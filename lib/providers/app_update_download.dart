import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/app_update_download.g.dart';

@Riverpod(keepAlive: true)
AppUpdateDownloadService appUpdateDownloadService(Ref ref) {
  final service = AppUpdateDownloadService();
  ref.onDispose(service.dispose);
  return service;
}

@Riverpod(keepAlive: true)
class AppUpdateDownload extends _$AppUpdateDownload {
  @override
  AppUpdateDownloadState build() {
    final service = ref.watch(appUpdateDownloadServiceProvider);
    ref.onDispose(service.cancel);
    return const AppUpdateDownloadState();
  }

  Future<void> download(AppUpdateRelease release) async {
    if (state.isBusy) return;
    final existing = state.release;
    if (state.status == AppUpdateDownloadStatus.ready &&
        existing?.packageKey == release.packageKey &&
        existing?.version == release.version &&
        existing?.downloadUri == release.downloadUri &&
        existing?.sha256 == release.sha256) {
      return;
    }
    state = AppUpdateDownloadState(
      release: release,
      status: AppUpdateDownloadStatus.downloading,
    );
    try {
      final path = await ref
          .read(appUpdateDownloadServiceProvider)
          .download(
            release,
            onProgress: (received, total) {
              if (!ref.mounted) return;
              state = AppUpdateDownloadState(
                release: release,
                status: AppUpdateDownloadStatus.downloading,
                receivedBytes: received,
                totalBytes: total,
              );
            },
            onVerifying: () {
              if (!ref.mounted) return;
              state = AppUpdateDownloadState(
                release: release,
                status: AppUpdateDownloadStatus.verifying,
                receivedBytes: state.receivedBytes,
                totalBytes: state.totalBytes,
              );
            },
          );
      if (!ref.mounted) return;
      state = AppUpdateDownloadState(
        release: release,
        status: AppUpdateDownloadStatus.ready,
        receivedBytes: state.receivedBytes,
        totalBytes: state.totalBytes,
        filePath: path,
      );
    } on AppUpdateDownloadCancelled {
      _cancelled(release);
    } on AppUpdateDownloadException catch (error) {
      _failed(release, error.failure);
    } catch (_) {
      _failed(release, AppUpdateDownloadFailure.downloadFailed);
    }
  }

  void cancel() {
    ref.read(appUpdateDownloadServiceProvider).cancel();
  }

  Future<void> install() async {
    final ready = state;
    final release = ready.release;
    if (release == null ||
        ready.isBusy ||
        ready.installerLaunched ||
        ready.filePath == null) {
      return;
    }
    state = AppUpdateDownloadState(
      release: release,
      status: AppUpdateDownloadStatus.verifying,
      receivedBytes: ready.receivedBytes,
      totalBytes: ready.totalBytes,
      filePath: ready.filePath,
    );
    try {
      await ref
          .read(appUpdateDownloadServiceProvider)
          .install(
            release,
            onVerified: () {
              if (!ref.mounted) return;
              state = AppUpdateDownloadState(
                release: release,
                status: AppUpdateDownloadStatus.installing,
                receivedBytes: ready.receivedBytes,
                totalBytes: ready.totalBytes,
                filePath: ready.filePath,
              );
            },
          );
      if (!ref.mounted) return;
      state = AppUpdateDownloadState(
        release: release,
        status: AppUpdateDownloadStatus.ready,
        receivedBytes: ready.receivedBytes,
        totalBytes: ready.totalBytes,
        filePath: ready.filePath,
        installerLaunched: true,
      );
    } on AppUpdateDownloadCancelled {
      _cancelled(release);
    } on AppUpdateDownloadException catch (error) {
      _failed(
        release,
        error.failure,
        filePath: error.failure == AppUpdateDownloadFailure.launchFailed
            ? ready.filePath
            : null,
      );
    } catch (_) {
      _failed(
        release,
        AppUpdateDownloadFailure.launchFailed,
        filePath: ready.filePath,
      );
    }
  }

  void _cancelled(AppUpdateRelease release) {
    if (!ref.mounted) return;
    state = AppUpdateDownloadState(
      release: release,
      status: AppUpdateDownloadStatus.cancelled,
    );
  }

  void _failed(
    AppUpdateRelease release,
    AppUpdateDownloadFailure failure, {
    String? filePath,
  }) {
    if (!ref.mounted) return;
    state = AppUpdateDownloadState(
      release: release,
      status: AppUpdateDownloadStatus.failed,
      failure: failure,
      filePath: filePath,
      receivedBytes: state.receivedBytes,
      totalBytes: state.totalBytes,
    );
  }
}
