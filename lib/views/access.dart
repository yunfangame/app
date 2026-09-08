import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccessView extends ConsumerStatefulWidget {
  const AccessView({super.key});

  @override
  ConsumerState<AccessView> createState() => _AccessViewState();
}

class _AccessViewState extends ConsumerState<AccessView> {
  final GlobalKey<CommonScaffoldState> _scaffoldKey = GlobalKey();
  late ScrollController _controller;
  List<String>? _pinedList;
  bool _isInit = false;
  bool _saving = false;
  bool _saveFailed = false;
  String? _saveMessage;
  AccessControlMode? _lastMode;
  late Future<List<Package>> _packagesFuture;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _packagesFuture = ref.read(systemActionProvider.notifier).getPackages();
    final accessControl = ref
        .read(vpnSettingProvider.select((state) => state.accessControlProps))
        .copyWith();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(accessControlStateProvider.notifier).value = accessControl;
      setState(() => _isInit = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildSelectedAllButton({
    required bool isSelectedAll,
    required List<String> allValueList,
  }) {
    void onPressed() {
      ref.read(accessControlStateProvider.notifier).update((state) {
        final newSet = Set<String>.from(state.currentList);
        final isSelectedAll = newSet.containsAll(allValueList);
        if (isSelectedAll) {
          newSet.removeAll(allValueList);
        } else {
          newSet.addAll(allValueList);
        }
        return state.copyWithNewList(newSet.toList());
      });
    }

    final appLocalizations = context.appLocalizations;
    return TextButton.icon(
      onPressed: allValueList.isEmpty ? null : onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      icon: Icon(isSelectedAll ? Icons.deselect : Icons.select_all, size: 17),
      label: Text(
        isSelectedAll
            ? appLocalizations.cancelSelectAll
            : appLocalizations.selectAll,
      ),
    );
  }

  Future<void> _intelligentSelected() async {
    final packageNames = ref.read(
      packagesProvider.select((state) => state.map((item) => item.packageName)),
    );
    if (packageNames.isEmpty) {
      return;
    }
    final selectedPackageNames =
        (await globalState.loadingRun<List<String>>(() async {
          return await app?.getChinaPackageNames() ?? [];
        }, tag: LoadingTag.access))?.toSet() ??
        {};
    if (!mounted) return;
    final acceptList = packageNames
        .where((item) => !selectedPackageNames.contains(item))
        .toList();
    final rejectList = packageNames
        .where((item) => selectedPackageNames.contains(item))
        .toList();
    ref
        .read(accessControlStateProvider.notifier)
        .update(
          (state) =>
              state.copyWith(acceptList: acceptList, rejectList: rejectList),
        );
  }

  Future<void> _handleToSetting() async {
    await showSheet<int>(
      context: context,
      props: const SheetProps(isScrollControlled: true),
      builder: (context) {
        final appLocalizations = context.appLocalizations;
        return AdaptiveSheetScaffold(
          body: const AccessControlPanel(),
          title: appLocalizations.accessControlSettings,
        );
      },
    );
  }

  void _handleSelected(String packageName) {
    ref.read(accessControlStateProvider.notifier).update((state) {
      final newSet = Set<String>.from(state.currentList)
        ..addOrRemove(packageName);
      return state.copyWithNewList(newSet.toList());
    });
  }

  void _handleToggle() {
    ref.read(accessControlStateProvider.notifier).update((state) {
      return state.copyWith(enable: !state.enable);
    });
  }

  void _handleSearch() {
    _scaffoldKey.currentState?.handleToSearch();
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    final appLocalizations = context.appLocalizations;
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.saveChanges),
    );
    if (res == null || !mounted) return;
    if (res && !await _handleSave()) return;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  AccessControlProps _getRealAccessControlProps(
    AccessControlProps accessControl,
  ) {
    List<String> normalize(List<String> values) =>
        values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return accessControl.copyWith(
      acceptList: normalize(accessControl.acceptList),
      rejectList: normalize(accessControl.rejectList),
    );
  }

  Future<bool> _handleSave() async {
    if (_saving) return false;
    final accessControl = _getRealAccessControlProps(
      ref.read(accessControlStateProvider),
    );
    final l10n = context.appLocalizations;
    setState(() {
      _saving = true;
      _saveFailed = false;
      _saveMessage = null;
    });
    try {
      final result = await ref
          .read(setupActionProvider.notifier)
          .applyAccessControl(accessControl);
      if (!mounted) return true;
      ref.read(accessControlStateProvider.notifier).value = accessControl;
      setState(() {
        _saveMessage = result == AccessControlApplyResult.reconnectRequested
            ? l10n.appRoutingReconnecting
            : l10n.appRoutingSaved;
      });
      return true;
    } catch (error) {
      commonPrint.log(
        'Application routing save failed: $error',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        setState(() {
          _saveFailed = true;
          _saveMessage = l10n.appRoutingSaveFailed;
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildConfirm() {
    final running = ref.watch(isStartProvider);
    final needsReconnect =
        running &&
        ref.read(setupActionProvider.notifier).hasPendingAccessControlReconnect;
    final l10n = context.appLocalizations;
    final colors = _RoutingColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saveMessage != null && (!_hasChanges || _saveFailed)) ...[
                Text(
                  _saveMessage!,
                  key: const ValueKey('app-routing-save-status'),
                  style: TextStyle(
                    color: _saveFailed ? context.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (running) ...[
                Text(
                  l10n.appRoutingConnectionHint,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                key: const ValueKey('app-routing-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed:
                    !_isInit ||
                        _saving ||
                        (!_hasChanges && !_saveFailed && !needsReconnect)
                    ? null
                    : _handleSave,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(running ? Icons.refresh : Icons.save_outlined),
                label: Text(running ? l10n.appRoutingReconnect : l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasChanges =>
      _getRealAccessControlProps(ref.read(accessControlStateProvider)) !=
      _getRealAccessControlProps(
        ref.read(vpnSettingProvider).accessControlProps,
      );

  Widget _buildRoutingControls(AccessControlProps accessControl) {
    final l10n = context.appLocalizations;
    final colors = _RoutingColors.of(context);
    return Container(
      key: const ValueKey('app-routing-policy-card'),
      padding: const EdgeInsets.all(18),
      decoration: colors.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.alt_route_rounded,
                  color: colors.primary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appRoutingPolicy,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accessControl.enable ? l10n.enabled : l10n.disabled,
                      style: TextStyle(
                        color: accessControl.enable
                            ? colors.primary
                            : colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('app-routing-enable'),
                value: accessControl.enable,
                onChanged: (_) => _handleToggle(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  MediaQuery.textScalerOf(context).scale(14) > 18 ||
                  constraints.maxWidth < 285;
              final width = stacked
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in [
                    AccessControlMode.rejectSelected,
                    AccessControlMode.acceptSelected,
                  ])
                    SizedBox(
                      width: width,
                      child: ChoiceChip(
                        key: ValueKey('app-routing-mode-${mode.name}'),
                        showCheckmark: false,
                        selectedColor: colors.primary,
                        backgroundColor: colors.soft,
                        side: BorderSide(
                          color: accessControl.mode == mode
                              ? colors.primary
                              : colors.outline,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(
                            mode == AccessControlMode.rejectSelected
                                ? l10n.appRoutingDirectMode
                                : l10n.appRoutingProxyMode,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: accessControl.mode == mode
                                  ? colors.onPrimary
                                  : colors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        selected: accessControl.mode == mode,
                        onSelected: (_) => ref
                            .read(accessControlStateProvider.notifier)
                            .update((state) => state.copyWith(mode: mode)),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: colors.muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  accessControl.mode == AccessControlMode.rejectSelected
                      ? l10n.accessControlNotAllowDesc
                      : l10n.accessControlAllowDesc,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportToClipboard() async {
    await globalState.safeRun(() {
      final currentList = ref.read(
        accessControlStateProvider.select((state) => state.currentList),
      );
      Clipboard.setData(ClipboardData(text: currentList.join('\n')));
    });
  }

  Future<void> _importFormClipboard() async {
    await globalState.safeRun(() async {
      final data = await Clipboard.getData('text/plain');
      if (!mounted) return;
      final text = data?.text;
      if (text == null) return;
      final list = text.split('\n');
      ref
          .read(accessControlStateProvider.notifier)
          .update((state) => state.copyWithNewList(list.toSet().toList()));
    });
  }

  List<Widget> _buildActions(BuildContext context, {required bool enable}) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupBox(
        targetBuilder: (open) {
          return IconButton(
            onPressed: () {
              open(offset: const Offset(0, 0));
            },
            tooltip: appLocalizations.settings,
            icon: const Icon(Icons.tune_rounded, size: 22),
          );
        },
        popup: CommonPopupMenu(
          items: [
            PopupMenuItemData(
              icon: Icons.swap_horiz,
              label: enable
                  ? appLocalizations.turnOff
                  : appLocalizations.turnOn,
              onPressed: _handleToggle,
            ),
            PopupMenuItemData(
              icon: Icons.tune,
              label: appLocalizations.settings,
              onPressed: _handleToSetting,
            ),
            PopupMenuItemData(
              icon: Icons.emergency_outlined,
              label: appLocalizations.action,
              subItems: [
                PopupMenuItemData(
                  icon: Icons.auto_awesome,
                  label: appLocalizations.intelligentSelected,
                  onPressed: _intelligentSelected,
                ),
                PopupMenuItemData(
                  icon: Icons.content_copy,
                  label: appLocalizations.clipboardExport,
                  onPressed: _exportToClipboard,
                ),
                PopupMenuItemData(
                  icon: Icons.paste,
                  label: appLocalizations.clipboardImport,
                  onPressed: _importFormClipboard,
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildContent({
    required List<Package> packages,
    required List<String> valueList,
    required AccessControlProps accessControl,
    required bool inlineSave,
  }) {
    final colors = _RoutingColors.of(context);
    return FutureBuilder(
      future: _packagesFuture,
      builder: (context, snapshot) {
        final appLocalizations = context.appLocalizations;
        Widget? status;
        if (snapshot.connectionState != ConnectionState.done) {
          status = const Center(child: CommonCircleLoading());
        } else if (snapshot.hasError) {
          status = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(appLocalizations.appRoutingLoadFailed),
                TextButton(
                  onPressed: () => setState(() {
                    _packagesFuture = ref
                        .read(systemActionProvider.notifier)
                        .getPackages();
                  }),
                  child: Text(appLocalizations.retry),
                ),
              ],
            ),
          );
        } else if (packages.isEmpty) {
          status = Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apps_outlined, size: 32, color: colors.muted),
                const SizedBox(height: 10),
                Text(
                  appLocalizations.appRoutingEmptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ],
            ),
          );
        }
        return CommonScrollBar(
          controller: _controller,
          child: CustomScrollView(
            key: const ValueKey('app-routing-scroll'),
            controller: _controller,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                sliver: SliverToBoxAdapter(
                  child: _buildRoutingControls(accessControl),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                sliver: DecoratedSliver(
                  decoration: colors.cardDecoration,
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildListHeader(
                          accessControl,
                          packages,
                          valueList,
                        ),
                      ),
                      if (status != null)
                        SliverToBoxAdapter(
                          child: SizedBox(height: 180, child: status),
                        )
                      else
                        SliverFixedExtentList(
                          itemExtent:
                              68 +
                              (MediaQuery.textScalerOf(context).scale(14) - 14)
                                      .clamp(0, 24) *
                                  2,
                          delegate: SliverChildBuilderDelegate((_, index) {
                            final package = packages[index];
                            return PackageListItem(
                              key: Key(package.packageName),
                              package: package,
                              value: valueList.contains(package.packageName),
                              onChanged: (value) {
                                _handleSelected(package.packageName);
                              },
                            );
                          }, childCount: packages.length),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),
                    ],
                  ),
                ),
              ),
              if (inlineSave) SliverToBoxAdapter(child: _buildConfirm()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListHeader(
    AccessControlProps accessControl,
    List<Package> packages,
    List<String> valueList,
  ) {
    final l10n = context.appLocalizations;
    final colors = _RoutingColors.of(context);
    final packageNames = packages.map((item) => item.packageName).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.appRoutingApps,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildSelectedAllButton(
                isSelectedAll:
                    packageNames.isNotEmpty &&
                    valueList.length == packageNames.length,
                allValueList: packageNames,
              ),
            ],
          ),
          Material(
            color: colors.soft,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              key: const ValueKey('app-routing-search'),
              onTap: _handleSearch,
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: colors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.appRoutingSearchHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                key: const ValueKey('app-routing-show-all'),
                selected: !accessControl.isFilterNonLaunchableApp,
                label: Text(l10n.appRoutingAllApps),
                labelStyle: TextStyle(fontSize: 11, color: colors.muted),
                backgroundColor: colors.surface,
                selectedColor: colors.soft,
                side: BorderSide(color: colors.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                visualDensity: VisualDensity.compact,
                onSelected: (value) => ref
                    .read(accessControlStateProvider.notifier)
                    .update(
                      (state) =>
                          state.copyWith(isFilterNonLaunchableApp: !value),
                    ),
              ),
              Text(
                l10n.selectedCountTitle(accessControl.currentList.length),
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (accessControl.isFilterNonLaunchableApp) ...[
            const SizedBox(height: 4),
            Text(
              l10n.appRoutingAppsHint,
              style: TextStyle(color: colors.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.access).notifier).value = value
        .trim()
        .toLowerCase();
    _pinedList = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _RoutingColors.of(context);
    final theme = Theme.of(context);
    final isLoading = ref.watch(loadingProvider(LoadingTag.access));
    final query = ref.watch(queryProvider(QueryTag.access));
    final packages = ref.watch(packagesProvider);
    final accessControl = ref.watch(accessControlStateProvider);
    if (_isInit) {
      if (_lastMode != accessControl.mode) {
        _lastMode = accessControl.mode;
        _pinedList = accessControl.currentList;
      } else {
        _pinedList ??= accessControl.currentList;
      }
    }
    final viewPackages = packages
        .getViewList(
          pinedList: _pinedList ?? [],
          sortType: accessControl.sort == AccessSortType.none
              ? AccessSortType.name
              : accessControl.sort,
          isFilterNonInternetApp: accessControl.isFilterNonInternetApp,
          isFilterSystemApp: false,
          isFilterNonLaunchableApp: accessControl.isFilterNonLaunchableApp,
        )
        .where(
          (package) =>
              package.label.toLowerCase().contains(query) ||
              package.packageName.toLowerCase().contains(query),
        )
        .toList();
    final currentList = accessControl.currentList;
    final viewPackageNameList = viewPackages.map((e) => e.packageName).toList();
    final valueList = currentList.intersection(viewPackageNameList);
    return CommonPopScope(
      onPop: _saving || _hasChanges
          ? (_) async {
              await _handleBack();
              return false;
            }
          : null,
      child: AbsorbPointer(
        absorbing: _saving,
        child: Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              backgroundColor: colors.background,
              foregroundColor: colors.text,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: TextStyle(
                color: colors.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          child: CommonScaffold(
            key: _scaffoldKey,
            backgroundColor: colors.background,
            isLoading: isLoading,
            searchState: AppBarSearchState(
              onSearch: _onSearch,
              autoAddSearch: false,
            ),
            title: context.appLocalizations.appRouting,
            actions: _buildActions(context, enable: accessControl.enable),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final inlineSave = constraints.maxHeight < 360;
                    final content = _buildContent(
                      packages: viewPackages,
                      valueList: valueList,
                      accessControl: accessControl,
                      inlineSave: inlineSave,
                    );
                    if (inlineSave) return content;
                    return Column(
                      children: [
                        Expanded(child: content),
                        _buildConfirm(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PackageListItem extends StatelessWidget {
  final Package package;
  final bool value;
  final void Function(bool?) onChanged;

  const PackageListItem({
    super.key,
    required this.package,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _RoutingColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: MergeSemantics(
        child: Material(
          color: value
              ? colors.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: Row(
                children: [
                  PackageIcon(packageName: package.packageName, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          package.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Checkbox(
                    value: value,
                    onChanged: onChanged,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    side: BorderSide(
                      color: colors.muted.withValues(alpha: 0.75),
                      width: 1.5,
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

class _RoutingColors {
  final ColorScheme scheme;

  const _RoutingColors(this.scheme);

  factory _RoutingColors.of(BuildContext context) =>
      _RoutingColors(Theme.of(context).colorScheme);

  bool get dark => scheme.brightness == Brightness.dark;
  Color get primary => scheme.primary;
  Color get onPrimary => scheme.onPrimary;
  Color get text => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get surface => scheme.surfaceContainerLowest;
  Color get soft => scheme.surfaceContainerLow;
  Color get outline => scheme.outlineVariant.withValues(alpha: 0.82);
  Color get background => Color.alphaBlend(
    primary.withValues(alpha: dark ? 0.055 : 0.035),
    scheme.surface,
  );

  BoxDecoration get cardDecoration => BoxDecoration(
    color: surface.withValues(alpha: 0.97),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: outline),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.3 : 0.055),
        blurRadius: 24,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

class AccessControlPanel extends ConsumerStatefulWidget {
  const AccessControlPanel({super.key});

  @override
  ConsumerState createState() => _AccessControlPanelState();
}

class _AccessControlPanelState extends ConsumerState<AccessControlPanel> {
  IconData _getIconWithAccessControlMode(AccessControlMode mode) {
    return switch (mode) {
      AccessControlMode.acceptSelected => Icons.adjust_outlined,
      AccessControlMode.rejectSelected => Icons.block_outlined,
    };
  }

  String _getTextWithAccessControlMode(AccessControlMode mode) {
    final appLocalizations = context.appLocalizations;
    return switch (mode) {
      AccessControlMode.acceptSelected => appLocalizations.appRoutingProxyMode,
      AccessControlMode.rejectSelected => appLocalizations.appRoutingDirectMode,
    };
  }

  String _getTextWithAccessSortType(AccessSortType type) {
    final appLocalizations = context.appLocalizations;
    return switch (type) {
      AccessSortType.none => appLocalizations.defaultText,
      AccessSortType.name => appLocalizations.name,
      AccessSortType.time => appLocalizations.time,
    };
  }

  IconData _getIconWithProxiesSortType(AccessSortType type) {
    return switch (type) {
      AccessSortType.none => Icons.sort,
      AccessSortType.name => Icons.sort_by_alpha,
      AccessSortType.time => Icons.timeline,
    };
  }

  List<Widget> _buildModeSetting() {
    final appLocalizations = context.appLocalizations;
    return generateSection(
      isFirst: true,
      title: appLocalizations.mode,
      items: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          child: Consumer(
            builder: (_, ref, _) {
              final accessControlMode = ref.watch(
                accessControlStateProvider.select((state) => state.mode),
              );
              return Wrap(
                spacing: 16,
                children: [
                  for (final item in AccessControlMode.values)
                    SettingInfoCard(
                      Info(
                        label: _getTextWithAccessControlMode(item),
                        iconData: _getIconWithAccessControlMode(item),
                      ),
                      isSelected: accessControlMode == item,
                      onPressed: () {
                        ref
                            .read(accessControlStateProvider.notifier)
                            .update((state) => state.copyWith(mode: item));
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSortSetting() {
    final appLocalizations = context.appLocalizations;
    return generateSection(
      title: appLocalizations.sort,
      items: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          child: Consumer(
            builder: (_, ref, _) {
              final accessSortType = ref.watch(
                accessControlStateProvider.select((state) => state.sort),
              );
              return Wrap(
                spacing: 16,
                children: [
                  for (final item in AccessSortType.values)
                    SettingInfoCard(
                      Info(
                        label: _getTextWithAccessSortType(item),
                        iconData: _getIconWithProxiesSortType(item),
                      ),
                      isSelected: accessSortType == item,
                      onPressed: () {
                        ref
                            .read(accessControlStateProvider.notifier)
                            .update((state) => state.copyWith(sort: item));
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSourceSetting() {
    final appLocalizations = context.appLocalizations;
    return generateSection(
      title: appLocalizations.source,
      items: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          child: Consumer(
            builder: (_, ref, _) {
              final vm2 = ref.watch(
                accessControlStateProvider.select(
                  (state) => VM2(
                    state.isFilterNonLaunchableApp,
                    state.isFilterNonInternetApp,
                  ),
                ),
              );
              return Wrap(
                spacing: 16,
                children: [
                  SettingTextCard(
                    appLocalizations.appRoutingAllApps,
                    isSelected: vm2.a == false,
                    onPressed: () {
                      ref
                          .read(accessControlStateProvider.notifier)
                          .update(
                            (state) => state.copyWith(
                              isFilterNonLaunchableApp: !vm2.a,
                            ),
                          );
                    },
                  ),
                  SettingTextCard(
                    appLocalizations.noNetworkApp,
                    isSelected: vm2.b == false,
                    onPressed: () {
                      ref
                          .read(accessControlStateProvider.notifier)
                          .update(
                            (state) =>
                                state.copyWith(isFilterNonInternetApp: !vm2.b),
                          );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildModeSetting(),
            ..._buildSortSetting(),
            ..._buildSourceSetting(),
          ],
        ),
      ),
    );
  }
}
