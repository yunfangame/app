import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

class DashboardNodeEntry extends StatelessWidget {
  const DashboardNodeEntry({
    super.key,
    required this.nodeName,
    this.delay,
    this.backendStatus = XboardNodeDisplayStatus.unknown,
    this.onTap,
  });

  final String nodeName;
  final int? delay;
  final XboardNodeDisplayStatus backendStatus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.appLocalizations;
    final dark = theme.brightness == Brightness.dark;
    final delayText = backendStatus == XboardNodeDisplayStatus.offline
        ? l10n.nodeBackendOffline
        : switch (delay) {
            null || 0 => l10n.notTested,
            final value => formatReferenceDelay(value),
          };
    final delayColor = switch (backendStatus) {
      XboardNodeDisplayStatus.online =>
        dark ? const Color(0xFF56D99C) : const Color(0xFF008854),
      XboardNodeDisplayStatus.offline => scheme.error,
      XboardNodeDisplayStatus.unknown => scheme.onSurfaceVariant,
    };
    final flag = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(nodeName)?.group(0);
    final radius = BorderRadius.circular(22);
    return Tooltip(
      message: '${l10n.switchNode}: $nodeName',
      child: Material(
        color: dark ? scheme.surfaceContainerHigh : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.09),
                      shape: BoxShape.circle,
                    ),
                    child: flag == null
                        ? Icon(Icons.public_rounded, color: scheme.primary)
                        : Text(flag, style: const TextStyle(fontSize: 23)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.currentNode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          nodeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.30,
                    ),
                    child: Text(
                      delayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: delayColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
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
