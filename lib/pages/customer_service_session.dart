import 'dart:async';

import 'package:fl_clash/common/crisp_support.dart';
import 'package:fl_clash/common/print.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

class CustomerServiceSession extends ChangeNotifier {
  CustomerServiceSession(
    this.uri, {
    WebViewController? controller,
    required this.sessionToken,
    required CrispSupportUser user,
    this.slowLoadDelay = const Duration(seconds: 12),
  }) : controller = controller ?? WebViewController(),
       _user = user {
    _initializing = _initialize();
  }

  final Uri uri;
  final String sessionToken;
  CrispSupportUser _user;
  Future<void>? _reloading;
  final WebViewController controller;
  final Duration slowLoadDelay;
  late final Future<void> _initializing;
  Timer? _slowTimer;
  final Stopwatch _loadingTime = Stopwatch();
  bool _closed = false;
  bool _configured = false;
  Future<void>? _closing;
  int progress = 0;
  bool ready = false;
  bool slow = false;
  bool failed = false;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _startLoading() {
    if (_closed) return;
    _slowTimer?.cancel();
    progress = 0;
    ready = false;
    slow = false;
    failed = false;
    _loadingTime
      ..reset()
      ..start();
    commonPrint.event('support.load.started');
    _slowTimer = Timer(slowLoadDelay, () {
      if (_closed || ready || failed) return;
      slow = true;
      commonPrint.event(
        'support.load.slow',
        fields: {'elapsed_ms': _loadingTime.elapsedMilliseconds},
      );
      _notify();
    });
    _notify();
  }

  Future<void> _markReady() async {
    if (_closed || failed || ready) return;
    try {
      CrispSupportUser profile;
      do {
        profile = _user;
        await controller.runJavaScript(profile.updateScript);
      } while (!_closed && !identical(profile, _user));
    } catch (_) {
      _markFailed();
      return;
    }
    if (_closed || failed || ready) return;
    _slowTimer?.cancel();
    ready = true;
    slow = false;
    progress = 100;
    _loadingTime.stop();
    commonPrint.event(
      'support.load.ready',
      fields: {
        'elapsed_ms': _loadingTime.elapsedMilliseconds,
        'provider': 'crisp',
      },
    );
    _notify();
  }

  void _markFailed() {
    if (_closed) return;
    _slowTimer?.cancel();
    failed = true;
    _loadingTime.stop();
    commonPrint.event(
      'support.load.failed',
      fields: {'elapsed_ms': _loadingTime.elapsedMilliseconds},
    );
    _notify();
  }

  Future<void> _initialize() async {
    _startLoading();
    try {
      if (!kIsWeb) {
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        if (_closed) return;
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onProgress: (value) {
              progress = value;
              _notify();
            },
            onPageStarted: (_) => _startLoading(),
            onPageFinished: (_) {
              if (_closed || failed) return;
              progress = 100;
              unawaited(_bootstrap());
              _notify();
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame != false) _markFailed();
            },
            onNavigationRequest: (request) async {
              final target = Uri.tryParse(request.url);
              if (target == null || _closed) return NavigationDecision.prevent;
              if (!request.isMainFrame ||
                  {'about', 'data', 'blob'}.contains(target.scheme) ||
                  (target.scheme == 'https' &&
                      target.host == uri.host &&
                      target.path == uri.path)) {
                return NavigationDecision.navigate;
              }
              if ({'https', 'mailto', 'tel', 'sms'}.contains(target.scheme)) {
                try {
                  await launchUrl(target, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
              return NavigationDecision.prevent;
            },
          ),
        );
        if (_closed) return;
        await controller.addJavaScriptChannel(
          'FengwoSupportReady',
          onMessageReceived: (message) {
            if (message.message == 'ready') unawaited(_markReady());
            if (!_closed && message.message == 'summary_sent') {
              commonPrint.event('support.summary.sent');
            }
            if (!_closed && message.message == 'summary_failed') {
              commonPrint.event('support.summary.failed');
            }
          },
        );
      }
      _configured = true;
      if (_closed) return;
      await controller.loadRequest(uri);
      if (kIsWeb) {
        ready = true;
        _slowTimer?.cancel();
        _notify();
      }
    } catch (_) {
      _markFailed();
    }
  }

  Future<void> _bootstrap() async {
    if (_closed) return;
    try {
      await controller.runJavaScript(
        crispBootstrapScript(sessionToken: sessionToken),
      );
    } catch (_) {
      _markFailed();
    }
  }

  Future<void> updateUser(CrispSupportUser user) async {
    _user = user;
    if (!ready || _closed) return;
    try {
      await controller.runJavaScript(user.updateScript);
    } catch (_) {
      commonPrint.event('support.profile.sync_failed');
    }
  }

  Future<void> reload() => _reloading ??= _reload().whenComplete(() {
    _reloading = null;
  });

  Future<void> _reload() async {
    if (_closed) return;
    await _initializing;
    if (_closed) return;
    if (!_configured) {
      await _initialize();
      return;
    }
    _startLoading();
    try {
      await controller.loadRequest(uri);
    } catch (_) {
      _markFailed();
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _slowTimer?.cancel();
    super.dispose();
    await _initializing;
    if (kIsWeb) return;
    try {
      if (await controller.isOffscreenWebViewSupported()) {
        await controller.platform.closeOffscreenWebView();
      } else {
        await controller.loadRequest(Uri.parse('about:blank'));
      }
    } catch (_) {}
  }
}

class CustomerServiceSessionCache {
  CustomerServiceSessionCache({this.keepAlive = const Duration(minutes: 5)});

  final Duration keepAlive;
  CustomerServiceSession? _session;
  String? _accountKey;
  String? _sessionToken;
  Timer? _expiration;

  CustomerServiceSession acquire(Uri uri, {required CrispSupportUser user}) {
    _expiration?.cancel();
    final accountChanged = _accountKey != user.accountKey;
    if (_session?.uri != uri || accountChanged) {
      final previous = _session;
      if (previous != null) unawaited(previous.close());
      if (accountChanged || _sessionToken == null) {
        _sessionToken = createCrispSessionToken();
      }
      _session = CustomerServiceSession(
        uri,
        sessionToken: _sessionToken!,
        user: user,
      );
      _accountKey = user.accountKey;
    } else {
      unawaited(_session!.updateUser(user));
      commonPrint.event('support.page.reused');
    }
    return _session!;
  }

  void release(CustomerServiceSession session) {
    if (!identical(session, _session)) return;
    _expiration?.cancel();
    _expiration = Timer(keepAlive, _expire);
  }

  void _expire() {
    _expiration?.cancel();
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.close());
  }

  void clear() {
    _expire();
    _accountKey = null;
    _sessionToken = null;
  }
}
