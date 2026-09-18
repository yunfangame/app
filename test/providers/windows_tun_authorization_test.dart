import 'dart:async';

import 'package:fl_clash/common/tun_failure.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _AuthorizationSetup action;

  setUp(() {
    container = ProviderContainer(
      overrides: [setupActionProvider.overrideWith(_AuthorizationSetup.new)],
    );
    action =
        container.read(setupActionProvider.notifier) as _AuthorizationSetup;
    container
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith.tun(enable: true));
  });
  tearDown(() => container.dispose());

  for (final code in [1223, 5, 2, 577, 1275, 9999]) {
    test('elevation error $code is actionable and retryable', () async {
      final failure = TunFailure.elevation(code);
      action.failure = failure;
      await expectLater(action.requestAdmin(true), throwsA(same(failure)));
      expect(action.reportTunFailure(failure), isTrue);
      expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
      expect(failure.toDiagnosticData()['os_error_code'], code);
      expect(action.notifications, [failure.code]);
      action.failure = null;
      container
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith.tun(enable: true));
      expect(await action.requestAdmin(true), isFalse);
      expect(action.calls, 2);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.authorized,
      );
    });
  }

  test(
    'failed authorization never silently continues with TUN disabled',
    () async {
      action.result = AuthorizeCode.error;
      await expectLater(action.requestAdmin(true), throwsA(isA<TunFailure>()));
      expect(container.read(windowsTunReadyProvider), isFalse);
    },
  );

  test('ready helper is reused without another authorization', () async {
    container.read(authorizedTunEnableProvider.notifier).value =
        TunAuthorizationState.authorized;
    action.ready = true;
    expect(await action.requestAdmin(true), isTrue);
    expect(action.calls, 0);
  });

  test(
    'cached authorization rechecks a stopped or mismatched service',
    () async {
      container.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.authorized;
      action.ready = false;
      expect(await action.requestAdmin(true), isFalse);
      expect(action.calls, 1);
    },
  );

  test(
    'turning TUN off while authorization is pending discards late result',
    () async {
      action.pending = Completer<AuthorizeCode>();
      final requesting = action.requestAdmin(true);
      await action.entered.future;
      container
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith.tun(enable: false));
      action.pending!.completeError(TunFailure.elevation(1223));
      expect(await requesting, isTrue);
      expect(action.notifications, isEmpty);
      expect(container.read(windowsTunReadyProvider), isFalse);
    },
  );

  test('repair requests coalesce and do not enable TUN', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith.tun(enable: false));
    action.pending = Completer<AuthorizeCode>();
    final first = action.repairTunService();
    final second = action.repairTunService();
    await action.entered.future;
    expect(action.calls, 1);
    action.pending!.complete(AuthorizeCode.none);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(container.read(patchClashConfigProvider).tun.enable, isFalse);
    expect(container.read(windowsTunReadyProvider), isFalse);
  });
}

class _AuthorizationSetup extends SetupAction {
  int calls = 0;
  bool ready = false;
  Object? failure;
  AuthorizeCode result = AuthorizeCode.success;
  Completer<AuthorizeCode>? pending;
  final entered = Completer<void>();
  final notifications = <String>[];

  @override
  bool get requiresListenerReadiness => true;

  @override
  Future<bool> isTunServiceReady() async => ready;

  @override
  Future<AuthorizeCode> authorizeCore() async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    if (failure != null) throw failure!;
    return await pending?.future ?? result;
  }

  @override
  void notifyTunFailure(String code) => notifications.add(code);
}
