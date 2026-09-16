import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/crisp_support.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import 'customer_service_session.dart';

export 'package:fl_clash/common/crisp_support.dart';

export 'customer_service_session.dart';

const _compactCustomerServiceBreakpoint = 700.0;

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

class CustomerServiceSheet {
  static final _sessions = CustomerServiceSessionCache();
  static Future<void>? _visibleSheet;
  static Future<void> show(
    BuildContext context, {
    String serviceUrl = crispServiceUrl,
    WidgetBuilder? contentBuilder,
  }) {
    final visible = _visibleSheet;
    if (visible != null) return visible;
    final user = _currentSupportUser();
    final uri = Uri.tryParse(serviceUrl.trim());
    final session =
        contentBuilder == null &&
            uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty
        ? _sessions.acquire(uri, user: user)
        : null;
    final viewport = MediaQuery.sizeOf(context);
    final panelSize = customerServicePanelSize(viewport);
    final isCompact = viewport.width < _compactCustomerServiceBreakpoint;
    final result = showModalSideSheet<void>(
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
              session: session,
              syncCurrentAccount: true,
              onReleased: (released) {
                if (_currentSupportUser().accountKey != user.accountKey) {
                  _sessions.clear();
                } else {
                  _sessions.release(released);
                }
                _visibleSheet = null;
              },
            ),
          ),
        ),
      ),
    );
    if (session != null && !globalState.isOfflineMode) {
      unawaited(_refreshSubscription());
    }
    return _visibleSheet = result.whenComplete(() {
      if (session == null) _visibleSheet = null;
    });
  }
}

CrispSupportUser _currentSupportUser() => CrispSupportUser.fromSession(
  globalState.xboardSession,
  offline: globalState.isOfflineMode,
);

Future<void> _refreshSubscription() async {
  try {
    await globalState.refreshXboardSubscription?.call();
  } catch (_) {}
}

class CustomerServiceView extends StatefulWidget {
  const CustomerServiceView({
    super.key,
    required this.serviceUrl,
    this.contentBuilder,
    this.session,
    this.onReleased,
    this.syncCurrentAccount = false,
  });

  final String serviceUrl;
  final bool syncCurrentAccount;
  final WidgetBuilder? contentBuilder;
  final CustomerServiceSession? session;
  final void Function(CustomerServiceSession)? onReleased;

  @override
  State<CustomerServiceView> createState() => _CustomerServiceViewState();
}

class _CustomerServiceViewState extends State<CustomerServiceView> {
  CustomerServiceSession? _session;
  String? _accountKey;
  bool _accountChanged = false;

  Uri? get _serviceUri {
    final uri = Uri.tryParse(widget.serviceUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  void initState() {
    super.initState();
    if (widget.contentBuilder == null && _serviceUri != null) {
      final user = _currentSupportUser();
      _accountKey = user.accountKey;
      _session =
          widget.session ??
          CustomerServiceSession(
            _serviceUri!,
            sessionToken: createCrispSessionToken(),
            user: user,
          );
      _session!.addListener(_update);
      if (widget.syncCurrentAccount) {
        globalState.xboardSessionRevisionNotifier.addListener(_syncAccount);
      }
    }
  }

  void _syncAccount() {
    final user = _currentSupportUser();
    if (user.accountKey != _accountKey) {
      setState(() => _accountChanged = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      unawaited(_session?.updateUser(user));
    }
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    globalState.xboardSessionRevisionNotifier.removeListener(_syncAccount);
    final session = _session;
    if (session != null) {
      session.removeListener(_update);
      if (widget.session == null) {
        unawaited(session.close());
      } else {
        widget.onReleased?.call(session);
      }
    }
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    final uri = _serviceUri;
    if (uri == null) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.appLocalizations.supportOpenBrowserFailed),
      ),
    );
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
    if (_accountChanged) return const SizedBox.shrink();
    if (_serviceUri == null) {
      return _CustomerServiceMessage(
        icon: Icons.support_agent_rounded,
        message: context.appLocalizations.featureComingSoon,
      );
    }
    final session = _session!;
    if (session.failed) {
      return _CustomerServiceMessage(
        icon: Icons.cloud_off_rounded,
        message: context.appLocalizations.supportLoadFailed,
        onRetry: session.reload,
        onOpenBrowser: _openInBrowser,
      );
    }
    return Column(
      children: [
        if (session.slow)
          MaterialBanner(
            content: Text(context.appLocalizations.supportLoadingSlow),
            actions: [
              TextButton(
                key: const Key('customer-service-retry'),
                onPressed: session.reload,
                child: Text(context.appLocalizations.retry),
              ),
              TextButton(
                key: const Key('customer-service-open-browser'),
                onPressed: _openInBrowser,
                child: Text(context.appLocalizations.supportOpenBrowser),
              ),
            ],
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !session.ready,
                  child: WebViewWidget(controller: session.controller),
                ),
              ),
              if (!session.ready)
                Positioned.fill(
                  child: ColoredBox(color: context.colorScheme.surface),
                ),
              if (!session.ready)
                Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    value: session.progress <= 0 || session.progress >= 100
                        ? null
                        : session.progress / 100,
                  ),
                ),
            ],
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
    this.onOpenBrowser,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenBrowser;

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
            if (onOpenBrowser != null)
              TextButton(
                onPressed: onOpenBrowser,
                child: Text(context.appLocalizations.supportOpenBrowser),
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
