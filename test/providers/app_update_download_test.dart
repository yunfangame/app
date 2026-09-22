import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  final bytes = utf8.encode('FengWo provider installer');

  AppUpdateRelease release({String version = '1.0.5', String? checksum}) =>
      AppUpdateRelease(
        packageKey: 'windows-x64',
        version: version,
        downloadUri: Uri.parse('https://example.com/FengWo-$version.exe'),
        releaseNotesHtml: '',
        sha256: checksum ?? sha256.convert(bytes).toString(),
      );

  ProviderContainer container({
    AppUpdateDownloadTransport? transport,
    AppUpdateInstallerLauncher? launcher,
    AppUpdateDownload? notifier,
    SystemAction? systemAction,
  }) {
    final service = AppUpdateDownloadService(
      temporaryDirectoryLoader: () async => temporary,
      packageKeyResolver: () => 'windows-x64',
      transport:
          transport ??
          (_, _) async => AppUpdateDownloadResponse(
            bytes: Stream.value(bytes),
            totalBytes: bytes.length,
          ),
      launcher: launcher ?? (_) async => true,
    );
    final value = ProviderContainer(
      overrides: [
        appUpdateDownloadServiceProvider.overrideWithValue(service),
        if (notifier != null)
          appUpdateDownloadProvider.overrideWith(() => notifier),
        if (systemAction != null)
          systemActionProvider.overrideWith(() => systemAction),
      ],
    );
    addTearDown(() {
      value.dispose();
      service.dispose();
    });
    if (notifier != null) value.read(appUpdateDownloadProvider);
    return value;
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'fengwo-provider-update-',
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'download lifecycle retains ready artifact after listeners close',
    () async {
      final providers = container();
      final statuses = <AppUpdateDownloadStatus>[];
      final subscription = providers.listen(
        appUpdateDownloadProvider,
        (_, next) => statuses.add(next.status),
        fireImmediately: true,
      );
      final notifier = providers.read(appUpdateDownloadProvider.notifier);
      await notifier.download(release());

      expect(
        statuses,
        containsAllInOrder([
          AppUpdateDownloadStatus.idle,
          AppUpdateDownloadStatus.downloading,
          AppUpdateDownloadStatus.verifying,
          AppUpdateDownloadStatus.ready,
        ]),
      );
      final ready = providers.read(appUpdateDownloadProvider);
      expect(ready.progress, 1);
      expect(ready.receivedBytes, bytes.length);
      expect(ready.isBusy, false);
      expect(ready.installerLaunched, false);
      expect(await File(ready.filePath!).readAsBytes(), bytes);

      subscription.close();
      await providers.pump();
      expect(providers.read(appUpdateDownloadProvider), same(ready));
    },
  );

  test('parallel clicks and dialog reopening do not redownload', () async {
    final response = Completer<AppUpdateDownloadResponse>();
    var requests = 0;
    final providers = container(
      transport: (_, _) {
        requests++;
        return response.future;
      },
    );
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    final target = release();
    final first = notifier.download(target);
    await notifier.download(target);
    await notifier.download(release(version: '1.0.6'));
    expect(providers.read(appUpdateDownloadProvider).release, same(target));
    response.complete(AppUpdateDownloadResponse(bytes: Stream.value(bytes)));
    await first;
    await notifier.download(target);
    expect(requests, 1);
  });

  test('failure is typed and download can be retried', () async {
    final providers = container();
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    await notifier.download(release(checksum: 'bad'));
    expect(
      providers.read(appUpdateDownloadProvider).failure,
      AppUpdateDownloadFailure.missingChecksum,
    );
    expect(
      providers.read(appUpdateDownloadProvider).status,
      AppUpdateDownloadStatus.failed,
    );
    await notifier.download(release());
    expect(
      providers.read(appUpdateDownloadProvider).status,
      AppUpdateDownloadStatus.ready,
    );
  });

  test('cancelled download is retained without an installable file', () async {
    final stream = StreamController<List<int>>();
    final started = Completer<void>();
    final providers = container(
      transport: (_, _) async {
        started.complete();
        return AppUpdateDownloadResponse(bytes: stream.stream);
      },
    );
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    final download = notifier.download(release());
    await started.future;
    notifier.cancel();
    await download;
    await stream.close();
    expect(
      providers.read(appUpdateDownloadProvider).status,
      AppUpdateDownloadStatus.cancelled,
    );
    expect(providers.read(appUpdateDownloadProvider).filePath, isNull);
  });

  test('installer launch is explicit, verified, and performed once', () async {
    final launched = Completer<bool>();
    final launching = Completer<void>();
    var launches = 0;
    final providers = container(
      launcher: (_) {
        launches++;
        launching.complete();
        return launched.future;
      },
    );
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    await notifier.download(release());
    expect(launches, 0);
    final install = notifier.install();
    await notifier.install();
    await launching.future;
    expect(
      providers.read(appUpdateDownloadProvider).status,
      AppUpdateDownloadStatus.installing,
    );
    launched.complete(true);
    await install;
    await notifier.install();
    final result = providers.read(appUpdateDownloadProvider);
    expect(launches, 1);
    expect(result.installerLaunched, true);
    expect(result.isBusy, false);
  });

  test('failed system launch can retry without downloading again', () async {
    var requests = 0;
    var launches = 0;
    final providers = container(
      transport: (_, _) async {
        requests++;
        return AppUpdateDownloadResponse(bytes: Stream.value(bytes));
      },
      launcher: (_) async => ++launches > 1,
    );
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    await notifier.download(release());
    await notifier.install();
    final failure = providers.read(appUpdateDownloadProvider);
    expect(failure.failure, AppUpdateDownloadFailure.launchFailed);
    expect(failure.filePath, isNotNull);
    await notifier.install();
    expect(requests, 1);
    expect(launches, 2);
    expect(providers.read(appUpdateDownloadProvider).installerLaunched, true);
  });

  test(
    'Windows waits for saving then launches and uses coordinated exit once',
    () async {
      final calls = <String>[];
      final saving = Completer<void>();
      final saved = Completer<void>();
      final action = _InstallerDownload(
        save: () async {
          calls.add('save');
          saving.complete();
          await saved.future;
          calls.add('saved');
        },
      );
      final providers = container(
        notifier: action,
        systemAction: _InstallerExit(calls),
        launcher: (_) async {
          calls.add('launch');
          return true;
        },
      );
      await action.download(release());
      final path = providers.read(appUpdateDownloadProvider).filePath!;
      final install = action.install();
      await saving.future;
      await action.install();
      expect(calls, ['save']);
      saved.complete();
      await install;
      await action.install();
      expect(calls, [
        'save',
        'saved',
        'launch',
        'cleanup:false',
        'window',
        'core',
        'exit',
      ]);
      expect(providers.read(appUpdateDownloadProvider).installerLaunched, true);
      expect(await File(path).exists(), isTrue);
    },
  );

  test(
    'Windows save failure prevents launch and exit but allows retry',
    () async {
      final calls = <String>[];
      var failSave = true;
      final action = _InstallerDownload(
        save: () async {
          calls.add('save');
          if (failSave) throw const FileSystemException('save failed');
        },
      );
      final providers = container(
        notifier: action,
        systemAction: _InstallerExit(calls),
        launcher: (_) async {
          calls.add('launch');
          return true;
        },
      );
      await action.download(release());
      await action.install();
      expect(calls, ['save']);
      final failure = providers.read(appUpdateDownloadProvider);
      expect(failure.failure, AppUpdateDownloadFailure.launchFailed);
      expect(failure.filePath, isNotNull);
      expect(failure.installerLaunched, isFalse);
      failSave = false;
      await action.install();
      expect(calls, [
        'save',
        'save',
        'launch',
        'cleanup:false',
        'window',
        'core',
        'exit',
      ]);
    },
  );

  test('Windows rejected launch keeps client running', () async {
    final calls = <String>[];
    final action = _InstallerDownload(save: () async => calls.add('save'));
    final providers = container(
      notifier: action,
      systemAction: _InstallerExit(calls),
      launcher: (_) async {
        calls.add('launch');
        return false;
      },
    );
    await action.download(release());
    await action.install();
    expect(calls, ['save', 'launch']);
    expect(
      providers.read(appUpdateDownloadProvider).failure,
      AppUpdateDownloadFailure.launchFailed,
    );
  });

  test('failed checksum does not save preferences or exit', () async {
    final calls = <String>[];
    final action = _InstallerDownload(save: () async => calls.add('save'));
    final providers = container(
      notifier: action,
      systemAction: _InstallerExit(calls),
      launcher: (_) async {
        calls.add('launch');
        return true;
      },
    );
    await action.download(release());
    await File(
      providers.read(appUpdateDownloadProvider).filePath!,
    ).writeAsString('tampered');
    await action.install();
    expect(calls, isEmpty);
    expect(
      providers.read(appUpdateDownloadProvider).failure,
      AppUpdateDownloadFailure.checksumMismatch,
    );
  });

  test('non-Windows installation does not use Windows save or exit', () async {
    final calls = <String>[];
    final action = _InstallerDownload(
      windows: false,
      save: () async => calls.add('save'),
    );
    final providers = container(
      notifier: action,
      systemAction: _InstallerExit(calls),
      launcher: (_) async {
        calls.add('launch');
        return true;
      },
    );
    await action.download(release());
    await action.install();
    expect(calls, ['launch']);
    expect(providers.read(appUpdateDownloadProvider).installerLaunched, isTrue);
  });

  test('tampered cached installer fails and never launches', () async {
    var launches = 0;
    final providers = container(
      launcher: (_) async {
        launches++;
        return true;
      },
    );
    final notifier = providers.read(appUpdateDownloadProvider.notifier);
    await notifier.download(release());
    await File(
      providers.read(appUpdateDownloadProvider).filePath!,
    ).writeAsString('changed');
    await notifier.install();
    final failure = providers.read(appUpdateDownloadProvider);
    expect(failure.failure, AppUpdateDownloadFailure.checksumMismatch);
    expect(failure.filePath, isNull);
    expect(launches, 0);
  });

  test(
    'missing cached installer clears install path and can redownload',
    () async {
      var requests = 0;
      final providers = container(
        transport: (_, _) async {
          requests++;
          return AppUpdateDownloadResponse(bytes: Stream.value(bytes));
        },
      );
      final notifier = providers.read(appUpdateDownloadProvider.notifier);
      await notifier.download(release());
      await File(providers.read(appUpdateDownloadProvider).filePath!).delete();
      await notifier.install();
      final failure = providers.read(appUpdateDownloadProvider);
      expect(failure.failure, AppUpdateDownloadFailure.checksumMismatch);
      expect(failure.filePath, isNull);
      await notifier.download(release());
      expect(requests, 2);
      expect(
        providers.read(appUpdateDownloadProvider).status,
        AppUpdateDownloadStatus.ready,
      );
    },
  );
}

class _InstallerDownload extends AppUpdateDownload {
  _InstallerDownload({required this.save, this.windows = true});

  final Future<void> Function() save;
  final bool windows;

  @override
  bool get exitForInstaller => windows;

  @override
  Future<void> saveBeforeInstaller() => save();
}

class _InstallerExit extends SystemAction {
  _InstallerExit(this.calls);

  final List<String> calls;

  @override
  Future<void> cleanupExitResources(bool needSave) async {
    calls.add('cleanup:$needSave');
  }

  @override
  Future<void> closeWindow() async => calls.add('window');

  @override
  Future<void> closeCore() async => calls.add('core');

  @override
  Future<void> exitApplication() async => calls.add('exit');
}
