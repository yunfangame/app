import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/practical_tools.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'theme.dart';

class ToolsView extends StatelessWidget {
  const ToolsView({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: context.appLocalizations.practicalTools,
      body: const PracticalToolsView(),
    );
  }
}

class ToolLocaleSelector {
  static List<String> get options => [
    '',
    ...AppLocalizations.delegate.supportedLocales.map(
      (locale) => locale.toString(),
    ),
  ];

  static String getLocaleString(BuildContext context, String locale) {
    if (locale.isEmpty) return context.appLocalizations.defaultText;
    return Intl.message(locale);
  }

  static void update(WidgetRef ref, String locale) {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) => state.copyWith(locale: locale.isEmpty ? null : locale),
        );
  }

  static String getNativeLocaleString(BuildContext context, String locale) {
    if (locale.isEmpty) return context.appLocalizations.defaultText;
    return const {
          'en': 'English',
          'ja': '日本語',
          'ru': 'Русский',
          'zh_CN': '中文简体',
        }[locale] ??
        getLocaleString(context, locale);
  }

  static Future<void> show(BuildContext context) {
    return showAdaptiveAnchoredPanel<void>(
      context,
      panelWidth: 252,
      maxHeight: 520,
      builder: (_) => const ToolLocaleQuickPanel(),
    );
  }
}

class ToolLocaleQuickPanel extends ConsumerWidget {
  const ToolLocaleQuickPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuredLocale = ref.watch(
      appSettingProvider.select((state) => state.locale),
    );
    final currentLocale = configuredLocale ?? '';
    return Padding(
      key: const Key('locale-quick-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final locale in ToolLocaleSelector.options)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.of(context).pop();
                ToolLocaleSelector.update(ref, locale);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: locale == currentLocale
                          ? Icon(
                              Icons.check_rounded,
                              color: context.colorScheme.primary,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        ToolLocaleSelector.getNativeLocaleString(
                          context,
                          locale,
                        ),
                        style: context.textTheme.titleLarge?.copyWith(
                          color: locale == currentLocale
                              ? context.colorScheme.primary
                              : null,
                          fontWeight: locale == currentLocale
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
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

class ToolThemeSelector {
  static Future<void> show(BuildContext context) {
    return ThemeQuickSelector.show(context);
  }
}
