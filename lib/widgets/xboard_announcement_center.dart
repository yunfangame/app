import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class XboardAnnouncementCenterHost extends ConsumerStatefulWidget {
  const XboardAnnouncementCenterHost({
    super.key,
    required this.child,
    this.authService,
    this.preferenceStore,
    this.now,
  });

  final Widget child;
  final XboardAuthService? authService;
  final XboardNoticePreferenceStore? preferenceStore;
  final DateTime Function()? now;

  @override
  ConsumerState<XboardAnnouncementCenterHost> createState() =>
      _XboardAnnouncementCenterHostState();
}

class _XboardAnnouncementCenterHostState
    extends ConsumerState<XboardAnnouncementCenterHost> {
  late final XboardAuthService _authService;
  late final XboardNoticePreferenceStore _preferenceStore;
  late final XboardAnnouncementRequest _requestHandler;
  final _automaticallyShownDays = <String>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    _preferenceStore = widget.preferenceStore ?? XboardNoticePreferenceStore();
    _requestHandler = ({required automatic}) {
      if (automatic) globalState.consumeXboardAnnouncementAutoPrompt();
      if (mounted) unawaited(_showAnnouncements(automatic: automatic));
    };
    globalState.showXboardAnnouncements = _requestHandler;
    ref.listenManual(isStartProvider, (previous, next) {
      if (previous != true && next) {
        globalState.requestXboardAnnouncementAutoPrompt();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !globalState.consumeXboardAnnouncementAutoPrompt()) {
        return;
      }
      unawaited(_showAnnouncements(automatic: true));
    });
  }

  @override
  void dispose() {
    if (identical(globalState.showXboardAnnouncements, _requestHandler)) {
      globalState.showXboardAnnouncements = null;
    }
    super.dispose();
  }

  String _accountId(XboardLoginResult session) {
    final account = session.subscription.email?.trim().toLowerCase();
    final uuid = session.subscription.uuid?.trim();
    return '${session.endpoint.origin}|${account ?? uuid ?? session.authData}';
  }

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  String _automaticShowKey(int revision) {
    final date = _now.toLocal();
    return '$revision|${date.year}-${date.month}-${date.day}';
  }

  Future<void> _showAnnouncements({required bool automatic}) async {
    if (_showing || !mounted) return;
    final session = globalState.xboardSession;
    if (session == null ||
        session.authData.isEmpty ||
        globalState.isOfflineMode) {
      if (!automatic && mounted) {
        context.showNotifier(
          context.appLocalizations.announcementUnavailableOffline,
        );
      }
      return;
    }
    final revision = globalState.xboardSessionRevision;
    final accountId = _accountId(session);
    final automaticShowKey = _automaticShowKey(revision);
    if (automatic && _automaticallyShownDays.contains(automaticShowKey)) {
      return;
    }
    _showing = true;
    try {
      final suppressed = await _preferenceStore.isSuppressedToday(
        accountId,
        now: _now,
      );
      if (automatic && suppressed) return;
      final allNotices = await _authService.fetchNotices(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!mounted || !globalState.isActiveXboardSession(session, revision)) {
        return;
      }
      final notices = automatic
          ? allNotices.where((notice) => notice.isPopup).toList(growable: false)
          : allNotices;
      if (notices.isEmpty) {
        if (!automatic) {
          context.showNotifier(context.appLocalizations.noAnnouncements);
        }
        return;
      }
      if (automatic) _automaticallyShownDays.add(automaticShowKey);
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierColor: context.colorScheme.scrim.withValues(alpha: 0.48),
        builder: (dialogContext) => XboardAnnouncementDialog(
          notices: notices,
          baseEndpoint: session.endpoint,
          initiallySuppressedToday: suppressed,
          onSuppressedTodayChanged: (value) =>
              _preferenceStore.setSuppressedToday(accountId, value, now: _now),
        ),
      );
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard announcements failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (!automatic && mounted) {
        final message = error is XboardAuthException
            ? error.message
            : context.appLocalizations.requestFailed;
        context.showNotifier(message);
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class XboardAnnouncementDialog extends StatefulWidget {
  const XboardAnnouncementDialog({
    super.key,
    required this.notices,
    required this.baseEndpoint,
    required this.initiallySuppressedToday,
    required this.onSuppressedTodayChanged,
  });

  final List<XboardNoticeData> notices;
  final Uri baseEndpoint;
  final bool initiallySuppressedToday;
  final Future<void> Function(bool value) onSuppressedTodayChanged;

  @override
  State<XboardAnnouncementDialog> createState() =>
      _XboardAnnouncementDialogState();
}

class _XboardAnnouncementDialogState extends State<XboardAnnouncementDialog> {
  var _index = 0;
  var _suppressedToday = false;

  XboardNoticeData get _notice => widget.notices[_index];

  @override
  void initState() {
    super.initState();
    _suppressedToday = widget.initiallySuppressedToday;
  }

  Future<void> _setSuppressedToday(bool value) async {
    setState(() => _suppressedToday = value);
    try {
      await widget.onSuppressedTodayChanged(value);
    } catch (error, stackTrace) {
      commonPrint.log(
        'save announcement reminder preference failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) setState(() => _suppressedToday = !value);
    }
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, widget.notices.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  Uri? _resolveUri(String? value) {
    final parsed = Uri.tryParse(value?.trim() ?? '');
    if (parsed == null) return null;
    final resolved = parsed.hasScheme
        ? parsed
        : widget.baseEndpoint.resolveUri(parsed);
    return {'http', 'https'}.contains(resolved.scheme) ? resolved : null;
  }

  Future<void> _openLink(String? value) async {
    final target = _resolveUri(value);
    if (target == null) return;
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  Widget _buildHtmlImage(ExtensionContext extensionContext) {
    final target = _resolveUri(extensionContext.attributes['src']);
    if (target == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Image.network(
        target.toString(),
        width: constraints.maxWidth,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.appLocalizations;
    final mediaSize = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dialogWidth = math.min(900.0, mediaSize.width - 24);
    final dialogHeight = math.min(720.0, mediaSize.height - 24);
    final compact = dialogWidth < 600 || dialogHeight < 560 || textScale > 1.2;
    final createdAt = _notice.createdAt;
    final dateText = createdAt == null
        ? '--'
        : DateFormat(
            'yyyy-MM-dd HH:mm',
            Localizations.localeOf(context).toLanguageTag(),
          ).format(createdAt);
    final bodyColor = scheme.onSurfaceVariant;
    return Dialog(
      key: const ValueKey('xboard-announcement-dialog'),
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: scheme.surface.withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 26 : 36),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 38,
            compact ? 16 : 28,
            compact ? 18 : 38,
            compact ? 14 : 26,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 58 : 78,
                    height: compact ? 58 : 78,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(compact ? 19 : 26),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: scheme.primary,
                      size: compact ? 31 : 42,
                    ),
                  ),
                  SizedBox(width: compact ? 14 : 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.announcementCenter,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: compact ? 13 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            _notice.title,
                            key: ValueKey('announcement-title-${_notice.id}'),
                            maxLines: compact ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: compact ? 24 : 31,
                              height: 1.12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('announcement-close-button'),
                    tooltip: l10n.closeAction,
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      fixedSize: Size.square(compact ? 44 : 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(compact ? 15 : 18),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              SizedBox(height: compact ? 14 : 22),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateText,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    l10n.announcementPosition(
                      _index + 1,
                      widget.notices.length,
                    ),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 18),
              Divider(color: scheme.outlineVariant),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: SingleChildScrollView(
                    key: ValueKey('announcement-content-${_notice.id}'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_notice.imageUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: Image.network(
                                _notice.imageUrl.toString(),
                                width: double.infinity,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Html(
                          data: _notice.content,
                          extensions: [
                            ImageExtension(
                              networkSchemas: const {'', 'http', 'https'},
                              builder: _buildHtmlImage,
                            ),
                          ],
                          style: {
                            'body': Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                              color: bodyColor,
                              fontSize: FontSize(compact ? 15 : 17),
                              lineHeight: const LineHeight(1.55),
                            ),
                            'p': Style(margin: Margins.only(bottom: 12)),
                            'li': Style(margin: Margins.only(bottom: 7)),
                            'a': Style(
                              color: scheme.primary,
                              textDecoration: TextDecoration.underline,
                            ),
                            'blockquote': Style(
                              backgroundColor: scheme.surfaceContainerLow,
                              border: Border(
                                left: BorderSide(
                                  color: scheme.primary,
                                  width: 4,
                                ),
                              ),
                              padding: HtmlPaddings.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          },
                          onLinkTap: (url, _, _) => _openLink(url),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('announcement-suppress-today'),
                contentPadding: EdgeInsets.zero,
                dense: compact,
                controlAffinity: ListTileControlAffinity.leading,
                value: _suppressedToday,
                onChanged: (value) {
                  if (value != null) unawaited(_setSuppressedToday(value));
                },
                title: Text(
                  l10n.doNotRemindToday,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              _AnnouncementNavigation(
                index: _index,
                count: widget.notices.length,
                compact: compact,
                onPrevious: () => _move(-1),
                onNext: () => _move(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementNavigation extends StatelessWidget {
  const _AnnouncementNavigation({
    required this.index,
    required this.count,
    required this.compact,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final bool compact;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final dots = SizedBox(
      width: compact ? 48 : 72,
      height: 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, dotIndex) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: dotIndex == index ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotIndex == index
                ? context.colorScheme.primary
                : context.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('announcement-previous-button'),
            onPressed: index > 0 ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: Text(l10n.previousAnnouncement),
            style: OutlinedButton.styleFrom(
              minimumSize: Size.fromHeight(compact ? 46 : 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 18),
        dots,
        SizedBox(width: compact ? 8 : 18),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('announcement-next-button'),
            onPressed: index < count - 1 ? onNext : null,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded),
            label: Text(l10n.nextAnnouncement),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(compact ? 46 : 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
