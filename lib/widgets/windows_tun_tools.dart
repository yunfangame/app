import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WindowsTunToolsButton extends ConsumerStatefulWidget {
  const WindowsTunToolsButton({super.key});

  @override
  ConsumerState<WindowsTunToolsButton> createState() =>
      _WindowsTunToolsButtonState();
}

class _WindowsTunToolsButtonState extends ConsumerState<WindowsTunToolsButton> {
  bool _busy = false;

  Future<void> _showTools() async {
    final l10n = context.appLocalizations;
    final choice = await globalState.showCommonDialog<String>(
      context: context,
      child: Builder(
        builder: (context) => AlertDialog(
          title: Text(l10n.tunTools),
          content: Text(l10n.tunToolsDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'logs'),
              child: Text(l10n.exportLogs),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'repair'),
              child: Text(l10n.tunRepairService),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => _busy = true);
    try {
      if (choice == 'logs') {
        await ref.read(logsProvider.notifier).exportLogs();
      } else {
        final repaired = await ref
            .read(setupActionProvider.notifier)
            .repairTunService();
        if (mounted && repaired) globalState.showNotifier(l10n.tunServiceReady);
      }
    } catch (error) {
      commonPrint.event('tun.tools.failed', fields: {'error': '$error'});
      if (mounted) globalState.showNotifier(l10n.tunServiceUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('windows-tun-tools'),
      tooltip: context.appLocalizations.tunTools,
      onPressed: _busy ? null : _showTools,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.build_outlined, size: 18),
    );
  }
}
