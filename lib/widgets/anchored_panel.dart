import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

Future<T?> showAdaptiveAnchoredPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double panelWidth = 448,
  double maxHeight = 500,
}) async {
  final mediaQuery = MediaQuery.of(context);
  if (!system.isDesktop || mediaQuery.size.width < 600) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colorScheme.surfaceContainerHigh,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.85),
        child: SingleChildScrollView(child: builder(context)),
      ),
    );
  }

  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: panelWidth,
            maxHeight: maxHeight,
          ),
          child: SingleChildScrollView(child: builder(context)),
        ),
      ),
    );
  }

  final anchor = renderObject.localToGlobal(Offset.zero) & renderObject.size;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          alignment: Alignment.topLeft,
          child: child,
        ),
      );
    },
    pageBuilder: (_, _, _) => _AnchoredPanelOverlay(
      anchor: anchor,
      panelWidth: panelWidth,
      maxHeight: maxHeight,
      builder: builder,
    ),
  );
}

class _AnchoredPanelOverlay extends StatelessWidget {
  const _AnchoredPanelOverlay({
    required this.anchor,
    required this.panelWidth,
    required this.maxHeight,
    required this.builder,
  });

  final Rect anchor;
  final double panelWidth;
  final double maxHeight;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const margin = 12.0;
          final width = min(panelWidth, constraints.maxWidth - margin * 2);
          final minLeft = padding.left + margin;
          final maxLeft = constraints.maxWidth - padding.right - width;
          final left = anchor.left
              .clamp(minLeft, max(maxLeft, minLeft))
              .toDouble();
          final top = anchor.bottom + 6;
          final availableHeight =
              constraints.maxHeight - padding.bottom - top - margin;
          final height = min(maxHeight, max(0, availableHeight)).toDouble();
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Material(
                  elevation: 14,
                  clipBehavior: Clip.antiAlias,
                  color: context.colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: SingleChildScrollView(child: builder(context)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
