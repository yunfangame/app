import 'dart:async';

import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _downloadDialogs = Expando<Future<void>>();

Future<void> showAppUpdateDownloadDialog({
  required BuildContext context,
  required AppUpdateRelease release,
  bool startDownload = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final existing = _downloadDialogs[navigator];
  if (existing != null) return existing;
  final future = showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) =>
        AppUpdateDownloadDialog(release: release, startDownload: startDownload),
  ).whenComplete(() => _downloadDialogs[navigator] = null);
  _downloadDialogs[navigator] = future;
  return future;
}

class AppUpdateDownloadDialog extends ConsumerStatefulWidget {
  const AppUpdateDownloadDialog({
    super.key,
    required this.release,
    this.startDownload = true,
  });

  final AppUpdateRelease release;
  final bool startDownload;

  @override
  ConsumerState<AppUpdateDownloadDialog> createState() =>
      _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState
    extends ConsumerState<AppUpdateDownloadDialog> {
  @override
  void initState() {
    super.initState();
    if (widget.startDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref
                .read(appUpdateDownloadProvider.notifier)
                .download(widget.release),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateDownloadProvider);
    final notifier = ref.read(appUpdateDownloadProvider.notifier);
    final release = state.release ?? widget.release;
    final l10n = context.appLocalizations;
    final opening = state.status == AppUpdateDownloadStatus.installing;
    final ready = state.status == AppUpdateDownloadStatus.ready;
    final failed = state.status == AppUpdateDownloadStatus.failed;
    final cancelled = state.status == AppUpdateDownloadStatus.cancelled;
    return AlertDialog(
      key: const ValueKey('app-update-download-dialog'),
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      icon: const Icon(Icons.system_update_alt_rounded, size: 32),
      title: Text(l10n.appUpdateDownload),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              release.title ?? l10n.softwareUpdate,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'v${release.version.replaceFirst(RegExp(r'^[vV]'), '').split('+').first}',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            AppUpdateDownloadProgressView(state: state),
          ],
        ),
      ),
      actions: [
        if (state.isBusy && !opening)
          TextButton(
            key: const ValueKey('app-update-download-cancel'),
            onPressed: notifier.cancel,
            child: Text(l10n.appUpdateCancelDownload),
          ),
        TextButton(
          key: const ValueKey('app-update-download-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(
            state.isBusy ? l10n.appUpdateBackground : l10n.closeAction,
          ),
        ),
        if (ready && !state.installerLaunched)
          FilledButton.icon(
            key: const ValueKey('app-update-install'),
            onPressed: notifier.install,
            icon: const Icon(Icons.install_desktop_rounded, size: 18),
            label: Text(l10n.appUpdateInstall),
          ),
        if (failed || cancelled || state.status == AppUpdateDownloadStatus.idle)
          FilledButton.icon(
            key: const ValueKey('app-update-download-retry'),
            onPressed: () {
              if (state.failure == AppUpdateDownloadFailure.launchFailed) {
                unawaited(notifier.install());
              } else {
                unawaited(notifier.download(release));
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l10n.appUpdateRetry),
          ),
      ],
    );
  }
}

class AppUpdateDownloadProgressView extends StatelessWidget {
  const AppUpdateDownloadProgressView({super.key, required this.state});

  final AppUpdateDownloadState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    final progress = state.progress;
    final failed = state.status == AppUpdateDownloadStatus.failed;
    final message = switch (state.status) {
      AppUpdateDownloadStatus.downloading => l10n.appUpdateDownloading,
      AppUpdateDownloadStatus.verifying => l10n.appUpdateVerifying,
      AppUpdateDownloadStatus.ready =>
        state.installerLaunched
            ? l10n.appUpdateInstallerOpened
            : l10n.appUpdateDownloadReady,
      AppUpdateDownloadStatus.cancelled => l10n.appUpdateDownloadCancelled,
      AppUpdateDownloadStatus.installing => l10n.appUpdateInstalling,
      AppUpdateDownloadStatus.failed => switch (state.failure) {
        AppUpdateDownloadFailure.missingChecksum =>
          l10n.appUpdateChecksumMissing,
        AppUpdateDownloadFailure.checksumMismatch =>
          l10n.appUpdateChecksumMismatch,
        AppUpdateDownloadFailure.launchFailed =>
          l10n.appUpdateInstallerOpenFailed,
        AppUpdateDownloadFailure.unsupportedPackage =>
          l10n.appUpdateUnsupportedPackage,
        _ => l10n.appUpdateDownloadFailed,
      },
      AppUpdateDownloadStatus.idle => l10n.appUpdateDownload,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            message,
            key: const ValueKey('app-update-download-status'),
            style: context.textTheme.bodyMedium?.copyWith(
              color: failed ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
        if (state.isBusy) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            key: const ValueKey('app-update-download-progress'),
            value: state.status == AppUpdateDownloadStatus.downloading
                ? progress
                : null,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            semanticsLabel: message,
          ),
        ],
        if (state.receivedBytes > 0 ||
            state.status == AppUpdateDownloadStatus.downloading) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                state.totalBytes == null
                    ? state.receivedBytes.traffic.show
                    : l10n.appUpdateProgress(
                        state.receivedBytes.traffic.show,
                        state.totalBytes!.traffic.show,
                      ),
                key: const ValueKey('app-update-download-bytes'),
                style: context.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (progress != null &&
                  state.status == AppUpdateDownloadStatus.downloading)
                Text(
                  '${(progress * 100).floor()}%',
                  key: const ValueKey('app-update-download-percentage'),
                  style: context.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
