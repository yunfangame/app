import 'dart:math' as math;

import 'package:fl_clash/common/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateDecision { update, later, ignoreVersion }

Future<AppUpdateDecision?> showAppUpdateDialog({
  required BuildContext context,
  required AppUpdateRelease release,
  required String currentVersion,
}) {
  return showDialog<AppUpdateDecision>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (_) =>
        AppUpdateDialog(release: release, currentVersion: currentVersion),
  );
}

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  final AppUpdateRelease release;
  final String currentVersion;

  Future<void> _openHtmlLink(String? value) async {
    final parsed = Uri.tryParse(value?.trim() ?? '');
    if (parsed == null) return;
    final target = parsed.hasScheme
        ? parsed
        : release.downloadUri.resolveUri(parsed);
    if (!{'http', 'https'}.contains(target.scheme)) return;
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final width = math.min(620.0, mediaSize.width - 24);
    final height = math.min(680.0, mediaSize.height - 24);
    final compact = width < 480 || height < 540;
    return Dialog(
      key: const ValueKey('app-update-dialog'),
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 24 : 32),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: EdgeInsets.all(compact ? 18 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 48 : 58,
                    height: compact ? 48 : 58,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: scheme.onPrimaryContainer,
                      size: compact ? 28 : 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          release.title ?? '发现新版本',
                          key: const ValueKey('app-update-title'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '当前 $currentVersion  →  最新 ${release.version}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('app-update-close'),
                    tooltip: '稍后提醒',
                    onPressed: () =>
                        Navigator.pop(context, AppUpdateDecision.later),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              SizedBox(height: compact ? 14 : 22),
              Divider(color: scheme.outlineVariant),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('app-update-html-scroll'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Html(
                    data: release.releaseNotesHtml,
                    style: {
                      'body': Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                        color: scheme.onSurfaceVariant,
                        fontSize: FontSize(compact ? 15 : 17),
                        lineHeight: const LineHeight(1.55),
                      ),
                      'h1': Style(color: scheme.onSurface),
                      'h2': Style(color: scheme.onSurface),
                      'h3': Style(color: scheme.onSurface),
                      'a': Style(
                        color: scheme.primary,
                        textDecoration: TextDecoration.underline,
                      ),
                    },
                    onLinkTap: (url, _, _) => _openHtmlLink(url),
                  ),
                ),
              ),
              Divider(color: scheme.outlineVariant),
              SizedBox(height: compact ? 8 : 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('app-update-ignore'),
                    onPressed: () =>
                        Navigator.pop(context, AppUpdateDecision.ignoreVersion),
                    child: const Text('不再提示此版本'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('app-update-later'),
                    onPressed: () =>
                        Navigator.pop(context, AppUpdateDecision.later),
                    child: const Text('稍后提醒'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('app-update-confirm'),
                    onPressed: () =>
                        Navigator.pop(context, AppUpdateDecision.update),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('立即更新'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
