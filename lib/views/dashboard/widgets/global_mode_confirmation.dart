import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> requestGlobalModeSwitch(
  BuildContext context,
  WidgetRef ref, {
  required bool skipConfirmation,
}) async {
  if (ref.read(patchClashConfigProvider).mode == Mode.global) return;
  if (!skipConfirmation) {
    final result = await showDialog<_GlobalModeDialogResult>(
      context: context,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.48),
      builder: (_) => const _GlobalModeConfirmationDialog(),
    );
    if (result?.confirmed != true || !context.mounted) return;
    if (result!.dontShowAgain) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(skipGlobalModeConfirmation: true));
    }
  }
  _switchToGlobalDirect(ref);
}

void _switchToGlobalDirect(WidgetRef ref) {
  const globalGroupName = 'GLOBAL';
  const directProxyName = 'DIRECT';
  final globalGroup = ref.read(groupsProvider).getGroup(globalGroupName);
  ref
      .read(profilesActionProvider.notifier)
      .updateCurrentSelectedMap(globalGroupName, directProxyName);
  ref.read(setupActionProvider.notifier).changeMode(Mode.global);
  final supportsDirect =
      globalGroup?.all.any((proxy) => proxy.name == directProxyName) == true;
  if (supportsDirect) {
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(globalGroupName, directProxyName);
  }
}

class _GlobalModeDialogResult {
  final bool confirmed;
  final bool dontShowAgain;

  const _GlobalModeDialogResult({
    required this.confirmed,
    required this.dontShowAgain,
  });
}

class _GlobalModeConfirmationDialog extends StatefulWidget {
  const _GlobalModeConfirmationDialog();

  @override
  State<_GlobalModeConfirmationDialog> createState() =>
      _GlobalModeConfirmationDialogState();
}

class _GlobalModeConfirmationDialogState
    extends State<_GlobalModeConfirmationDialog> {
  bool _dontShowAgain = false;

  void _close({required bool confirmed}) {
    Navigator.of(context).pop(
      _GlobalModeDialogResult(
        confirmed: confirmed,
        dontShowAgain: _dontShowAgain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = _GlobalModeDialogColors.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final actions = [
      _DialogActionButton(
        key: const ValueKey('global-mode-cancel'),
        colors: colors,
        label: l10n.cancel,
        onTap: () => _close(confirmed: false),
      ),
      _DialogActionButton(
        key: const ValueKey('global-mode-confirm'),
        colors: colors,
        label: l10n.switchAndDirect,
        icon: Icons.error_outline_rounded,
        emphasized: true,
        onTap: () => _close(confirmed: true),
      ),
    ];
    return Dialog(
      key: const ValueKey('global-mode-confirmation-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 32,
        vertical: narrow ? 18 : 28,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 610),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(narrow ? 28 : 36),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              narrow ? 20 : 38,
              narrow ? 20 : 32,
              narrow ? 20 : 38,
              narrow ? 22 : 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: narrow ? 62 : 74,
                      height: narrow ? 62 : 74,
                      decoration: BoxDecoration(
                        color: colors.warningSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.warningOutline),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: colors.warning,
                        size: narrow ? 34 : 40,
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey('global-mode-dialog-close'),
                      onPressed: () => _close(confirmed: false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                SizedBox(height: narrow ? 22 : 30),
                Text(
                  l10n.switchToGlobalMode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: narrow ? 27 : 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.globalModeWarningDescription,
                  textAlign: narrow ? TextAlign.left : TextAlign.center,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: narrow ? 15 : 17,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: narrow ? 20 : 26),
                Container(
                  padding: EdgeInsets.all(narrow ? 16 : 20),
                  decoration: BoxDecoration(
                    color: colors.infoSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: colors.text,
                            size: 23,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.whatHappensAfterSwitch,
                              style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        colors: colors,
                        icon: Icons.check_circle_outline_rounded,
                        label: l10n.dailyBrowsingRuleMode,
                      ),
                      const SizedBox(height: 13),
                      _InfoRow(
                        colors: colors,
                        icon: Icons.router_outlined,
                        label: l10n.proxyNeededChooseNode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  key: const ValueKey('global-mode-dont-show-row'),
                  onTap: () {
                    setState(() => _dontShowAgain = !_dontShowAgain);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          key: const ValueKey('global-mode-dont-show-checkbox'),
                          value: _dontShowAgain,
                          onChanged: (value) {
                            setState(() => _dontShowAgain = value ?? false);
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.dontShowAgain,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (narrow)
                  Column(
                    children: [
                      actions[1],
                      const SizedBox(height: 10),
                      actions[0],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: actions[0]),
                      const SizedBox(width: 14),
                      Expanded(child: actions[1]),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final _GlobalModeDialogColors colors;
  final IconData icon;
  final String label;

  const _InfoRow({
    required this.colors,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: colors.primary, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogActionButton extends StatelessWidget {
  final _GlobalModeDialogColors colors;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool emphasized;

  const _DialogActionButton({
    super.key,
    required this.colors,
    required this.label,
    required this.onTap,
    this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: emphasized
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.warning,
                foregroundColor: colors.onWarning,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 22),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : FilledButton.tonal(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onTap,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
    );
  }
}

class _GlobalModeDialogColors {
  final Color surface;
  final Color infoSurface;
  final Color text;
  final Color muted;
  final Color outline;
  final Color primary;
  final Color primarySoft;
  final Color warning;
  final Color onWarning;
  final Color warningSoft;
  final Color warningOutline;

  const _GlobalModeDialogColors({
    required this.surface,
    required this.infoSurface,
    required this.text,
    required this.muted,
    required this.outline,
    required this.primary,
    required this.primarySoft,
    required this.warning,
    required this.onWarning,
    required this.warningSoft,
    required this.warningOutline,
  });

  factory _GlobalModeDialogColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final warning = dark ? const Color(0xFFFFB94E) : const Color(0xFFE99A00);
    return _GlobalModeDialogColors(
      surface: scheme.surfaceContainerLowest,
      infoSurface: scheme.surfaceContainerLow,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.11),
      warning: warning,
      onWarning: dark ? const Color(0xFF392400) : Colors.white,
      warningSoft: warning.withValues(alpha: dark ? 0.18 : 0.09),
      warningOutline: warning.withValues(alpha: 0.45),
    );
  }
}
