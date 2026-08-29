import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

const saleSmartlyServiceUrl = String.fromEnvironment(
  'SALESMARTLY_SERVICE_URL',
  defaultValue: 'https://kefu.wxbaohe.com',
);

const _compactCustomerServiceBreakpoint = 700.0;

const saleSmartlyDesktopUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
    'Mobile/15E148 Safari/604.1';

@visibleForTesting
Size customerServicePanelSize(Size viewport) {
  if (viewport.width < _compactCustomerServiceBreakpoint) return viewport;

  final width = switch (viewport.width) {
    >= 1600 => min(1240.0, max(1100.0, viewport.width * 0.68)),
    >= 1200 => min(1080.0, viewport.width * 0.84),
    >= 1000 => viewport.width * 0.88,
    _ => viewport.width * 0.90,
  };
  final verticalInset = viewport.height < 700 ? 8.0 : 16.0;
  final availableHeight = max(0.0, viewport.height - verticalInset * 2);
  return Size(min(width, viewport.width), availableHeight);
}

const saleSmartlyLayoutFixScript = '''
(() => {
  const styleId = 'flclash-salesmartly-layout-fix';
  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.textContent = `
      html, body {
        width: 100% !important;
        max-width: 100% !important;
        overflow-x: hidden !important;
        overscroll-behavior-x: none !important;
      }
      .container {
        width: 100% !important;
        min-width: 0 !important;
        max-width: 100% !important;
        overflow-x: hidden !important;
      }
      salesmartly-chat-widget {
        max-width: 100vw !important;
      }
      a, p, pre {
        overflow-wrap: anywhere !important;
        word-break: break-word !important;
      }
      img, video, iframe {
        max-width: 100% !important;
      }
    `;
    document.head.appendChild(style);
  }
  document.documentElement.scrollLeft = 0;
  document.body.scrollLeft = 0;
  window.scrollTo(0, window.scrollY);
})();
''';

class CustomerServiceSheet {
  static Future<void> show(
    BuildContext context, {
    String serviceUrl = saleSmartlyServiceUrl,
    WidgetBuilder? contentBuilder,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final panelSize = customerServicePanelSize(viewport);
    final isCompact = viewport.width < _compactCustomerServiceBreakpoint;
    return showModalSideSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: false,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.none,
      constraints: BoxConstraints.tightFor(width: panelSize.width),
      builder: (_) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: panelSize.height,
          child: Material(
            color: context.colorScheme.surface,
            elevation: isCompact ? 0 : 24,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: isCompact
                  ? BorderRadius.zero
                  : const BorderRadius.horizontal(left: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomerServiceView(
              serviceUrl: serviceUrl,
              contentBuilder: contentBuilder,
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerServiceView extends StatefulWidget {
  const CustomerServiceView({
    super.key,
    required this.serviceUrl,
    this.contentBuilder,
  });

  final String serviceUrl;
  final WidgetBuilder? contentBuilder;

  @override
  State<CustomerServiceView> createState() => _CustomerServiceViewState();
}

class _CustomerServiceViewState extends State<CustomerServiceView> {
  WebViewController? _controller;
  int _progress = 0;
  String? _error;

  Uri? get _serviceUri {
    final uri = Uri.tryParse(widget.serviceUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  void initState() {
    super.initState();
    if (widget.contentBuilder == null && _serviceUri != null) {
      _initializeWebView(_serviceUri!);
    }
  }

  void _initializeWebView(Uri uri) {
    final controller = WebViewController();
    if (!kIsWeb) {
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() {
                _progress = 0;
                _error = null;
              });
            },
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _progress = 100);
              _applySaleSmartlyLayoutFix();
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == false) return;
              if (!mounted) return;
              setState(() => _error = error.description);
            },
            onNavigationRequest: (request) async {
              final target = Uri.tryParse(request.url);
              if (target == null) return NavigationDecision.prevent;
              if (!request.isMainFrame ||
                  target.scheme == 'about' ||
                  target.scheme == 'data' ||
                  target.scheme == 'blob' ||
                  (target.scheme == 'https' &&
                      (target.host == uri.host ||
                          target.host.endsWith('.salesmartly.com')))) {
                return NavigationDecision.navigate;
              }
              if (target.scheme == 'https' ||
                  target.scheme == 'mailto' ||
                  target.scheme == 'tel' ||
                  target.scheme == 'sms') {
                await launchUrl(target, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            },
          ),
        );
    }
    _controller = controller;
    unawaited(_loadWebView(controller, uri));
  }

  Future<void> _loadWebView(WebViewController controller, Uri uri) async {
    final useCompactComposer =
        !kIsWeb &&
        {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform);
    if (useCompactComposer) {
      try {
        await controller.setUserAgent(saleSmartlyDesktopUserAgent);
      } catch (_) {
        // The page still works with the platform user agent on older engines.
      }
    }
    await controller.loadRequest(uri);
  }

  void _applySaleSmartlyLayoutFix() {
    final controller = _controller;
    if (controller == null) return;
    controller.runJavaScript(saleSmartlyLayoutFixScript);
    for (final delay in const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ]) {
      Future<void>.delayed(delay, () async {
        if (!mounted || _controller != controller) return;
        await controller.runJavaScript(saleSmartlyLayoutFixScript);
      });
    }
  }

  void _reload() {
    setState(() => _error = null);
    _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const Key('customer-service-sheet'),
      child: Column(
        children: [
          _CustomerServiceHeader(onClose: () => Navigator.of(context).pop()),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.contentBuilder case final builder?) return builder(context);
    if (_serviceUri == null) {
      return _CustomerServiceMessage(
        icon: Icons.support_agent_rounded,
        message: context.appLocalizations.featureComingSoon,
      );
    }
    if (_error case final error?) {
      return _CustomerServiceMessage(
        icon: Icons.cloud_off_rounded,
        message: error,
        onRetry: _reload,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller!)),
        if (_progress < 100)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress / 100,
            ),
          ),
      ],
    );
  }
}

class _CustomerServiceHeader extends StatelessWidget {
  const _CustomerServiceHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 10),
              IconButton(
                key: const Key('customer-service-close'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                context.appLocalizations.onlineSupport,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerServiceMessage extends StatelessWidget {
  const _CustomerServiceMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: context.colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.textTheme.titleMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              IconButton.filled(
                tooltip: MaterialLocalizations.of(
                  context,
                ).refreshIndicatorSemanticLabel,
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
