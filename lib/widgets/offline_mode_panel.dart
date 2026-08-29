import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class OfflineModeFeaturePanel extends StatefulWidget {
  const OfflineModeFeaturePanel({super.key});

  @override
  State<OfflineModeFeaturePanel> createState() =>
      _OfflineModeFeaturePanelState();
}

class _OfflineModeFeaturePanelState extends State<OfflineModeFeaturePanel> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await globalState.restoreOnlineMode?.call();
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            key: const ValueKey('offline-feature-panel'),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 54, color: colors.primary),
                const SizedBox(height: 18),
                Text(
                  context.appLocalizations.offlineMode,
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.appLocalizations.onlineFeaturesUnavailableOffline,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('offline-feature-restore-button'),
                  onPressed: _busy ? null : _restore,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: Text(
                    _busy
                        ? context.appLocalizations.restoringOnline
                        : context.appLocalizations.restoreOnline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
