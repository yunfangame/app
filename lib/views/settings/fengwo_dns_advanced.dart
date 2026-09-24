import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/fake_ip_settings.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FengWoDnsAdvancedView extends ConsumerStatefulWidget {
  const FengWoDnsAdvancedView({super.key});

  @override
  ConsumerState<FengWoDnsAdvancedView> createState() =>
      _FengWoDnsAdvancedViewState();
}

class _FengWoDnsAdvancedViewState extends ConsumerState<FengWoDnsAdvancedView> {
  Future<void> _editFilters() async {
    final current = ref.read(patchClashConfigProvider).dns.fakeIpFilter;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _FakeIpFilterDialog(filters: current),
    );
    if (!mounted || result == null) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.dns(fakeIpFilter: result));
  }

  Future<void> _editRange() async {
    final current = ref.read(patchClashConfigProvider).dns.fakeIpRange;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FakeIpRangeDialog(value: current),
    );
    if (!mounted || result == null) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.dns(fakeIpRange: result));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dns = ref.watch(
      patchClashConfigProvider.select((config) => config.dns),
    );
    final overrideDns = ref.watch(overrideDnsProvider);
    final campusOverride = hasActiveCampusNetworkConfig(
      ref.watch(appSettingProvider),
    );
    final effectiveOverride = overrideDns || campusOverride;
    final fakeIpEnabled = dns.enhancedMode == DnsMode.fakeIp;
    final dnsEnabled = dns.enable || campusOverride;
    final desktop = switch (theme.platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final status = campusOverride
        ? l10n.dnsAdvancedCampusOverrideActive
        : overrideDns
        ? l10n.dnsAdvancedLocalOverrideActive
        : l10n.dnsAdvancedLocalOverrideInactive;
    return CommonScaffold(
      title: l10n.dnsAdvancedOptions,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              key: const ValueKey('dns-advanced-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.dnsAdvancedLocalSettings,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DnsSettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.overrideDns),
                          subtitle: Text(l10n.overrideDnsDesc),
                          value: effectiveOverride,
                          onChanged: campusOverride
                              ? null
                              : (value) {
                                  ref.read(overrideDnsProvider.notifier).value =
                                      value;
                                },
                          key: const ValueKey('dns-advanced-override-switch'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DnsMode>(
                          key: const ValueKey('dns-advanced-mode-dropdown'),
                          initialValue: dns.enhancedMode,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.dnsMode,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final mode in DnsMode.values)
                              DropdownMenuItem(
                                value: mode,
                                child: Text(_dnsModeLabel(mode)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            ref
                                .read(patchClashConfigProvider.notifier)
                                .update(
                                  (state) =>
                                      state.copyWith.dns(enhancedMode: value),
                                );
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          key: const ValueKey('dns-advanced-status'),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: desktop
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                status,
                                style: TextStyle(
                                  color: desktop
                                      ? null
                                      : scheme.onPrimaryContainer,
                                ),
                              ),
                              if (!dnsEnabled) ...[
                                const SizedBox(height: 8),
                                Text(l10n.dnsAdvancedDnsDisabled),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton(
                                    key: const ValueKey(
                                      'dns-advanced-enable-dns',
                                    ),
                                    onPressed: () {
                                      ref
                                          .read(
                                            patchClashConfigProvider.notifier,
                                          )
                                          .update(
                                            (state) => state.copyWith.dns(
                                              enable: true,
                                            ),
                                          );
                                    },
                                    child: Text(l10n.dnsAdvancedEnableDns),
                                  ),
                                ),
                              ] else if (!fakeIpEnabled) ...[
                                const SizedBox(height: 8),
                                Text(l10n.dnsAdvancedFakeIpInactive),
                              ] else if (effectiveOverride) ...[
                                const SizedBox(height: 8),
                                Text(l10n.dnsAdvancedFakeIpActive),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DnsSettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.fakeipFilter,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(l10n.dnsAdvancedFilterDescription),
                        const SizedBox(height: 8),
                        Text(
                          l10n.dnsAdvancedLocalFiltersHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.dnsAdvancedSavedFiltersCount(
                            dns.fakeIpFilter.length,
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          dns.fakeIpFilter.isEmpty
                              ? l10n.dnsAdvancedFilterEmpty
                              : dns.fakeIpFilter.join('\n'),
                          key: const ValueKey('dns-advanced-filter-preview'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.icon(
                            key: const ValueKey('dns-advanced-filter-edit'),
                            style: desktop
                                ? FilledButton.styleFrom(
                                    backgroundColor: scheme.secondaryContainer,
                                    foregroundColor:
                                        scheme.onSecondaryContainer,
                                  )
                                : null,
                            onPressed: _editFilters,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(l10n.edit),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (desktop) ...[
                    const SizedBox(height: 16),
                    _DnsSettingsCard(
                      child: ExpansionTile(
                        key: const ValueKey('dns-advanced-range-expansion'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        title: Text(l10n.fakeipRange),
                        subtitle: Text(dns.fakeIpRange),
                        children: [
                          Text(l10n.dnsAdvancedRangeDescription),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              key: const ValueKey('dns-advanced-range-edit'),
                              onPressed: _editRange,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(l10n.edit),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DnsSettingsCard extends StatelessWidget {
  const _DnsSettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _FakeIpFilterDialog extends StatefulWidget {
  const _FakeIpFilterDialog({required this.filters});

  final List<String> filters;

  @override
  State<_FakeIpFilterDialog> createState() => _FakeIpFilterDialogState();
}

class _FakeIpFilterDialogState extends State<_FakeIpFilterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text: widget.filters.join('\n'),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      title: Text(l10n.fakeipFilter),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.dnsAdvancedFilterEditingHint),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: TextFormField(
                key: const ValueKey('dns-fake-ip-filter-input'),
                controller: _controller,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  errorMaxLines: 4,
                ),
                validator: (value) {
                  for (final entry in normalizeFakeIpFilters(value ?? '')) {
                    if (!isValidFakeIpFilter(entry)) {
                      return l10n.dnsAdvancedFilterInvalid(entry);
                    }
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('dns-fake-ip-filter-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('dns-fake-ip-filter-save'),
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(normalizeFakeIpFilters(_controller.text));
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _FakeIpRangeDialog extends StatefulWidget {
  const _FakeIpRangeDialog({required this.value});

  final String value;

  @override
  State<_FakeIpRangeDialog> createState() => _FakeIpRangeDialogState();
}

class _FakeIpRangeDialogState extends State<_FakeIpRangeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      title: Text(l10n.fakeipRange),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('dns-fake-ip-range-input'),
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: l10n.fakeipRange,
              hintText: '198.18.0.1/16',
              errorMaxLines: 4,
              border: const OutlineInputBorder(),
            ),
            validator: (value) => isValidFakeIpRange(value ?? '')
                ? null
                : l10n.dnsAdvancedRangeInvalid,
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('dns-fake-ip-range-reset'),
          onPressed: () => _controller.text = '198.18.0.1/16',
          child: Text(l10n.reset),
        ),
        TextButton(
          key: const ValueKey('dns-fake-ip-range-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('dns-fake-ip-range-save'),
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

String _dnsModeLabel(DnsMode mode) => switch (mode) {
  DnsMode.normal => 'normal',
  DnsMode.fakeIp => 'fake-ip',
  DnsMode.redirHost => 'redir-host',
  DnsMode.hosts => 'hosts',
};
