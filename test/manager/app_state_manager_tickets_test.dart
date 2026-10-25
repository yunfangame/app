import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/ticket_fixtures.dart';

class _SetupAction extends SetupAction {
  @override
  void build() {}

  @override
  void tryCheckIp() {}
}

class _ManagerRig {
  late final controller = XboardTicketController(
    summaryPollingEnabled: false,
    pollJitterSeconds: () => 0,
    now: TestWidgetsFlutterBinding.instance.clock.now,
    api: XboardTicketApi(
      requester: (_, _, _) async =>
          throw StateError('unexpected ticket request'),
    ),
  );
  late final ProviderContainer container;

  Future<void> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('wifi_ssid'),
      (_) async => 0,
    );
    container = ProviderContainer(
      overrides: [
        setupActionProvider.overrideWith(_SetupAction.new),
        configProvider.overrideWith(
          (_) => const Config(themeProps: defaultThemeProps),
        ),
        checkIpProvider.overrideWith((_) => const VM3(false, 0, false)),
        needUpdateGroupsProvider.overrideWith(
          (_) => const VM3(false, 0, ProxiesSortType.none),
        ),
        suspendProvider.overrideWith((_) => false),
        autoSetSystemDnsStateProvider.overrideWith(
          (_) => const VM2(false, false),
        ),
      ],
    );
    globalState.container = container;
    globalState.setOfflineMode(false);
    globalState.activateXboardSession(ticketSession());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppStateManager(
          ticketController: controller,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      globalState.clearXboardSession();
      globalState.setOfflineMode(false);
      container.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('wifi_ssid'),
        null,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      ApiHealthService.setAppForeground(true);
    });
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(Duration.zero);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }
}

void main() {
  testWidgets(
    'real AppStateManager resume preserves a closed detail deadline and manual refresh remains immediate',
    (tester) async {
      final rig = _ManagerRig();
      await rig.mount(tester);
      var calls = 0;
      rig.controller.setViewActive(
        Object(),
        true,
        detailInterval: const Duration(minutes: 5),
        refresh: () async {
          calls++;
          return true;
        },
      );
      for (var count = 0; count < 10; count++) {
        await tester.pump(const Duration(seconds: 20));
        await rig.resume(tester);
        expect(calls, 0);
      }
      await tester.pump(const Duration(seconds: 99));
      expect(calls, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      rig.controller.refreshNow();
      await tester.pump(Duration.zero);
      expect(calls, 2);
    },
  );

  testWidgets(
    'real AppStateManager resume cannot bypass active detail failure backoff',
    (tester) async {
      final rig = _ManagerRig();
      await rig.mount(tester);
      var calls = 0;
      rig.controller.setViewActive(
        Object(),
        true,
        detailInterval: const Duration(seconds: 30),
        refresh: () async {
          calls++;
          return false;
        },
      );
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      for (var count = 0; count < 10; count++) {
        await tester.pump(const Duration(seconds: 20));
        await rig.resume(tester);
        expect(calls, 1);
      }
      await tester.pump(const Duration(seconds: 39));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      rig.controller.refreshNow();
      await tester.pump(Duration.zero);
      expect(calls, 3);
    },
  );
}
