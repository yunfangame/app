import 'dart:async';

import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/app_update_download_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String formatAppUpdateVersion(String? version) {
  if (version == null || version.trim().isEmpty) return '—';
  return 'v${version.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first}';
}

class AppUpdateBadge extends ConsumerWidget {
  const AppUpdateBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUpdate = ref.watch(
      appUpdateProvider.select((state) => state.hasUpdate),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: child),
        if (hasUpdate) ...[
          const SizedBox(width: 8),
          Semantics(
            label: context.appLocalizations.discoverNewVersion,
            child: const DecoratedBox(
              key: ValueKey('app-update-red-dot'),
              decoration: BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: 8),
            ),
          ),
        ],
      ],
    );
  }
}

class AppUpdateSettingsContent extends ConsumerStatefulWidget {
  const AppUpdateSettingsContent({super.key});

  @override
  ConsumerState<AppUpdateSettingsContent> createState() =>
      _AppUpdateSettingsContentState();
}

class _AppUpdateSettingsContentState
    extends ConsumerState<AppUpdateSettingsContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final update = ref.read(appUpdateProvider);
      final checkedAt = update.checkedAt;
      if (update.status == AppUpdateStatus.idle ||
          (checkedAt != null &&
              DateTime.now().difference(checkedAt) >
                  const Duration(minutes: 10))) {
        unawaited(ref.read(appUpdateProvider.notifier).check());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider);
    final download = ref.watch(appUpdateDownloadProvider);
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    final version = formatAppUpdateVersion(
      ref.watch(appUpdateCurrentVersionProvider),
    );
    final checkButton = FilledButton.icon(
      key: const ValueKey('advanced-check-update'),
      onPressed: update.isChecking
          ? null
          : () => ref
                .read(commonActionProvider.notifier)
                .checkAppUpdate(isUser: true),
      icon: update.isChecking
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(
        update.isChecking ? l10n.appUpdateChecking : l10n.checkUpdate,
      ),
    );
    final heading = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.system_update_alt_rounded,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppUpdateBadge(
                key: const ValueKey('software-update-badge'),
                child: Text(
                  l10n.softwareUpdate,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.appUpdateCurrentVersion(version),
                key: const ValueKey('advanced-current-version'),
                style: context.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final feedback = switch (update.status) {
      AppUpdateStatus.upToDate => l10n.appUpdateLatest(version),
      AppUpdateStatus.available => l10n.appUpdateAvailable(
        formatAppUpdateVersion(update.release?.version),
      ),
      AppUpdateStatus.unavailable => l10n.appUpdateUnavailable,
      AppUpdateStatus.failed => l10n.appUpdateFailed,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 430) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: checkButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 20),
                checkButton,
              ],
            );
          },
        ),
        if (feedback != null) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              feedback,
              key: const ValueKey('app-update-check-feedback'),
              style: context.textTheme.bodySmall?.copyWith(
                color: update.status == AppUpdateStatus.failed
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (download.release != null &&
            download.status != AppUpdateDownloadStatus.idle) ...[
          const Divider(height: 30),
          Text(
            '${l10n.appUpdateDownload} · ${formatAppUpdateVersion(download.release!.version)}',
            key: const ValueKey('advanced-update-download-version'),
            style: context.textTheme.labelLarge,
          ),
          const SizedBox(height: 10),
          AppUpdateDownloadProgressView(state: download),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: const ValueKey('advanced-update-download-details'),
              onPressed: () => showAppUpdateDownloadDialog(
                context: context,
                release: download.release!,
                startDownload: false,
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(l10n.appUpdateDownloadDetails),
            ),
          ),
        ],
      ],
    );
  }
}
