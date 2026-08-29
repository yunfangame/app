import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FengWoNodeSelector {
  static Future<void> show(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;
    final inset = compact ? 12.0 : 24.0;
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.all(inset),
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        child: SizedBox(
          width: compact
              ? size.width - inset * 2
              : size.width.clamp(680, 1180).toDouble(),
          height: compact
              ? size.height - inset * 2
              : size.height.clamp(560, 780).toDouble(),
          child: const FengWoNodeSelectorView(),
        ),
      ),
    );
  }
}

enum _NodeSort { original, delayAscending, delayDescending, name }

class FengWoNodeSelectorView extends ConsumerStatefulWidget {
  const FengWoNodeSelectorView({super.key});

  @override
  ConsumerState<FengWoNodeSelectorView> createState() =>
      _FengWoNodeSelectorViewState();
}

class _FengWoNodeSelectorViewState
    extends ConsumerState<FengWoNodeSelectorView> {
  String? _selectedGroupName;
  String _query = '';
  _NodeSort _sort = _NodeSort.original;
  bool _testingAll = false;

  Group _selectedGroup(List<Group> groups) {
    final requested = _selectedGroupName.takeFirstValid([
      ref.read(currentProfileProvider)?.currentGroupName,
    ]);
    return groups.getGroup(requested) ?? groups.first;
  }

  Future<void> _testAll(Group group) async {
    if (_testingAll || group.all.isEmpty) return;
    setState(() => _testingAll = true);
    try {
      await delayTest(group.all, group.testUrl);
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }

  void _selectProxy(Group group, Proxy proxy) {
    if (!group.type.isComputedSelected && group.type != GroupType.Selector) {
      globalState.showNotifier(context.appLocalizations.notSelectedTip);
      return;
    }
    final currentName = ref.read(proxyNameProvider(group.name));
    final nextName = group.type.isComputedSelected
        ? currentName == proxy.name
              ? ''
              : proxy.name
        : proxy.name;
    ref.read(proxiesActionProvider.notifier).updateCurrentGroupName(group.name);
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(group.name, nextName);
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(group.name, nextName);
  }

  @override
  Widget build(BuildContext context) {
    final rawGroups = ref.watch(groupsProvider);
    final visibleGroups = ref.watch(currentGroupsStateProvider).value;
    final groups = visibleGroups
        .map((group) => rawGroups.getGroup(group.name) ?? group)
        .toList();
    final colors = _SelectorColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Material(
        color: colors.background,
        child: groups.isEmpty
            ? _EmptyNodes(colors: colors)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final group = _selectedGroup(groups);
                  final compact = constraints.maxWidth < 760;
                  return Column(
                    children: [
                      _SelectorHeader(colors: colors),
                      if (compact)
                        _CompactGroupSelector(
                          colors: colors,
                          groups: groups,
                          selected: group,
                          onChanged: (value) {
                            setState(() {
                              _selectedGroupName = value.name;
                              _query = '';
                            });
                          },
                        ),
                      Expanded(
                        child: Row(
                          children: [
                            if (!compact)
                              SizedBox(
                                width: constraints.maxWidth * 0.32,
                                child: _GroupPane(
                                  colors: colors,
                                  groups: groups,
                                  selected: group,
                                  onSelected: (value) {
                                    setState(() {
                                      _selectedGroupName = value.name;
                                      _query = '';
                                    });
                                  },
                                ),
                              ),
                            if (!compact)
                              VerticalDivider(width: 1, color: colors.outline),
                            Expanded(
                              child: _NodePane(
                                colors: colors,
                                group: group,
                                query: _query,
                                sort: _sort,
                                testingAll: _testingAll,
                                onQueryChanged: (value) =>
                                    setState(() => _query = value),
                                onSortChanged: (value) =>
                                    setState(() => _sort = value),
                                onTestAll: () => _testAll(group),
                                onSelect: (proxy) => _selectProxy(group, proxy),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _SelectorColors {
  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;

  const _SelectorColors({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
  });

  factory _SelectorColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _SelectorColors(
      background: scheme.surfaceContainerLowest,
      surface: dark ? scheme.surfaceContainer : scheme.surface,
      surfaceStrong: dark
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.05),
              scheme.surface,
            ),
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.11),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant,
      success: dark ? const Color(0xFF46E39C) : const Color(0xFF17BC70),
    );
  }
}

class _SelectorHeader extends StatelessWidget {
  final _SelectorColors colors;

  const _SelectorHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Icon(Icons.route_rounded, color: colors.primary, size: 28),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              context.appLocalizations.proxyGroup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _CompactGroupSelector extends StatelessWidget {
  final _SelectorColors colors;
  final List<Group> groups;
  final Group selected;
  final ValueChanged<Group> onChanged;

  const _CompactGroupSelector({
    required this.colors,
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Group>(
          value: selected,
          isExpanded: true,
          items: groups
              .map(
                (group) => DropdownMenuItem(
                  value: group,
                  child: Text(group.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _GroupPane extends ConsumerWidget {
  final _SelectorColors colors;
  final List<Group> groups;
  final Group selected;
  final ValueChanged<Group> onSelected;

  const _GroupPane({
    required this.colors,
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  IconData _icon(GroupType type) {
    return switch (type) {
      GroupType.Selector => Icons.tune_rounded,
      GroupType.URLTest => Icons.speed_rounded,
      GroupType.Fallback => Icons.alt_route_rounded,
      GroupType.LoadBalance => Icons.balance_rounded,
      GroupType.Relay => Icons.link_rounded,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: colors.surface,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          final group = groups[index];
          final active = group.name == selected.name;
          final selectedName = ref.watch(selectedProxyNameProvider(group.name));
          final current = (selectedName ?? '').takeFirstValid([
            group.realNow,
            context.appLocalizations.proxiesEmpty,
          ]);
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelected(group),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: active ? colors.primarySoft : colors.surfaceStrong,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active ? colors.primary : colors.outline,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: active
                          ? colors.primary.withValues(alpha: 0.15)
                          : colors.background,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      _icon(group.type),
                      color: active ? colors.primary : colors.muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          current,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: active ? colors.primary : colors.muted,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NodePane extends ConsumerWidget {
  final _SelectorColors colors;
  final Group group;
  final String query;
  final _NodeSort sort;
  final bool testingAll;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_NodeSort> onSortChanged;
  final VoidCallback onTestAll;
  final ValueChanged<Proxy> onSelect;

  const _NodePane({
    required this.colors,
    required this.group,
    required this.query,
    required this.sort,
    required this.testingAll,
    required this.onQueryChanged,
    required this.onSortChanged,
    required this.onTestAll,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final delayMap = <String, int?>{
      for (final proxy in group.all)
        proxy.name: ref.watch(
          delayProvider(proxyName: proxy.name, testUrl: group.testUrl),
        ),
    };
    final lowQuery = query.trim().toLowerCase();
    final proxies = group.all
        .where((proxy) => proxy.name.toLowerCase().contains(lowQuery))
        .toList();
    int delayRank(int? value) {
      if (value == null || value == 0 || value < 0) return 1 << 30;
      return value;
    }

    proxies.sort((left, right) {
      return switch (sort) {
        _NodeSort.original =>
          group.all.indexOf(left) - group.all.indexOf(right),
        _NodeSort.delayAscending => delayRank(
          delayMap[left.name],
        ).compareTo(delayRank(delayMap[right.name])),
        _NodeSort.delayDescending => delayRank(
          delayMap[right.name],
        ).compareTo(delayRank(delayMap[left.name])),
        _NodeSort.name => left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        ),
      };
    });
    final selectedName = ref.watch(selectedProxyNameProvider(group.name));
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outline)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: testingAll ? null : onTestAll,
                    icon: testingAll
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_rounded),
                    label: Text(l10n.delayTest),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: onQueryChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.search,
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: colors.surfaceStrong,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PopupMenuButton<_NodeSort>(
                    tooltip: l10n.sort,
                    initialValue: sort,
                    onSelected: onSortChanged,
                    icon: const Icon(Icons.sort_rounded),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _NodeSort.original,
                        child: Text(l10n.defaultText),
                      ),
                      PopupMenuItem(
                        value: _NodeSort.delayAscending,
                        child: Text('${l10n.delay} ↑'),
                      ),
                      PopupMenuItem(
                        value: _NodeSort.delayDescending,
                        child: Text('${l10n.delay} ↓'),
                      ),
                      PopupMenuItem(
                        value: _NodeSort.name,
                        child: Text(l10n.name),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: proxies.isEmpty
              ? Center(
                  child: Text(
                    l10n.noData,
                    style: TextStyle(color: colors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: proxies.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final proxy = proxies[index];
                    final delay = delayMap[proxy.name];
                    return _NodeRow(
                      colors: colors,
                      proxy: proxy,
                      delay: delay,
                      selected: selectedName == proxy.name,
                      onSelect: () => onSelect(proxy),
                      onTest: () => proxyDelayTest(proxy, group.testUrl),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  final _SelectorColors colors;
  final Proxy proxy;
  final int? delay;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTest;

  const _NodeRow({
    required this.colors,
    required this.proxy,
    required this.delay,
    required this.selected,
    required this.onSelect,
    required this.onTest,
  });

  Color _delayColor() {
    if (delay == null || delay == 0) return colors.muted;
    if (delay! < 0) return const Color(0xFFE84C4C);
    if (delay! <= 250) return colors.success;
    if (delay! <= 400) return colors.primary;
    return const Color(0xFFF29C38);
  }

  @override
  Widget build(BuildContext context) {
    final color = _delayColor();
    final text = switch (delay) {
      null => context.appLocalizations.delayTest,
      0 => '',
      < 0 => context.appLocalizations.timeout,
      final value => '$value ms',
    };
    return Material(
      color: selected ? colors.primarySoft : colors.surfaceStrong,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  _nodeFlag(proxy.name),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  proxy.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: delay == 0 ? null : onTest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.45)),
                ),
                icon: delay == 0
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_rounded, size: 17),
                label: Text(text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNodes extends StatelessWidget {
  final _SelectorColors colors;

  const _EmptyNodes({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 52, color: colors.muted),
          const SizedBox(height: 12),
          Text(
            context.appLocalizations.proxyGroupEmpty,
            style: TextStyle(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

String _nodeFlag(String name) {
  const entries = <String, String>{
    '香港': '🇭🇰',
    'hong kong': '🇭🇰',
    '台湾': '🇹🇼',
    'taiwan': '🇹🇼',
    '日本': '🇯🇵',
    'japan': '🇯🇵',
    '韩国': '🇰🇷',
    'korea': '🇰🇷',
    '新加坡': '🇸🇬',
    'singapore': '🇸🇬',
    '美国': '🇺🇸',
    'united states': '🇺🇸',
    '英国': '🇬🇧',
    'united kingdom': '🇬🇧',
    '德国': '🇩🇪',
    'germany': '🇩🇪',
    '法国': '🇫🇷',
    'france': '🇫🇷',
    '俄罗斯': '🇷🇺',
    'russia': '🇷🇺',
    '澳大利亚': '🇦🇺',
    'australia': '🇦🇺',
  };
  final lower = name.toLowerCase();
  for (final entry in entries.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  final emoji = RegExp(
    r'[\u{1F1E6}-\u{1F1FF}]{2}',
    unicode: true,
  ).firstMatch(name);
  return emoji?.group(0) ?? '🌐';
}
