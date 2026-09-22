import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloseConnectionsItem extends ConsumerWidget {
  const CloseConnectionsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final closeConnections = ref.watch(
      appSettingProvider.select((state) => state.closeConnections),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.autoCloseConnections),
      subtitle: Text(appLocalizations.autoCloseConnectionsDesc),
      value: closeConnections,
      onChanged: (value) async {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(closeConnections: value));
      },
    );
  }
}

class UsageItem extends ConsumerWidget {
  const UsageItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final onlyStatisticsProxy = ref.watch(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.onlyStatisticsProxy),
      subtitle: Text(appLocalizations.onlyStatisticsProxyDesc),
      value: onlyStatisticsProxy,
      onChanged: (bool value) async {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(onlyStatisticsProxy: value));
      },
    );
  }
}

class MinimizeItem extends ConsumerWidget {
  const MinimizeItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final minimizeOnExit = ref.watch(
      appSettingProvider.select((state) => state.minimizeOnExit),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.minimizeOnExit),
      subtitle: Text(appLocalizations.minimizeOnExitDesc),
      value: minimizeOnExit,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(minimizeOnExit: value));
      },
    );
  }
}

class AutoLaunchItem extends ConsumerStatefulWidget {
  const AutoLaunchItem({super.key});

  static bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };

  @override
  ConsumerState<AutoLaunchItem> createState() => _AutoLaunchItemState();
}

class _AutoLaunchItemState extends ConsumerState<AutoLaunchItem> {
  bool _refreshing = true;
  bool _applying = false;
  bool _readFailed = false;
  String? _errorCode;

  bool get _busy => _refreshing || _applying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AutoLaunchItem.isSupported) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_applying) return;
    setState(() {
      _refreshing = true;
      _errorCode = null;
    });
    try {
      await ref.read(systemActionProvider.notifier).refreshAutoLaunch();
      if (mounted) setState(() => _readFailed = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _readFailed = true;
          _errorCode = error is AutoLaunchException ? error.code : 'readFailed';
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_busy || _readFailed) return;
    setState(() {
      _applying = true;
      _errorCode = null;
    });
    try {
      await ref.read(systemActionProvider.notifier).setAutoLaunch(enabled);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorCode = error is AutoLaunchException
              ? error.code
              : 'changeFailed';
          _readFailed =
              _errorCode == 'readFailed' || _errorCode == 'rollbackFailed';
        });
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _errorText(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (_errorCode) {
      'readFailed' => l10n.autoLaunchReadFailed,
      'verificationFailed' => l10n.autoLaunchVerificationFailed,
      'persistenceFailed' => l10n.autoLaunchPersistenceFailed,
      'rollbackFailed' => l10n.autoLaunchRollbackFailed,
      _ => l10n.autoLaunchFailed,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!AutoLaunchItem.isSupported) return const SizedBox.shrink();
    final l10n = context.appLocalizations;
    final autoLaunch = ref.watch(
      appSettingProvider.select((state) => state.autoLaunch),
    );
    final enabled = !_busy && !_readFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListItem(
          title: Text(l10n.autoLaunch),
          subtitle: Text(
            _refreshing
                ? l10n.autoLaunchReading
                : _applying
                ? l10n.autoLaunchApplying
                : l10n.autoLaunchDesc,
          ),
          onTap: enabled ? () => _setEnabled(!autoLaunch) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                SizedBox.square(
                  key: const ValueKey('auto-launch-progress'),
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: _refreshing
                        ? l10n.autoLaunchReading
                        : l10n.autoLaunchApplying,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Switch(
                key: const ValueKey('auto-launch-switch'),
                value: autoLaunch,
                onChanged: enabled ? _setEnabled : null,
              ),
            ],
          ),
        ),
        if (_errorCode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _errorText(context),
                    key: const ValueKey('auto-launch-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                if (_readFailed) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('auto-launch-retry'),
                    onPressed: _busy ? null : _refresh,
                    child: Text(l10n.retry),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class SilentLaunchItem extends ConsumerWidget {
  const SilentLaunchItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final silentLaunch = ref.watch(
      appSettingProvider.select((state) => state.silentLaunch),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.silentLaunch),
      subtitle: Text(appLocalizations.silentLaunchDesc),
      value: silentLaunch,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(silentLaunch: value));
      },
    );
  }
}

class AutoRunItem extends ConsumerWidget {
  const AutoRunItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final autoRun = ref.watch(
      appSettingProvider.select((state) => state.autoRun),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.autoRun),
      subtitle: Text(appLocalizations.autoRunDesc),
      value: autoRun,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoRun: value));
      },
    );
  }
}

class HiddenItem extends ConsumerWidget {
  const HiddenItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final hidden = ref.watch(
      appSettingProvider.select((state) => state.hidden),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.exclude),
      subtitle: Text(appLocalizations.excludeDesc),
      value: hidden,
      onChanged: (value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(hidden: value));
      },
    );
  }
}

class AnimateTabItem extends ConsumerWidget {
  const AnimateTabItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final isAnimateToPage = ref.watch(
      appSettingProvider.select((state) => state.isAnimateToPage),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.tabAnimation),
      subtitle: Text(appLocalizations.tabAnimationDesc),
      value: isAnimateToPage,
      onChanged: (value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(isAnimateToPage: value));
      },
    );
  }
}

class OpenLogsItem extends ConsumerWidget {
  const OpenLogsItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final openLogs = ref.watch(
      appSettingProvider.select((state) => state.openLogs),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.logcat),
      subtitle: Text(appLocalizations.logcatDesc),
      value: openLogs,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(openLogs: value));
      },
    );
  }
}

class CrashlyticsItem extends ConsumerWidget {
  const CrashlyticsItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final crashlytics = ref.watch(
      appSettingProvider.select((state) => state.crashlytics),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.crashlytics),
      subtitle: Text(appLocalizations.crashlyticsTip),
      value: crashlytics,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(crashlytics: value));
      },
    );
  }
}

class AutoCheckUpdateItem extends ConsumerWidget {
  const AutoCheckUpdateItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final autoCheckUpdate = ref.watch(
      appSettingProvider.select((state) => state.autoCheckUpdate),
    );
    return ListItem.toggle(
      title: Text(appLocalizations.autoCheckUpdate),
      subtitle: Text(appLocalizations.autoCheckUpdateDesc),
      value: autoCheckUpdate,
      onChanged: (bool value) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: value));
      },
    );
  }
}

class ApplicationSettingView extends StatelessWidget {
  const ApplicationSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [
      const MinimizeItem(),
      if (system.isDesktop) ...[
        const AutoLaunchItem(),
        const SilentLaunchItem(),
      ],
      const AutoRunItem(),
      if (system.isAndroid) ...[const HiddenItem()],
      const AnimateTabItem(),
      const OpenLogsItem(),
      const CloseConnectionsItem(),
      const UsageItem(),
      if (system.isAndroid) const CrashlyticsItem(),
      if (!system.isDesktop) const AutoCheckUpdateItem(),
    ];
    return BaseScaffold(
      title: context.appLocalizations.application,
      body: ListView.separated(
        itemBuilder: (_, index) {
          final item = items[index];
          return item;
        },
        separatorBuilder: (_, _) {
          return const Divider(height: 0);
        },
        itemCount: items.length,
      ),
    );
  }
}
