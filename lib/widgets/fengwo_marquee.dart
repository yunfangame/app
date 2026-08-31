import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FengWoMarqueeBar extends StatefulWidget {
  const FengWoMarqueeBar({
    super.key,
    required this.controller,
    required this.onMessageTap,
    this.margin = EdgeInsets.zero,
    this.compact = false,
  });

  final XboardMarqueeController controller;
  final ValueChanged<XboardMarqueeMessage> onMessageTap;
  final EdgeInsetsGeometry margin;
  final bool compact;

  @override
  State<FengWoMarqueeBar> createState() => _FengWoMarqueeBarState();
}

class _FengWoMarqueeBarState extends State<FengWoMarqueeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  var _index = 0;

  List<XboardMarqueeMessage> get _messages => widget.controller.messages;

  XboardMarqueeMessage? get _message => _messages.isEmpty
      ? null
      : _messages[_index.clamp(0, _messages.length - 1)];

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          final length = _messages.length;
          if (length > 0) setState(() => _index = (_index + 1) % length);
          _restartAnimation();
        }
      });
    widget.controller.addListener(_queueChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartAnimation());
  }

  @override
  void didUpdateWidget(FengWoMarqueeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_queueChanged);
      widget.controller.addListener(_queueChanged);
      _queueChanged();
    }
  }

  void _queueChanged() {
    if (!mounted) return;
    final previousId = _message?.id;
    final messages = _messages;
    var nextIndex = previousId == null
        ? 0
        : messages.indexWhere((message) => message.id == previousId);
    if (nextIndex < 0) nextIndex = 0;
    setState(() => _index = nextIndex);
    _restartAnimation();
  }

  void _restartAnimation() {
    if (!mounted) return;
    final message = _message;
    if (message == null) {
      _animation.stop();
      return;
    }
    final seconds = (message.marqueeText.characters.length / 7).clamp(7, 16);
    _animation.duration = Duration(milliseconds: (seconds * 1000).round());
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_queueChanged);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final height = widget.compact ? 42.0 : 46.0;
    return Padding(
      padding: widget.margin,
      child: Material(
        key: const ValueKey('fengwo-marquee-bar'),
        color: scheme.primaryContainer.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(height / 2),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: () => widget.onMessageTap(message),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  SizedBox(
                    width: height,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.campaign_rounded,
                          color: scheme.onPrimaryContainer,
                          size: widget.compact ? 22 : 25,
                        ),
                        Positioned(
                          right: widget.compact ? 5 : 6,
                          top: widget.compact ? 7 : 8,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: scheme.error,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.primaryContainer,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final style = Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              );
                          final painter = TextPainter(
                            text: TextSpan(
                              text: message.marqueeText,
                              style: style,
                            ),
                            textDirection: Directionality.of(context),
                            maxLines: 1,
                          )..layout();
                          final travel = constraints.maxWidth + painter.width;
                          return AnimatedBuilder(
                            animation: _animation,
                            builder: (_, child) => Transform.translate(
                              offset: Offset(
                                constraints.maxWidth -
                                    travel * _animation.value,
                                0,
                              ),
                              child: child,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                message.marqueeText,
                                key: ValueKey('marquee-message-${message.id}'),
                                maxLines: 1,
                                softWrap: false,
                                style: style,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!widget.compact)
                          Text(
                            '${_index + 1}/${_messages.length}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                        const SizedBox(width: 4),
                        TweenAnimationBuilder<double>(
                          key: ValueKey('marquee-view-${message.id}'),
                          tween: Tween(begin: 0.9, end: 1),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutBack,
                          builder: (_, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.compact ? 10 : 13,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.compact ? '查看' : '查看详情',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: scheme.onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: scheme.onPrimary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openFengWoMarqueeMessage({
  required BuildContext context,
  required WidgetRef ref,
  required XboardMarqueeController controller,
  required XboardMarqueeMessage message,
}) async {
  unawaited(controller.markRead(message));
  final actionUrl = message.actionUrl.trim();
  final opensLocalDetail =
      actionUrl.isEmpty || isLocalMarqueeDetailAction(actionUrl, message);
  if (!opensLocalDetail) {
    final route = pageLabelForMarqueeAction(actionUrl);
    if (route != null) {
      ref.read(currentPageLabelProvider.notifier).toPage(route);
      return;
    }
  }
  await showFengWoMarqueeDetail(
    context: context,
    controller: controller,
    message: message,
  );
}

PageLabel? pageLabelForMarqueeAction(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || value.trim().isEmpty) return null;
  String? target;
  if (uri.scheme == 'fengwo' && uri.host == 'page') {
    target = uri.pathSegments.firstOrNull;
  } else if (uri.scheme.isEmpty &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'app') {
    target = uri.pathSegments.last;
  }
  return switch (target) {
    'home' || 'dashboard' => PageLabel.dashboard,
    'purchase' || 'plans' => PageLabel.profiles,
    'nodes' => PageLabel.proxies,
    'connections' => PageLabel.connections,
    'traffic' => PageLabel.traffic,
    'orders' => PageLabel.orders,
    'invite' => PageLabel.invite,
    'profile' || 'account' => PageLabel.tools,
    'settings' => PageLabel.resources,
    'utilities' => PageLabel.practicalTools,
    _ => null,
  };
}

bool isLocalMarqueeDetailAction(String value, XboardMarqueeMessage message) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme.isEmpty &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == 'message' &&
      int.tryParse(uri.pathSegments.last) == message.id;
}

Future<void> showFengWoMarqueeDetail({
  required BuildContext context,
  required XboardMarqueeController controller,
  required XboardMarqueeMessage message,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => AlertDialog(
      key: ValueKey('marquee-detail-${message.id}'),
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(message.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: math.min(
            420,
            MediaQuery.sizeOf(dialogContext).height * 0.6,
          ),
        ),
        child: SingleChildScrollView(child: SelectableText(message.detailText)),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('marquee-acknowledge'),
          onPressed: () {
            unawaited(controller.markRead(message));
            Navigator.pop(dialogContext);
          },
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
