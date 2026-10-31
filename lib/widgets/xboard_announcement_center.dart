import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_announcement_query.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

class XboardAnnouncementCenterHost extends ConsumerStatefulWidget {
  const XboardAnnouncementCenterHost({
    super.key,
    required this.child,
    this.authService,
    this.preferenceStore,
    this.now,
    this.queryCache,
    this.observeDesktopWindow,
  });

  final Widget child;
  final XboardAuthService? authService;
  final XboardNoticePreferenceStore? preferenceStore;
  final DateTime Function()? now;
  final XboardAnnouncementQueryCache? queryCache;
  final bool? observeDesktopWindow;

  @override
  ConsumerState<XboardAnnouncementCenterHost> createState() =>
      _XboardAnnouncementCenterHostState();
}

class _XboardAnnouncementCenterHostState
    extends ConsumerState<XboardAnnouncementCenterHost>
    with WidgetsBindingObserver, WindowListener {
  late final XboardAuthService _authService;
  late final XboardNoticePreferenceStore _preferenceStore;
  late final XboardAnnouncementQueryCache _queries;
  late final XboardAnnouncementRequest _requestHandler;
  late final bool _observeDesktopWindow;
  final _shown = <String>{};
  final _presentation = ValueNotifier<_AnnouncementPresentation?>(null);
  DialogRoute<void>? _dialog;
  Future<void>? _dialogClosed;
  Timer? _windowRetry;
  _AnnouncementWindowRead? _windowRead;
  String? _identity;
  String? _shownDate;
  int _requestRevision = 0;
  int _activityRevision = 0;
  bool _wasAutomaticAvailable = false;
  int _windowRevision = 0;
  int _windowRetries = 0;
  bool _foreground = true;
  bool _windowForeground = true;
  bool _windowKnownBackground = false;
  bool _pageActive = true;
  bool _automaticPending = false;
  bool _automaticScheduled = false;
  bool _automaticLoading = false;
  bool _manualLoading = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();
  String? get _currentIdentity {
    final session = globalState.xboardSession;
    return session == null
        ? null
        : XboardAnnouncementQueryCache.accountKey(session);
  }

  bool get _available =>
      mounted &&
      _foreground &&
      _windowForeground &&
      _pageActive &&
      !globalState.isOfflineMode;

  bool get _automaticAvailable =>
      _available &&
      _dialog == null &&
      !_manualLoading &&
      (ModalRoute.isCurrentOf(context) ?? true);

  bool get _manualAvailable =>
      mounted &&
      _foreground &&
      _pageActive &&
      !_windowKnownBackground &&
      !globalState.isOfflineMode;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    _preferenceStore = widget.preferenceStore ?? XboardNoticePreferenceStore();
    _queries =
        widget.queryCache ?? XboardAnnouncementQueryCache(now: widget.now);
    _identity = _currentIdentity;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _observeDesktopWindow = widget.observeDesktopWindow ?? system.isDesktop;
    WidgetsBinding.instance.addObserver(this);
    globalState.xboardSessionRevisionNotifier.addListener(_sessionChanged);
    globalState.offlineModeNotifier.addListener(_offlineChanged);
    if (_observeDesktopWindow) {
      _windowForeground = false;
      windowManager.addListener(this);
      unawaited(_readWindow());
    }
    _requestHandler = ({required automatic}) {
      if (automatic) {
        globalState.consumeXboardAnnouncementAutoPrompt();
        _automaticPending = true;
        _scheduleAutomatic();
      } else if (mounted) {
        _automaticPending = false;
        unawaited(_showAnnouncements(automatic: false));
      }
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
      _automaticPending = true;
      _scheduleAutomatic();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final previous = _pageActive;
    final active = PageActivityScope.isActiveOf(context);
    _pageActive = active;
    if (active != previous && _observeDesktopWindow) {
      if (active) {
        unawaited(_readWindow());
      } else {
        _cancelWindowRead();
        _windowRetry?.cancel();
      }
    }
    _scheduleAutomatic();
  }

  void _scheduleAutomatic() {
    final available = _automaticAvailable;
    if (_wasAutomaticAvailable && !available) _activityRevision++;
    _wasAutomaticAvailable = available;
    if (!_automaticPending ||
        _automaticScheduled ||
        _automaticLoading ||
        !_automaticAvailable) {
      return;
    }
    _automaticScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticScheduled = false;
      if (_automaticPending && _automaticAvailable && !_automaticLoading) {
        unawaited(_showAnnouncements(automatic: true));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sessionChanged() {
    final identity = _currentIdentity;
    if (identity == _identity) return;
    _identity = identity;
    _requestRevision++;
    _automaticLoading = false;
    _manualLoading = false;
    _queries.clear();
    _closeDialog();
    _automaticPending = identity != null;
    _scheduleAutomatic();
  }

  void _offlineChanged() {
    _requestRevision++;
    _automaticLoading = false;
    _manualLoading = false;
    _closeDialog();
    _automaticPending = _identity != null;
    _scheduleAutomatic();
  }

  bool _current(XboardLoginResult session, int revision) =>
      mounted &&
      revision == _requestRevision &&
      _currentIdentity == XboardAnnouncementQueryCache.accountKey(session);

  String _accountId(XboardLoginResult session) {
    final account = session.subscription.email?.trim().toLowerCase();
    final uuid = session.subscription.uuid?.trim();
    return '${session.endpoint.origin}|${account ?? uuid ?? session.authData}';
  }

  String _showKey(XboardLoginResult session, XboardNoticeData notice) {
    final date = _now.toLocal();
    final day = '${date.year}-${date.month}-${date.day}';
    if (day != _shownDate) {
      _shownDate = day;
      _shown.clear();
    }
    final version = sha256.convert(
      utf8.encode(
        jsonEncode([
          notice.id,
          notice.updatedAtEpochSeconds,
          notice.rawData['version'],
          notice.rawData['revision'],
          notice.title,
          notice.content,
          notice.tags,
          notice.imageUrl?.toString(),
        ]),
      ),
    );
    return '${XboardAnnouncementQueryCache.accountKey(session)}|$day|$version';
  }

  Future<void> _showAnnouncements({required bool automatic}) async {
    if (!mounted) return;
    final session = globalState.xboardSession;
    if (session == null ||
        session.authData.isEmpty ||
        globalState.isOfflineMode) {
      if (!automatic) {
        context.showNotifier(
          context.appLocalizations.announcementUnavailableOffline,
        );
      }
      if (automatic) _automaticPending = false;
      return;
    }
    if (!(automatic ? _automaticAvailable : _manualAvailable)) return;
    final revision = ++_requestRevision;
    final activityRevision = _activityRevision;
    bool canRequest() =>
        _current(session, revision) &&
        activityRevision == _activityRevision &&
        (automatic ? _automaticAvailable : _manualAvailable);
    if (automatic) {
      _automaticLoading = true;
    } else {
      _automaticLoading = false;
      _manualLoading = true;
    }
    try {
      final accountId = _accountId(session);
      final suppressed = await _preferenceStore.isSuppressedToday(
        accountId,
        now: _now,
      );
      if (!mounted ||
          !_current(session, revision) ||
          !(automatic ? _available : _manualAvailable)) {
        return;
      }
      if (automatic && suppressed) {
        _automaticPending = false;
        return;
      }
      final allNotices = await _queries.load(
        session: session,
        forceRefresh: !automatic,
        canRequest: canRequest,
        loader: () async {
          ensureXboardApiRequestAllowed(canRequest);
          try {
            final notices = await _authService.fetchNotices(
              endpoint: session.endpoint,
              authData: session.authData,
              canRequest: canRequest,
            );
            ensureXboardApiRequestAllowed(canRequest);
            return notices;
          } catch (_) {
            ensureXboardApiRequestAllowed(canRequest);
            rethrow;
          }
        },
      );
      if (!mounted ||
          !_current(session, revision) ||
          !(automatic ? _available : _manualAvailable)) {
        return;
      }
      if (automatic && !_automaticAvailable) return;
      final notices = allNotices
          .where(
            (notice) =>
                !automatic ||
                (notice.isPopup && !_shown.contains(_showKey(session, notice))),
          )
          .toList(growable: false);
      if (notices.isEmpty) {
        if (automatic) _automaticPending = false;
        if (!automatic) {
          context.showNotifier(context.appLocalizations.noAnnouncements);
        }
        return;
      }
      final presented = await _present(
        _AnnouncementPresentation(
          notices,
          session.endpoint,
          suppressed,
          accountId,
          revision,
        ),
        session,
        revision,
        automatic,
      );
      if (!mounted || !_current(session, revision)) return;
      if (!presented) return;
      if (automatic) _automaticPending = false;
      for (final notice in notices.where((notice) => notice.isPopup)) {
        _shown.add(_showKey(session, notice));
      }
    } catch (error, stackTrace) {
      if (!mounted || !_current(session, revision)) return;
      if (error is XboardApiRequestDeferred || !canRequest()) {
        if (automatic) _automaticPending = true;
        return;
      }
      if (automatic) _automaticPending = false;
      commonPrint.log(
        'load XBoard announcements failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (!automatic && _manualAvailable) {
        context.showNotifier(
          error is XboardAuthException
              ? error.message
              : context.appLocalizations.requestFailed,
        );
      }
    } finally {
      if (_current(session, revision)) {
        if (automatic) {
          _automaticLoading = false;
        } else {
          _manualLoading = false;
        }
        _scheduleAutomatic();
      }
    }
  }

  Future<bool> _present(
    _AnnouncementPresentation value,
    XboardLoginResult session,
    int revision,
    bool automatic,
  ) async {
    final previous = _dialog;
    if (previous != null && previous.isActive) {
      _presentation.value = value;
      return true;
    }
    await _dialogClosed;
    if (!mounted ||
        !_current(session, revision) ||
        !(automatic ? _automaticAvailable : _manualAvailable)) {
      return false;
    }
    _presentation.value = value;
    final route = DialogRoute<void>(
      context: context,
      barrierColor: context.colorScheme.scrim.withValues(alpha: 0.48),
      builder: (_) => ValueListenableBuilder<_AnnouncementPresentation?>(
        valueListenable: _presentation,
        builder: (_, presentation, _) => XboardAnnouncementDialog(
          key: ValueKey(presentation!.revision),
          notices: presentation.notices,
          baseEndpoint: presentation.endpoint,
          initiallySuppressedToday: presentation.suppressed,
          onSuppressedTodayChanged: (suppressed) =>
              _currentIdentity ==
                  XboardAnnouncementQueryCache.accountKey(session)
              ? _preferenceStore.setSuppressedToday(
                  presentation.accountId,
                  suppressed,
                  now: _now,
                )
              : Future.value(),
        ),
      ),
    );
    _dialog = route;
    unawaited(Navigator.of(context, rootNavigator: true).push(route));
    _dialogClosed = route.completed.then<void>((_) {
      if (identical(_dialog, route)) _dialog = null;
      if (mounted) _scheduleAutomatic();
    });
    return true;
  }

  void _closeDialog() {
    final route = _dialog;
    _dialog = null;
    if (route == null) return;
    scheduleMicrotask(() {
      final navigator = route.navigator;
      if (route.isActive && navigator?.mounted == true) {
        navigator!.removeRoute(route);
      }
    });
  }

  void _pauseWindow() {
    _windowRevision++;
    _windowForeground = false;
    _windowKnownBackground = true;
    _windowRetry?.cancel();
    _cancelWindowRead();
    _scheduleAutomatic();
  }

  void _focusWindow() {
    _windowRevision++;
    _windowForeground = true;
    _windowKnownBackground = false;
    _windowRetries = 0;
    _windowRetry?.cancel();
    _cancelWindowRead();
    _scheduleAutomatic();
  }

  void _cancelWindowRead() {
    _windowRead?.cancel();
    _windowRead = null;
  }

  Future<void> _readWindow({bool reset = true}) async {
    if (!mounted || !_foreground || !_pageActive) return;
    if (reset) {
      _windowRetries = 0;
      _windowRetry?.cancel();
    }
    final revision = ++_windowRevision;
    _cancelWindowRead();
    _windowForeground = false;
    _scheduleAutomatic();
    final read = _AnnouncementWindowRead(
      Future.wait([
        windowManager.isVisible(),
        windowManager.isMinimized(),
        windowManager.isFocused(),
      ]),
    );
    _windowRead = read;
    try {
      final state = await read.future;
      if (state == null || !mounted || revision != _windowRevision) return;
      _windowForeground = state[0] && !state[1] && state[2];
      _windowKnownBackground = !_windowForeground;
      _windowRetries = 0;
      _scheduleAutomatic();
    } catch (_) {
      if (!mounted ||
          revision != _windowRevision ||
          _windowKnownBackground ||
          !_foreground ||
          !_pageActive ||
          _windowRetries >= 4) {
        return;
      }
      final seconds = const [1, 3, 6, 12][_windowRetries++];
      _windowRetry = Timer(Duration(seconds: seconds), () {
        if (mounted &&
            revision == _windowRevision &&
            !_windowKnownBackground &&
            _foreground &&
            _pageActive) {
          unawaited(_readWindow(reset: false));
        }
      });
    } finally {
      if (identical(_windowRead, read)) _windowRead = null;
      read.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _windowRetry?.cancel();
      _cancelWindowRead();
    }
    if (_foreground && _observeDesktopWindow) unawaited(_readWindow());
    _scheduleAutomatic();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') _pauseWindow();
    if (eventName == 'show') {
      _windowKnownBackground = false;
      unawaited(_readWindow());
    }
  }

  @override
  void onWindowFocus() => _focusWindow();
  @override
  void onWindowBlur() => _pauseWindow();
  @override
  void onWindowMinimize() => _pauseWindow();
  @override
  void onWindowRestore() {
    _windowKnownBackground = false;
    unawaited(_readWindow());
  }

  @override
  void dispose() {
    _requestRevision++;
    _windowRevision++;
    _windowRetry?.cancel();
    _cancelWindowRead();
    _queries.clear();
    WidgetsBinding.instance.removeObserver(this);
    globalState.xboardSessionRevisionNotifier.removeListener(_sessionChanged);
    globalState.offlineModeNotifier.removeListener(_offlineChanged);
    if (_observeDesktopWindow) windowManager.removeListener(this);
    if (identical(globalState.showXboardAnnouncements, _requestHandler)) {
      globalState.showXboardAnnouncements = null;
    }
    final closed = _dialogClosed;
    _closeDialog();
    if (closed == null) {
      _presentation.dispose();
    } else {
      unawaited(closed.whenComplete(_presentation.dispose));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AnnouncementWindowRead {
  _AnnouncementWindowRead(Future<List<bool>> read) {
    _timeout = Timer(const Duration(seconds: 2), () {
      _fail(
        TimeoutException('Window state read timed out'),
        StackTrace.current,
      );
    });
    unawaited(read.then<void>(_complete, onError: _fail));
  }

  final _completion = Completer<List<bool>?>();
  late final Timer _timeout;

  Future<List<bool>?> get future => _completion.future;

  void _complete(List<bool> state) {
    _timeout.cancel();
    if (!_completion.isCompleted) _completion.complete(state);
  }

  void _fail(Object error, StackTrace stackTrace) {
    _timeout.cancel();
    if (!_completion.isCompleted) {
      _completion.completeError(error, stackTrace);
    }
  }

  void cancel() {
    _timeout.cancel();
    if (!_completion.isCompleted) _completion.complete(null);
  }
}

class _AnnouncementPresentation {
  const _AnnouncementPresentation(
    this.notices,
    this.endpoint,
    this.suppressed,
    this.accountId,
    this.revision,
  );
  final List<XboardNoticeData> notices;
  final Uri endpoint;
  final bool suppressed;
  final String accountId;
  final int revision;
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
