import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/views.dart';
import 'package:flutter/material.dart';

class Navigation {
  static Navigation? _instance;

  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        keep: false,
        icon: const Icon(Icons.home_outlined),
        label: PageLabel.dashboard,
        builder: (_) =>
            const DashboardView(key: GlobalObjectKey(PageLabel.dashboard)),
      ),
      NavigationItem(
        icon: const Icon(Icons.shopping_cart_outlined),
        label: PageLabel.profiles,
        builder: (_) => const FengWoPurchasePlansView(
          key: GlobalObjectKey(PageLabel.profiles),
        ),
      ),
      NavigationItem(
        icon: const Icon(Icons.tune_rounded),
        label: PageLabel.proxies,
        builder: (_) =>
            const FengWoNodeStatusView(key: GlobalObjectKey(PageLabel.proxies)),
      ),
      NavigationItem(
        icon: const Icon(Icons.show_chart_rounded),
        label: PageLabel.connections,
        builder: (_) => const FengWoConnectionsView(
          key: GlobalObjectKey(PageLabel.connections),
        ),
        description: 'connectionsDesc',
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.pie_chart_outline_rounded),
        label: PageLabel.traffic,
        builder: (_) => const FengWoTrafficDetailsView(
          key: GlobalObjectKey(PageLabel.traffic),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.receipt_long_outlined),
        label: PageLabel.orders,
        builder: (_) =>
            const FengWoOrdersView(key: GlobalObjectKey(PageLabel.orders)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.card_giftcard_outlined),
        label: PageLabel.invite,
        builder: (_) => const FengWoInvitePromotionView(
          key: GlobalObjectKey(PageLabel.invite),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.person_outline_rounded),
        label: PageLabel.tools,
        builder: (_) => const FengWoPersonalCenterView(
          key: GlobalObjectKey(PageLabel.tools),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.settings_outlined),
        label: PageLabel.resources,
        builder: (_) => const FengWoAdvancedSettingsView(
          key: GlobalObjectKey(PageLabel.resources),
        ),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.business_center_outlined),
        label: PageLabel.practicalTools,
        builder: (_) =>
            const ToolsView(key: GlobalObjectKey(PageLabel.practicalTools)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
      NavigationItem(
        icon: const Icon(Icons.view_timeline),
        label: PageLabel.requests,
        builder: (_) =>
            const RequestsView(key: GlobalObjectKey(PageLabel.requests)),
        description: 'requestsDesc',
        modes: const [NavigationItemMode.more],
      ),
      NavigationItem(
        icon: const Icon(Icons.adb),
        label: PageLabel.logs,
        builder: (_) => const LogsView(key: GlobalObjectKey(PageLabel.logs)),
        description: 'logsDesc',
        modes: openLogs ? const [NavigationItemMode.more] : const [],
      ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
