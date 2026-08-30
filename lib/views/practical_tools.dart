import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/practical_tools/cloudflare_optimizer_dialog.dart';
import 'package:fl_clash/views/practical_tools/network_tool_dialogs.dart';
import 'package:flutter/material.dart';

class PracticalToolsView extends StatelessWidget {
  const PracticalToolsView({super.key});

  Future<void> _openTool(BuildContext context, _PracticalTool tool) async {
    final dialog = switch (tool.type) {
      _PracticalToolType.speedTest => const SpeedTestDialog(),
      _PracticalToolType.cloudflare => const CloudflareOptimizerDialog(),
      _PracticalToolType.ipLookup => const IpLookupDialog(),
      _PracticalToolType.streaming => const StreamingTestDialog(),
      _PracticalToolType.chainProxy => const ChainProxyDialog(),
      _PracticalToolType.popularApps => const PopularAppsDialog(),
    };
    await showDialog<void>(
      context: context,
      barrierDismissible: tool.type != _PracticalToolType.cloudflare,
      builder: (_) => dialog,
    );
  }

  List<_PracticalTool> _tools(BuildContext context) {
    final l10n = context.appLocalizations;
    return [
      _PracticalTool(
        type: _PracticalToolType.speedTest,
        icon: Icons.speed_rounded,
        color: const Color(0xFF2F80ED),
        title: l10n.speedTest,
        description: l10n.speedTestDescription,
        action: l10n.chooseSpeedTest,
      ),
      _PracticalTool(
        type: _PracticalToolType.cloudflare,
        icon: Icons.cloud_rounded,
        color: const Color(0xFFFF8A1F),
        title: l10n.cloudflarePreferredIp,
        description: l10n.cloudflarePreferredIpDescription,
        action: l10n.startOptimization,
      ),
      _PracticalTool(
        type: _PracticalToolType.ipLookup,
        icon: Icons.location_on_outlined,
        color: const Color(0xFF16B86A),
        title: l10n.ipLookup,
        description: l10n.ipLookupDescription,
        action: l10n.queryNow,
      ),
      _PracticalTool(
        type: _PracticalToolType.streaming,
        icon: Icons.movie_filter_outlined,
        color: const Color(0xFF8057F5),
        title: l10n.streamingUnlockTest,
        description: l10n.streamingUnlockTestDescription,
        action: l10n.startTest,
      ),
      _PracticalTool(
        type: _PracticalToolType.chainProxy,
        icon: Icons.link_rounded,
        color: const Color(0xFF1E88F7),
        title: l10n.chainProxy,
        description: l10n.chainProxyDescription,
        action: l10n.manageChainProxy,
      ),
      _PracticalTool(
        type: _PracticalToolType.popularApps,
        icon: Icons.grid_view_rounded,
        color: const Color(0xFF13A9E8),
        title: l10n.popularApps,
        description: l10n.popularAppsDescription,
        action: l10n.viewApps,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final tools = _tools(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPadding = width < 700 ? 16.0 : 32.0;
        final columns = width >= 1180
            ? 3
            : width >= 720
            ? 2
            : 1;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface,
                colors.primaryContainer.withValues(alpha: .23),
              ],
            ),
          ),
          child: SingleChildScrollView(
            key: const ValueKey('practical-tools-scroll'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              28,
              horizontalPadding,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ToolsHero(compact: width < 700),
                    const SizedBox(height: 20),
                    Container(
                      padding: EdgeInsets.all(width < 700 ? 16 : 30),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: .55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: .08),
                            blurRadius: 34,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.appLocalizations.toolbox,
                            style: context.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 24),
                          GridView.builder(
                            key: const ValueKey('practical-tools-grid'),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 20,
                                  crossAxisSpacing: 20,
                                  mainAxisExtent: width < 700 ? 210 : 220,
                                ),
                            itemCount: tools.length,
                            itemBuilder: (context, index) {
                              final tool = tools[index];
                              return _PracticalToolCard(
                                tool: tool,
                                onTap: () => _openTool(context, tool),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToolsHero extends StatelessWidget {
  const _ToolsHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      height: compact ? 195 : 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.primaryContainer.withValues(alpha: .82),
            const Color(0xFFDCE9FF).withValues(alpha: .72),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .13)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: compact ? -32 : 36,
            top: compact ? 16 : 10,
            child: Icon(
              Icons.business_center_outlined,
              size: compact ? 150 : 180,
              color: colors.primary.withValues(alpha: .13),
            ),
          ),
          Positioned(
            right: compact ? 92 : 260,
            top: 26,
            child: _HeroOrb(icon: Icons.search_rounded, color: colors.primary),
          ),
          Positioned(
            right: compact ? 24 : 100,
            bottom: -28,
            child: Container(
              width: 180,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.primary.withValues(alpha: .14),
                ),
                borderRadius: BorderRadius.circular(90),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 38,
              vertical: compact ? 28 : 34,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 290 : 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.appLocalizations.practicalTools,
                    style:
                        (compact
                                ? context.textTheme.headlineMedium
                                : context.textTheme.displaySmall)
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF071A3C),
                              letterSpacing: -.6,
                            ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.appLocalizations.practicalToolsSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF526B98),
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: context.colorScheme.surface.withValues(alpha: .62),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .12), blurRadius: 20),
        ],
      ),
      child: Icon(icon, size: 38, color: color.withValues(alpha: .65)),
    );
  }
}

class _PracticalToolCard extends StatelessWidget {
  const _PracticalToolCard({required this.tool, required this.onTap});

  final _PracticalTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      color: colors.surfaceContainerLowest.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('practical-tool-${tool.type.name}'),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.primary.withValues(alpha: .12)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surfaceContainerLowest,
                tool.color.withValues(alpha: .035),
              ],
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: tool.color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(tool.icon, color: tool.color, size: 32),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF10244A),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          tool.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5D719A),
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onTap,
                  icon: const Icon(Icons.bolt_rounded, size: 19),
                  label: Text(tool.action),
                  style: FilledButton.styleFrom(
                    foregroundColor: tool.color,
                    backgroundColor: tool.color.withValues(alpha: .075),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticalTool {
  const _PracticalTool({
    required this.type,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.action,
  });

  final _PracticalToolType type;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String action;
}

enum _PracticalToolType {
  speedTest,
  cloudflare,
  ipLookup,
  streaming,
  chainProxy,
  popularApps,
}
