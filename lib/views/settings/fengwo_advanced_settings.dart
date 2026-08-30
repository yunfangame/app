import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef GeoResourceUpdater = Future<void> Function(GeoResource resource);
typedef CampusNetworkConfigLoader = Future<CampusNetworkConfig> Function();
typedef CampusNetworkCoreRestarter = Future<void> Function();

class FengWoAdvancedSettingsView extends ConsumerStatefulWidget {
  final GeoResourceUpdater? geoResourceUpdater;
  final CampusNetworkConfigLoader? campusNetworkConfigLoader;
  final CampusNetworkCoreRestarter? campusNetworkCoreRestarter;

  const FengWoAdvancedSettingsView({
    super.key,
    this.geoResourceUpdater,
    this.campusNetworkConfigLoader,
    this.campusNetworkCoreRestarter,
  });

  @override
  ConsumerState<FengWoAdvancedSettingsView> createState() =>
      _FengWoAdvancedSettingsViewState();
}

class _FengWoAdvancedSettingsViewState
    extends ConsumerState<FengWoAdvancedSettingsView> {
  final Set<GeoResource> _updatingResources = {};
  bool _updatingAll = false;
  bool _updatingCampusNetwork = false;

  Future<CampusNetworkConfig> _loadCampusNetworkConfig() async {
    final loader = widget.campusNetworkConfigLoader;
    if (loader != null) {
      return loader();
    }
    final remoteConfig = await ApiHealthService().loadConfig();
    return CampusNetworkConfig.fromRemote(remoteConfig);
  }

  Future<void> _restartCoreForCampusNetwork() {
    return widget.campusNetworkCoreRestarter?.call() ??
        ref.read(coreActionProvider.notifier).restartCore();
  }

  Future<void> _setCampusNetworkEnabled(bool enabled) async {
    if (_updatingCampusNetwork) return;
    final previous = ref.read(appSettingProvider);
    setState(() => _updatingCampusNetwork = true);
    try {
      var hostsByOperator = previous.campusHostsByOperator;
      if (enabled && !hasCompleteCampusNetworkConfig(hostsByOperator)) {
        hostsByOperator = (await _loadCampusNetworkConfig()).hostsByOperator;
      }
      if (!mounted) return;
      final next = previous.copyWith(
        campusNetworkEnabled: enabled,
        campusHostsByOperator: hostsByOperator,
      );
      ref.read(appSettingProvider.notifier).value = next;
      try {
        await _restartCoreForCampusNetwork();
      } catch (_) {
        ref.read(appSettingProvider.notifier).value = previous;
        rethrow;
      }
      if (mounted) {
        context.showNotifier(
          enabled
              ? context.appLocalizations.campusNetworkEnabled
              : context.appLocalizations.campusNetworkDisabled,
        );
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'update campus network mode failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        context.showNotifier(context.appLocalizations.campusNetworkApplyFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingCampusNetwork = false);
    }
  }

  Future<void> _selectCampusOperator() async {
    if (_updatingCampusNetwork) return;
    final previous = ref.read(appSettingProvider);
    final selected = await showDialog<CampusOperator>(
      context: context,
      builder: (_) => OptionsDialog<CampusOperator>(
        title: context.appLocalizations.campusNetworkLine,
        options: CampusOperator.values,
        textBuilder: _campusOperatorLabel,
        value: previous.campusOperator,
      ),
    );
    if (selected == null || selected == previous.campusOperator || !mounted) {
      return;
    }
    final next = previous.copyWith(campusOperator: selected);
    if (!previous.campusNetworkEnabled) {
      ref.read(appSettingProvider.notifier).value = next;
      return;
    }
    setState(() => _updatingCampusNetwork = true);
    ref.read(appSettingProvider.notifier).value = next;
    try {
      await _restartCoreForCampusNetwork();
      if (mounted) {
        context.showNotifier(context.appLocalizations.campusNetworkEnabled);
      }
    } catch (error, stackTrace) {
      ref.read(appSettingProvider.notifier).value = previous;
      commonPrint.log(
        'switch campus network line failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        context.showNotifier(context.appLocalizations.campusNetworkApplyFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingCampusNetwork = false);
    }
  }

  Future<void> _editMixedPort() async {
    final l10n = context.appLocalizations;
    final current = ref.read(patchClashConfigProvider).mixedPort;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => InputDialog(
        title: l10n.mixedPort,
        value: '$current',
        resetValue: '$defaultMixedPort',
        keyboardType: TextInputType.number,
        maxLength: 5,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (value) {
          final port = int.tryParse(value ?? '');
          if (port == null || port < 1024 || port > 49151) {
            return l10n.portTip(l10n.mixedPort);
          }
          return null;
        },
      ),
    );
    final port = int.tryParse(value ?? '');
    if (port == null || port == current) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: port));
  }

  Future<void> _copyProxyAddress() async {
    final port = ref.read(patchClashConfigProvider).mixedPort;
    await Clipboard.setData(ClipboardData(text: '127.0.0.1:$port'));
    if (mounted) context.showNotifier(context.appLocalizations.copySuccess);
  }

  Future<void> _selectDnsMode() async {
    final l10n = context.appLocalizations;
    final current = ref.read(patchClashConfigProvider).dns.enhancedMode;
    final value = await showDialog<DnsMode>(
      context: context,
      builder: (_) => OptionsDialog<DnsMode>(
        title: l10n.dnsMode,
        options: DnsMode.values,
        textBuilder: _dnsModeLabel,
        value: current,
      ),
    );
    if (value == null || value == current) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.dns(enhancedMode: value));
  }

  Future<void> _editDnsServers() async {
    final l10n = context.appLocalizations;
    final current = ref.read(patchClashConfigProvider).dns.nameserver;
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ListInputPage(
          title: l10n.customDnsServers,
          items: List<String>.from(current),
          itemMaxLength: TextInputLimits.dnsServer,
          titleBuilder: Text.new,
        ),
      ),
    );
    if (result == null || stringListEquality.equals(result, current)) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.dns(nameserver: result));
  }

  Future<void> _updateGeoResource(
    GeoResource resource, {
    bool showSuccess = true,
  }) async {
    if (_updatingResources.contains(resource)) return;
    setState(() => _updatingResources.add(resource));
    try {
      final updater = widget.geoResourceUpdater;
      if (updater != null) {
        await updater(resource);
      } else {
        await ref
            .read(geoResourceActionProvider.notifier)
            .updateGeoResource(resource);
      }
      if (mounted && showSuccess) {
        context.showNotifier(
          context.appLocalizations.geoUpdated(_geoResourceLabel(resource)),
        );
      }
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _updatingResources.remove(resource));
    }
  }

  Future<void> _updateAllGeoResources() async {
    if (_updatingAll) return;
    setState(() => _updatingAll = true);
    try {
      for (final resource in _geoResources) {
        await _updateGeoResource(resource, showSuccess: false);
      }
      if (mounted) {
        context.showNotifier(context.appLocalizations.allGeodataUpdated);
      }
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _AdvancedColors.of(context);
    return Material(
      color: colors.background,
      child: CustomScrollView(
        key: const ValueKey('fengwo-advanced-settings-scroll'),
        slivers: [
          SliverToBoxAdapter(child: _AdvancedHeader(colors: colors)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1480),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop = constraints.maxWidth >= 640;
                      if (!desktop) {
                        return Column(
                          children: [
                            _buildProxyCard(colors),
                            const SizedBox(height: 16),
                            _buildIpv6Card(colors),
                            const SizedBox(height: 16),
                            _buildCampusNetworkCard(colors),
                            const SizedBox(height: 16),
                            _buildDnsCard(colors),
                            const SizedBox(height: 16),
                            _buildGeoCard(colors),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _buildProxyCard(colors)),
                                const SizedBox(width: 18),
                                Expanded(child: _buildIpv6Card(colors)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildCampusNetworkCard(colors),
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: _buildDnsCard(colors)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildGeoCard(colors),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyCard(_AdvancedColors colors) {
    final l10n = context.appLocalizations;
    final mixedPort = ref.watch(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    final allowLan = ref.watch(
      patchClashConfigProvider.select((state) => state.allowLan),
    );
    final address = '127.0.0.1:$mixedPort';
    return _AdvancedCard(
      key: const ValueKey('advanced-proxy-card'),
      colors: colors,
      child: Column(
        children: [
          _CardHeading(
            colors: colors,
            icon: Icons.hub_outlined,
            title: l10n.proxySettings,
            subtitle: l10n.proxySettingsSubtitle,
            accent: colors.green,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            colors: colors,
            icon: Icons.tag_rounded,
            iconColor: colors.blue,
            title: l10n.mixedPort,
            subtitle: l10n.mixedPortSharedDescription,
            trailing: OutlinedButton(
              key: const ValueKey('advanced-mixed-port-button'),
              onPressed: _editMixedPort,
              child: Text(
                '$mixedPort',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          Divider(height: 1, color: colors.outline),
          _SettingsRow(
            colors: colors,
            icon: Icons.link_rounded,
            iconColor: colors.orange,
            title: l10n.allowLan,
            subtitle: l10n.allowLanDesc,
            trailing: Switch(
              key: const ValueKey('advanced-allow-lan-switch'),
              value: allowLan,
              onChanged: (value) {
                ref
                    .read(patchClashConfigProvider.notifier)
                    .update((state) => state.copyWith(allowLan: value));
              },
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: colors.surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: const ValueKey('advanced-copy-proxy-address'),
              onTap: _copyProxyAddress,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, color: colors.muted, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.proxyAccessAddress,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            address,
                            style: TextStyle(
                              color: colors.text,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _copyProxyAddress,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(l10n.copy),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpv6Card(_AdvancedColors colors) {
    final l10n = context.appLocalizations;
    final ipv6 = ref.watch(
      patchClashConfigProvider.select((state) => state.ipv6),
    );
    final dnsIpv6 = ref.watch(
      patchClashConfigProvider.select((state) => state.dns.ipv6),
    );
    return _AdvancedCard(
      key: const ValueKey('advanced-ipv6-card'),
      colors: colors,
      child: Column(
        children: [
          _CardHeading(
            colors: colors,
            icon: Icons.water_drop_outlined,
            title: l10n.ipv6Settings,
            subtitle: l10n.ipv6SettingsSubtitle,
            accent: colors.blue,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            colors: colors,
            icon: Icons.adjust_rounded,
            iconColor: colors.cyan,
            title: l10n.coreIpv6,
            subtitle: l10n.coreIpv6Description,
            trailing: Switch(
              key: const ValueKey('advanced-core-ipv6-switch'),
              value: ipv6,
              onChanged: (value) {
                ref
                    .read(patchClashConfigProvider.notifier)
                    .update((state) => state.copyWith(ipv6: value));
              },
            ),
          ),
          Divider(height: 1, color: colors.outline),
          _SettingsRow(
            colors: colors,
            icon: Icons.water_drop_outlined,
            iconColor: colors.cyan,
            title: l10n.dnsIpv6,
            subtitle: l10n.dnsIpv6Description,
            trailing: Switch(
              key: const ValueKey('advanced-dns-ipv6-switch'),
              value: dnsIpv6,
              onChanged: (value) {
                ref
                    .read(patchClashConfigProvider.notifier)
                    .update((state) => state.copyWith.dns(ipv6: value));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeoCard(_AdvancedColors colors) {
    final l10n = context.appLocalizations;
    return _AdvancedCard(
      key: const ValueKey('advanced-geodata-card'),
      colors: colors,
      child: Column(
        children: [
          _CardHeading(
            colors: colors,
            icon: Icons.cloud_outlined,
            title: l10n.geodataSettings,
            subtitle: l10n.geodataSettingsSubtitle,
            accent: colors.purple,
            trailing: OutlinedButton.icon(
              key: const ValueKey('advanced-update-all-geodata'),
              onPressed: _updatingAll ? null : _updateAllGeoResources,
              icon: _updatingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(l10n.updateAll),
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < _geoResources.length; index++) ...[
            _GeoResourceRow(
              colors: colors,
              resource: _geoResources[index],
              updating: _updatingResources.contains(_geoResources[index]),
              onUpdate: () => _updateGeoResource(_geoResources[index]),
            ),
            if (index != _geoResources.length - 1)
              Divider(height: 1, color: colors.outline),
          ],
        ],
      ),
    );
  }

  Widget _buildCampusNetworkCard(_AdvancedColors colors) {
    final l10n = context.appLocalizations;
    final settings = ref.watch(appSettingProvider);
    return _AdvancedCard(
      key: const ValueKey('advanced-campus-network-card'),
      colors: colors,
      child: Column(
        children: [
          _CardHeading(
            colors: colors,
            icon: Icons.school_outlined,
            title: l10n.campusNetworkMode,
            subtitle: l10n.campusNetworkModeSubtitle,
            accent: colors.orange,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            colors: colors,
            icon: Icons.route_outlined,
            iconColor: colors.orange,
            title: l10n.campusNetworkSwitch,
            subtitle: l10n.campusNetworkSwitchDescription,
            trailing: Switch(
              key: const ValueKey('advanced-campus-network-switch'),
              value: settings.campusNetworkEnabled,
              onChanged: _updatingCampusNetwork
                  ? null
                  : _setCampusNetworkEnabled,
            ),
          ),
          const SizedBox(height: 8),
          _NavigationSettingTile(
            key: const ValueKey('advanced-campus-network-line-tile'),
            colors: colors,
            icon: Icons.alt_route_rounded,
            iconColor: colors.blue,
            title: l10n.campusNetworkLine,
            subtitle: _campusOperatorLabel(settings.campusOperator),
            onTap: _selectCampusOperator,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSoft,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: colors.muted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.campusNetworkInformation,
                    style: TextStyle(
                      color: colors.muted,
                      height: 1.35,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDnsCard(_AdvancedColors colors) {
    final l10n = context.appLocalizations;
    final overrideDns = ref.watch(overrideDnsProvider);
    final dns = ref.watch(
      patchClashConfigProvider.select((state) => state.dns),
    );
    return _AdvancedCard(
      key: const ValueKey('advanced-dns-card'),
      colors: colors,
      child: Column(
        children: [
          _CardHeading(
            colors: colors,
            icon: Icons.dns_outlined,
            title: l10n.dnsSettings,
            subtitle: l10n.dnsSettingsSubtitle,
            accent: colors.green,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            colors: colors,
            icon: Icons.dns_outlined,
            iconColor: colors.green,
            title: l10n.overrideDns,
            subtitle: l10n.overrideDnsDesc,
            trailing: Switch(
              key: const ValueKey('advanced-override-dns-switch'),
              value: overrideDns,
              onChanged: (value) {
                ref.read(overrideDnsProvider.notifier).value = value;
              },
            ),
          ),
          const SizedBox(height: 8),
          _NavigationSettingTile(
            key: const ValueKey('advanced-dns-mode-tile'),
            colors: colors,
            icon: Icons.tune_rounded,
            iconColor: colors.purple,
            title: l10n.dnsMode,
            subtitle: _dnsModeLabel(dns.enhancedMode),
            onTap: _selectDnsMode,
          ),
          const SizedBox(height: 8),
          _NavigationSettingTile(
            key: const ValueKey('advanced-custom-dns-tile'),
            colors: colors,
            icon: Icons.edit_outlined,
            iconColor: colors.blue,
            title: l10n.customDnsServers,
            subtitle: l10n.savedDnsServersCount(dns.nameserver.length),
            onTap: _editDnsServers,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSoft,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: colors.muted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.dnsOverrideInformation,
                    style: TextStyle(
                      color: colors.muted,
                      height: 1.35,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _geoResources = [
  GeoResource.GEOIP,
  GeoResource.GEOSITE,
  GeoResource.MMDB,
  GeoResource.ASN,
];

String _geoResourceLabel(GeoResource resource) {
  return switch (resource) {
    GeoResource.GEOIP => 'GeoIP',
    GeoResource.GEOSITE => 'GeoSite',
    GeoResource.MMDB => 'MMDB',
    GeoResource.ASN => 'ASN',
  };
}

String _dnsModeLabel(DnsMode mode) {
  return switch (mode) {
    DnsMode.normal => 'normal',
    DnsMode.fakeIp => 'fake-ip',
    DnsMode.redirHost => 'redir-host',
    DnsMode.hosts => 'hosts',
  };
}

String _campusOperatorLabel(CampusOperator operator) {
  final l10n = currentAppLocalizations;
  return switch (operator) {
    CampusOperator.telecom => l10n.campusNetworkLine1,
    CampusOperator.unicom => l10n.campusNetworkLine2,
    CampusOperator.mobile => l10n.campusNetworkLine3,
  };
}

class _AdvancedHeader extends StatelessWidget {
  final _AdvancedColors colors;

  const _AdvancedHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 144),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primarySoft, colors.background, colors.secondarySoft],
        ),
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (!compact)
                Positioned(
                  right: 20,
                  top: -30,
                  bottom: -30,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        _HeaderGlyph(
                          colors: colors,
                          icon: Icons.tune_rounded,
                          angle: -0.08,
                        ),
                        const SizedBox(width: 16),
                        _HeaderGlyph(
                          colors: colors,
                          icon: Icons.settings_outlined,
                          angle: 0.04,
                          size: 126,
                        ),
                        const SizedBox(width: 16),
                        _HeaderGlyph(
                          colors: colors,
                          icon: Icons.dns_outlined,
                          angle: 0.08,
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 28,
                  26,
                  compact ? 20 : 260,
                  24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.appLocalizations.advancedSettings,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: compact ? 29 : 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.appLocalizations.advancedSettingsSubtitle,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderGlyph extends StatelessWidget {
  final _AdvancedColors colors;
  final IconData icon;
  final double angle;
  final double size;

  const _HeaderGlyph({
    required this.colors,
    required this.icon,
    required this.angle,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.outline),
          boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 24)],
        ),
        child: Icon(
          icon,
          size: size * 0.48,
          color: colors.primary.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

class _AdvancedCard extends StatelessWidget {
  final _AdvancedColors colors;
  final Widget child;

  const _AdvancedCard({super.key, required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 24)],
      ),
      child: child,
    );
  }
}

class _CardHeading extends StatelessWidget {
  final _AdvancedColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? trailing;

  const _CardHeading({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TintedIcon(icon: icon, color: accent, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final _AdvancedColors colors;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsRow({
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _TintedIcon(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _NavigationSettingTile extends StatelessWidget {
  final _AdvancedColors colors;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavigationSettingTile({
    super.key,
    required this.colors,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            children: [
              _TintedIcon(icon: icon, color: iconColor, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeoResourceRow extends StatelessWidget {
  final _AdvancedColors colors;
  final GeoResource resource;
  final bool updating;
  final VoidCallback onUpdate;

  const _GeoResourceRow({
    required this.colors,
    required this.resource,
    required this.updating,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (resource) {
      GeoResource.GEOIP => colors.blue,
      GeoResource.GEOSITE => colors.green,
      GeoResource.MMDB => colors.orange,
      GeoResource.ASN => colors.purple,
    };
    final icon = switch (resource) {
      GeoResource.GEOIP => Icons.location_on_outlined,
      GeoResource.GEOSITE => Icons.public_rounded,
      GeoResource.MMDB => Icons.storage_rounded,
      GeoResource.ASN => Icons.dns_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _TintedIcon(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _geoResourceLabel(resource),
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            key: ValueKey('advanced-update-${resource.name}'),
            tooltip: context.appLocalizations.update,
            onPressed: updating ? null : onUpdate,
            icon: updating
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }
}

class _TintedIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _TintedIcon({required this.icon, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class _AdvancedColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color secondarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color shadow;
  final Color blue;
  final Color cyan;
  final Color green;
  final Color orange;
  final Color purple;

  const _AdvancedColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.secondarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.shadow,
    required this.blue,
    required this.cyan,
    required this.green,
    required this.orange,
    required this.purple,
  });

  factory _AdvancedColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _AdvancedColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
        scheme.surface,
      ),
      surface: scheme.surfaceContainerLowest,
      surfaceSoft: scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.2 : 0.1),
      secondarySoft: scheme.tertiary.withValues(alpha: dark ? 0.12 : 0.07),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: 0.82),
      shadow: Colors.black.withValues(alpha: dark ? 0.3 : 0.075),
      blue: scheme.primary,
      cyan: dark ? const Color(0xFF62D8E8) : const Color(0xFF18AFC4),
      green: dark ? const Color(0xFF62E1B3) : const Color(0xFF22B884),
      orange: dark ? const Color(0xFFFFB86A) : const Color(0xFFF08A36),
      purple: dark ? const Color(0xFFC6A1FF) : const Color(0xFF8C5DE8),
    );
  }
}
