import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class DashboardSubscriptionRefreshButton extends StatefulWidget {
  const DashboardSubscriptionRefreshButton({super.key, this.onRefresh});

  final Future<bool> Function()? onRefresh;

  @override
  State<DashboardSubscriptionRefreshButton> createState() =>
      _DashboardSubscriptionRefreshButtonState();
}

class _DashboardSubscriptionRefreshButtonState
    extends State<DashboardSubscriptionRefreshButton> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    final callback = widget.onRefresh ?? globalState.refreshXboardSubscription;
    if (callback == null ||
        globalState.xboardSession == null ||
        globalState.isOfflineMode) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final refreshed = await callback();
      if (!refreshed && mounted) {
        context.showNotifier(context.appLocalizations.requestFailed);
      }
    } catch (_) {
      if (mounted) {
        context.showNotifier(context.appLocalizations.requestFailed);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !_refreshing &&
        !globalState.isOfflineMode &&
        globalState.xboardSession != null &&
        (widget.onRefresh != null ||
            globalState.refreshXboardSubscription != null);
    return IconButton(
      key: const ValueKey('fengwo-dashboard-traffic-refresh'),
      onPressed: enabled ? _refresh : null,
      tooltip: context.appLocalizations.refreshSubscription,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: _refreshing
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 20),
    );
  }
}
