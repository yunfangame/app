// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_color_utilities/hct/hct.dart';

class ThemeModeItem {
  final ThemeMode themeMode;
  final IconData iconData;
  final String label;

  const ThemeModeItem({
    required this.themeMode,
    required this.iconData,
    required this.label,
  });
}

class FontFamilyItem {
  final FontFamily fontFamily;
  final String label;

  const FontFamilyItem({required this.fontFamily, required this.label});
}

class ThemeQuickSelector {
  static Future<void> show(BuildContext context) {
    return showAdaptiveAnchoredPanel<void>(
      context,
      panelWidth: 340,
      maxHeight: 500,
      builder: (_) => const ThemeQuickPanel(),
    );
  }
}

class ThemeQuickPanel extends ConsumerWidget {
  const ThemeQuickPanel({super.key});

  Future<void> _showThemeColors(BuildContext context, WidgetRef ref) async {
    await globalState.showCommonDialog<void>(
      context: context,
      child: const _ThemeColorDialog(),
    );
  }

  Future<void> _showSchemeVariants(BuildContext context, WidgetRef ref) async {
    final value = await globalState.showCommonDialog<DynamicSchemeVariant>(
      context: context,
      child: OptionsDialog<DynamicSchemeVariant>(
        title: context.appLocalizations.colorSchemes,
        options: DynamicSchemeVariant.values,
        textBuilder: (item) => Intl.message('${item.name}Scheme'),
        value: ref.read(themeSettingProvider).schemeVariant,
      ),
    );
    if (value == null) return;
    ref
        .read(themeSettingProvider.notifier)
        .update((state) => state.copyWith(schemeVariant: value));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final themeProps = ref.watch(themeSettingProvider);
    final primaryColor = themeProps.primaryColor == null
        ? context.colorScheme.primary
        : Color(themeProps.primaryColor!);
    final modeItems = [
      ThemeModeItem(
        themeMode: ThemeMode.system,
        iconData: Icons.brightness_auto_rounded,
        label: appLocalizations.auto,
      ),
      ThemeModeItem(
        themeMode: ThemeMode.light,
        iconData: Icons.light_mode_rounded,
        label: appLocalizations.light,
      ),
      ThemeModeItem(
        themeMode: ThemeMode.dark,
        iconData: Icons.dark_mode_rounded,
        label: appLocalizations.dark,
      ),
    ];
    return Padding(
      key: const Key('theme-quick-panel'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in modeItems)
            _QuickThemeRow(
              icon: item.iconData,
              label: item.label,
              selected: item.themeMode == themeProps.themeMode,
              onTap: () {
                ref
                    .read(themeSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(themeMode: item.themeMode),
                    );
              },
            ),
          const Divider(height: 1),
          _QuickThemeRow(
            icon: Icons.contrast_rounded,
            label: appLocalizations.pureBlackMode,
            onTap: () {
              ref
                  .read(themeSettingProvider.notifier)
                  .update(
                    (state) => state.copyWith(pureBlack: !state.pureBlack),
                  );
            },
            trailing: Switch(
              value: themeProps.pureBlack,
              onChanged: (value) {
                ref
                    .read(themeSettingProvider.notifier)
                    .update((state) => state.copyWith(pureBlack: value));
              },
            ),
          ),
          const Divider(height: 1),
          _QuickThemeRow(
            icon: Icons.palette_rounded,
            label: appLocalizations.themeColor,
            onTap: () => _showThemeColors(context, ref),
            trailing: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          _QuickThemeRow(
            icon: Icons.format_color_fill_rounded,
            label: appLocalizations.colorSchemes,
            onTap: () => _showSchemeVariants(context, ref),
            trailing: Text(
              Intl.message('${themeProps.schemeVariant.name}Scheme'),
              style: context.textTheme.titleMedium?.copyWith(
                color: context.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickThemeRow extends StatelessWidget {
  const _QuickThemeRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colorScheme.primary
        : context.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                label,
                style: context.textTheme.titleLarge?.copyWith(
                  color: selected ? context.colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            trailing ??
                (selected
                    ? Icon(
                        Icons.check_rounded,
                        color: context.colorScheme.primary,
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorDialog extends ConsumerWidget {
  const _ThemeColorDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeProps = ref.watch(themeSettingProvider);
    final colors = <int?>[null, ...defaultPrimaryColors];
    final dynamicPrimary = ref.watch(
      genColorSchemeProvider(
        Theme.of(context).brightness,
        ignoreConfig: true,
      ).select((scheme) => scheme.primary),
    );
    return Dialog(
      key: const Key('theme-color-dialog'),
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      backgroundColor: context.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.palette_rounded,
                    color: context.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    context.appLocalizations.themeColor,
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                context.appLocalizations.themeDesc,
                style: context.textTheme.titleMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 24,
                runSpacing: 20,
                children: [
                  for (final color in colors)
                    _ThemeColorOption(
                      color: color == null ? dynamicPrimary : Color(color),
                      selected: color == themeProps.primaryColor,
                      onPressed: () {
                        ref
                            .read(themeSettingProvider.notifier)
                            .update(
                              (state) => state.copyWith(primaryColor: color),
                            );
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.appLocalizations.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeColorOption extends StatelessWidget {
  const _ThemeColorOption({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: selected ? 8 : 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 64,
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class ThemeView extends StatelessWidget {
  const ThemeView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return BaseScaffold(
      title: appLocalizations.theme,
      body: const CustomScrollView(
        slivers: [
          _ThemeModeItem(),
          SliverToBoxAdapter(child: SizedBox(height: 16)),
          _PrimaryColorItem(),
          SliverToBoxAdapter(child: SizedBox(height: 16)),
          _PrueBlackItem(),
          SliverToBoxAdapter(child: SizedBox(height: 16)),
          _TextScaleFactorItem(),
          SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final Widget child;
  final Info info;
  final List<Widget> actions;

  const ItemCard({
    super.key,
    required this.info,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 16,
      children: [
        InfoHeader(info: info, actions: actions),
        child,
      ],
    );
  }
}

class _ThemeModeItem extends ConsumerWidget {
  const _ThemeModeItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final themeMode = ref.watch(
      themeSettingProvider.select((state) => state.themeMode),
    );
    final List<ThemeModeItem> themeModeItems = [
      ThemeModeItem(
        iconData: Icons.auto_mode,
        label: appLocalizations.auto,
        themeMode: ThemeMode.system,
      ),
      ThemeModeItem(
        iconData: Icons.light_mode,
        label: appLocalizations.light,
        themeMode: ThemeMode.light,
      ),
      ThemeModeItem(
        iconData: Icons.dark_mode,
        label: appLocalizations.dark,
        themeMode: ThemeMode.dark,
      ),
    ];
    return SliverToBoxAdapter(
      child: ItemCard(
        info: Info(
          label: appLocalizations.themeMode,
          iconData: Icons.brightness_high,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themeModeItems.length,
            itemBuilder: (_, index) {
              final themeModeItem = themeModeItems[index];
              return CommonCard(
                isSelected: themeModeItem.themeMode == themeMode,
                onPressed: () {
                  ref
                      .read(themeSettingProvider.notifier)
                      .update(
                        (state) =>
                            state.copyWith(themeMode: themeModeItem.themeMode),
                      );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Flexible(child: Icon(themeModeItem.iconData)),
                      const SizedBox(width: 8),
                      Flexible(child: Text(themeModeItem.label)),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) {
              return const SizedBox(width: 16);
            },
          ),
        ),
      ),
    );
  }
}

class _PrimaryColorItem extends ConsumerStatefulWidget {
  const _PrimaryColorItem();

  @override
  ConsumerState<_PrimaryColorItem> createState() => _PrimaryColorItemState();
}

class _PrimaryColorItemState extends ConsumerState<_PrimaryColorItem> {
  int? _removablePrimaryColor;

  int _calcColumns(double maxWidth) {
    return max((maxWidth / 96).ceil(), 3);
  }

  Future<void> _handleReset() async {
    final res = await globalState.showMessage(
      message: TextSpan(text: context.appLocalizations.resetTip),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).update((state) {
      return state.copyWith(
        primaryColors: defaultPrimaryColors,
        primaryColor: defaultPrimaryColor,
        schemeVariant: DynamicSchemeVariant.content,
      );
    });
  }

  Future<void> _handleDel() async {
    final appLocalizations = context.appLocalizations;
    if (_removablePrimaryColor == null) {
      return;
    }
    final res = await globalState.showMessage(
      message: TextSpan(
        text: appLocalizations.deleteTip(appLocalizations.colorSchemes),
      ),
    );
    if (res != true) {
      return;
    }
    ref.read(themeSettingProvider.notifier).update((state) {
      final newPrimaryColors = List<int>.from(state.primaryColors)
        ..remove(_removablePrimaryColor);
      int? newPrimaryColor = state.primaryColor;
      if (state.primaryColor == _removablePrimaryColor) {
        if (newPrimaryColors.contains(defaultPrimaryColor)) {
          newPrimaryColor = defaultPrimaryColor;
        } else {
          newPrimaryColor = null;
        }
      }
      return state.copyWith(
        primaryColors: newPrimaryColors,
        primaryColor: newPrimaryColor,
      );
    });
    setState(() {
      _removablePrimaryColor = null;
    });
  }

  Future<void> _handleAdd() async {
    final appLocalizations = context.appLocalizations;
    final res = await globalState.showCommonDialog<int>(
      child: const _PaletteDialog(),
    );
    if (res == null) {
      return;
    }
    final isExists = ref.read(
      themeSettingProvider.select((state) => state.primaryColors.contains(res)),
    );
    if (isExists && mounted) {
      context.showNotifier(
        appLocalizations.existsTip(appLocalizations.colorSchemes),
      );
      return;
    }
    ref.read(themeSettingProvider.notifier).update((state) {
      return state.copyWith(
        primaryColors: List.from(state.primaryColors)..add(res),
      );
    });
  }

  Future<void> _handleChangeSchemeVariant() async {
    final schemeVariant = ref.read(
      themeSettingProvider.select((state) => state.schemeVariant),
    );
    final value = await globalState.showCommonDialog<DynamicSchemeVariant>(
      child: OptionsDialog<DynamicSchemeVariant>(
        title: context.appLocalizations.colorSchemes,
        options: DynamicSchemeVariant.values,
        textBuilder: (item) => Intl.message('${item.name}Scheme'),
        value: schemeVariant,
      ),
    );
    if (value == null) {
      return;
    }
    ref.read(themeSettingProvider.notifier).update((state) {
      return state.copyWith(schemeVariant: value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final vm4 = ref.watch(
      themeSettingProvider.select(
        (state) => VM4(
          state.primaryColor,
          state.primaryColors,
          state.schemeVariant,
          state.primaryColor == defaultPrimaryColor &&
              intListEquality.equals(
                state.primaryColors,
                defaultPrimaryColors,
              ) &&
              state.schemeVariant == DynamicSchemeVariant.content,
        ),
      ),
    );
    final primaryColor = vm4.a;
    final primaryColors = [null, ...vm4.b];
    final schemeVariant = vm4.c;
    final isEquals = vm4.d;

    return SliverToBoxAdapter(
      child: CommonPopScope(
        onPop: (context) {
          if (_removablePrimaryColor != null) {
            setState(() {
              _removablePrimaryColor = null;
            });
            return false;
          }
          return true;
        },
        child: ItemCard(
          info: Info(
            label: appLocalizations.themeColor,
            iconData: Icons.palette,
          ),
          actions: genActions([
            if (_removablePrimaryColor == null)
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _handleChangeSchemeVariant,
                child: Text(Intl.message('${schemeVariant.name}Scheme')),
              ),
            if (_removablePrimaryColor != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  setState(() {
                    _removablePrimaryColor = null;
                  });
                },
                child: Text(appLocalizations.cancel),
              ),
            if (_removablePrimaryColor == null && !isEquals)
              IconButton.filledTonal(
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                onPressed: _handleReset,
                icon: const Icon(Icons.replay),
              ),
          ], space: 8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (_, constraints) {
                final columns = _calcColumns(constraints.maxWidth);
                final itemWidth =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final color in primaryColors)
                      Container(
                        clipBehavior: Clip.none,
                        width: itemWidth,
                        height: itemWidth,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            EffectGestureDetector(
                              child: ColorSchemeBox(
                                isSelected: color == primaryColor,
                                primaryColor: color != null
                                    ? Color(color)
                                    : null,
                                onPressed: () {
                                  setState(() {
                                    _removablePrimaryColor = null;
                                  });
                                  ref
                                      .read(themeSettingProvider.notifier)
                                      .update(
                                        (state) =>
                                            state.copyWith(primaryColor: color),
                                      );
                                },
                              ),
                              onLongPress: () {
                                setState(() {
                                  _removablePrimaryColor = color;
                                });
                              },
                            ),
                            if (_removablePrimaryColor != null &&
                                _removablePrimaryColor == color)
                              Container(
                                color: Colors.white.opacity0,
                                padding: const EdgeInsets.all(8),
                                child: IconButton.filledTonal(
                                  onPressed: _handleDel,
                                  padding: const EdgeInsets.all(12),
                                  iconSize: 30,
                                  icon: Icon(
                                    color: context.colorScheme.primary,
                                    Icons.delete,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_removablePrimaryColor == null)
                      Container(
                        width: itemWidth,
                        height: itemWidth,
                        padding: const EdgeInsets.all(4),
                        child: IconButton.filledTonal(
                          onPressed: _handleAdd,
                          iconSize: 32,
                          icon: Icon(
                            color: context.colorScheme.primary,
                            Icons.add,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PrueBlackItem extends ConsumerWidget {
  const _PrueBlackItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final prueBlack = ref.watch(
      themeSettingProvider.select((state) => state.pureBlack),
    );
    return SliverToBoxAdapter(
      child: ListItem.toggle(
        leading: const Icon(Icons.contrast),
        horizontalTitleGap: 12,
        title: Text(
          appLocalizations.pureBlackMode,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        value: prueBlack,
        onChanged: (value) {
          ref
              .read(themeSettingProvider.notifier)
              .update((state) => state.copyWith(pureBlack: value));
        },
      ),
    );
  }
}

class _TextScaleFactorItem extends ConsumerWidget {
  const _TextScaleFactorItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final textScale = ref.watch(
      themeSettingProvider.select((state) => state.textScale),
    );
    final String process = '${(textScale.scale * 100).round()}%';
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListItem.toggle(
              leading: const Icon(Icons.text_fields),
              horizontalTitleGap: 12,
              title: Text(
                appLocalizations.textScale,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              value: textScale.enable,
              onChanged: (value) {
                ref
                    .read(themeSettingProvider.notifier)
                    .update((state) => state.copyWith.textScale(enable: value));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              spacing: 32,
              children: [
                Expanded(
                  child: DisabledMask(
                    status: !textScale.enable,
                    child: ActivateBox(
                      active: textScale.enable,
                      child: SliderTheme(
                        data: SliderDefaultsM3(context),
                        child: Slider(
                          padding: EdgeInsets.zero,
                          min: minTextScale,
                          max: maxTextScale,
                          value: textScale.scale,
                          onChanged: (value) {
                            ref
                                .read(themeSettingProvider.notifier)
                                .update(
                                  (state) =>
                                      state.copyWith.textScale(scale: value),
                                );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(process, style: context.textTheme.titleMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteDialog extends StatefulWidget {
  const _PaletteDialog();

  @override
  State<_PaletteDialog> createState() => _PaletteDialogState();
}

class _PaletteDialogState extends State<_PaletteDialog> {
  final _controller = ValueNotifier<Color>(Color(Hct.from(0, 0, 60).toInt()));

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.palette,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(_controller.value.toARGB32());
          },
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 300, child: Palette(controller: _controller)),
        ],
      ),
    );
  }
}
