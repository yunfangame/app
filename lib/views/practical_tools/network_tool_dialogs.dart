import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/streaming_unlock.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:simple_icons/simple_icons.dart';

class SpeedTestDialog extends StatelessWidget {
  const SpeedTestDialog({super.key});

  static const _services = [
    ('Speedtest', 'Ookla', 'https://www.speedtest.net/zh-Hans'),
    ('Google Fiber', 'Google Fiber', 'https://fiber.google.com/speedtest/'),
    ('Fast.com', 'Netflix', 'https://fast.com'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _NetworkDialogIcon(
                    icon: Icons.speed_rounded,
                    color: Color(0xFF2F80ED),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      context.appLocalizations.speedTest,
                      style: context.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final service in _services) ...[
                Material(
                  color: context.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    minTileHeight: 86,
                    leading: const Icon(Icons.speed_rounded, size: 34),
                    title: Text(
                      service.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(service.$2),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => globalState.openUrl(service.$3),
                  ),
                ),
                if (service != _services.last) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class IpLookupDialog extends StatefulWidget {
  const IpLookupDialog({super.key});

  @override
  State<IpLookupDialog> createState() => _IpLookupDialogState();
}

class _IpLookupDialogState extends State<IpLookupDialog> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await request
          .getTextResponseForUrl('https://ipwho.is')
          .timeout(const Duration(seconds: 10));
      final value = jsonDecode(response.data ?? '');
      if (value is! Map<String, dynamic> || value['success'] == false) {
        throw const FormatException('invalid IP response');
      }
      if (mounted) setState(() => _data = value);
    } catch (_) {
      if (mounted) setState(() => _data = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(String key, [String? nested]) {
    final data = _data;
    if (data == null) return '--';
    final value = nested == null
        ? data[key]
        : (data[key] is Map ? (data[key] as Map)[nested] : null);
    return value?.toString().trim().isNotEmpty == true
        ? value.toString().trim()
        : '--';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final ip = _value('ip');
    final rows = [
      (l10n.countryRegion, '${_value('country')} · ${_value('country_code')}'),
      (l10n.provinceCity, '${_value('region')} · ${_value('city')}'),
      (l10n.carrier, _value('connection', 'isp')),
      (l10n.organization, _value('connection', 'org')),
      (l10n.asnLabel, _value('connection', 'asn')),
      (l10n.timezoneLabel, _value('timezone', 'id')),
      (l10n.dataSource, 'ipwho.is'),
    ];
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _NetworkDialogIcon(
                    icon: Icons.location_on_outlined,
                    color: Color(0xFF16B86A),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ipLookup,
                          style: context.textTheme.titleMedium?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _loading ? '…' : ip,
                          style: context.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: _data == null
                            ? _ErrorPanel(
                                message: l10n.ipLookupFailed,
                                onRetry: _load,
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: context
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: .22),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(l10n.publicIp),
                                              const SizedBox(height: 5),
                                              Text(
                                                ip,
                                                style: context
                                                    .textTheme
                                                    .headlineMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(text: ip),
                                            );
                                            if (context.mounted) {
                                              context.showNotifier(
                                                l10n.copySuccess,
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.copy_rounded),
                                          label: Text(l10n.copy),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  for (final row in rows) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 17,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context
                                            .colorScheme
                                            .surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 150,
                                            child: Text(
                                              row.$1,
                                              style: TextStyle(
                                                color: context
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              row.$2,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
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

class StreamingTestDialog extends ConsumerStatefulWidget {
  const StreamingTestDialog({super.key, this.tester});

  final StreamingUnlockTester? tester;

  @override
  ConsumerState<StreamingTestDialog> createState() =>
      _StreamingTestDialogState();
}

class _StreamingTestDialogState extends ConsumerState<StreamingTestDialog> {
  static const _services = [
    (
      platform: StreamingPlatform.netflix,
      name: 'Netflix',
      brand: _Brand.netflix,
    ),
    (
      platform: StreamingPlatform.disneyPlus,
      name: 'Disney+',
      brand: _Brand.disneyPlus,
    ),
    (
      platform: StreamingPlatform.youtubePremium,
      name: 'YouTube Premium',
      brand: _Brand.youtube,
    ),
    (
      platform: StreamingPlatform.chatGpt,
      name: 'ChatGPT',
      brand: _Brand.openAi,
    ),
    (platform: StreamingPlatform.gemini, name: 'Gemini', brand: _Brand.gemini),
    (platform: StreamingPlatform.claude, name: 'Claude', brand: _Brand.claude),
    (platform: StreamingPlatform.tikTok, name: 'TikTok', brand: _Brand.tikTok),
  ];

  late final StreamingUnlockTester _tester;
  final Map<StreamingPlatform, StreamingUnlockResult> _results = {};
  final Set<StreamingPlatform> _testingPlatforms = {};
  bool _testing = false;
  String? _exitRegion;

  @override
  void initState() {
    super.initState();
    _tester = widget.tester ?? StreamingUnlockTester();
  }

  bool _ensureProxyStarted() {
    if (ref.read(isStartProvider)) return true;
    context.showNotifier(context.appLocalizations.streamingProxyRequired);
    return false;
  }

  Future<void> _testOne(_StreamingService service) async {
    if (!_ensureProxyStarted() ||
        _testingPlatforms.contains(service.platform)) {
      return;
    }
    setState(() => _testingPlatforms.add(service.platform));
    final result = await _tester.test(service.platform);
    _storeResult(result);
  }

  Future<void> _testAll() async {
    if (_testing || !_ensureProxyStarted()) return;
    setState(() {
      _testing = true;
      _testingPlatforms.addAll(_services.map((service) => service.platform));
    });
    try {
      unawaited(_updateExitRegion());
      await _tester.testAll(
        _services.map((service) => service.platform),
        maxConcurrent: 2,
        onResult: _storeResult,
      );
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
          _testingPlatforms.clear();
        });
      }
    }
  }

  Future<void> _updateExitRegion() async {
    try {
      final ipResult = await request.checkIp().timeout(
        const Duration(seconds: 12),
      );
      if (mounted) setState(() => _exitRegion = ipResult.data?.countryCode);
    } catch (_) {}
  }

  void _storeResult(StreamingUnlockResult result) {
    commonPrint.log(
      'streaming ${result.platform.name}: ${result.status.name}, '
      'reason=${result.failureReason?.name}, region=${result.region}',
    );
    if (!mounted) return;
    setState(() {
      _results[result.platform] = result;
      _testingPlatforms.remove(result.platform);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final available = _results.values
        .where((result) => result.isPageAccessible)
        .length;
    final completed = _results.length;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 850),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(26),
              child: Row(
                children: [
                  const _NetworkDialogIcon(
                    icon: Icons.movie_filter_outlined,
                    color: Color(0xFF8057F5),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.streamingUnlockTest,
                          style: context.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          l10n.streamingUnlockTestDescription,
                          style: TextStyle(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _testing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountChip(
                    label: l10n.platformCount,
                    value: _services.length,
                  ),
                  _CountChip(label: l10n.availableCount, value: available),
                  _CountChip(label: l10n.completedCount, value: completed),
                  if (_exitRegion != null)
                    Chip(
                      avatar: const Icon(Icons.public_rounded, size: 18),
                      label: Text('${l10n.streamingExitRegion} $_exitRegion'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                itemCount: _services.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final service = _services[index];
                  final result = _results[service.platform];
                  final testing = _testingPlatforms.contains(service.platform);
                  final statusIcon = switch (result?.status) {
                    StreamingUnlockStatus.unlocked => const Text(
                      '✅',
                      style: TextStyle(fontSize: 23),
                    ),
                    StreamingUnlockStatus.reachable => const Text(
                      '✅',
                      style: TextStyle(fontSize: 23),
                    ),
                    StreamingUnlockStatus.restricted => const Icon(
                      Icons.block_rounded,
                      color: Colors.redAccent,
                    ),
                    StreamingUnlockStatus.failed => const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    null => null,
                  };
                  return Material(
                    color: context.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      minTileHeight: 78,
                      leading: _BrandLogo(brand: service.brand),
                      title: Text(
                        service.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_statusLabel(context, result, testing)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ?statusIcon,
                          IconButton(
                            onPressed: testing ? null : () => _testOne(service),
                            icon: testing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.closeAction),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _testing ? null : _testAll,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.testAll),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(
    BuildContext context,
    StreamingUnlockResult? result,
    bool testing,
  ) {
    final l10n = context.appLocalizations;
    if (testing) return l10n.testingStatus;
    if (result == null) return l10n.pendingTest;
    final label = switch ((result.status, result.failureReason)) {
      (StreamingUnlockStatus.reachable, StreamingUnlockFailureReason.timeout) =>
        l10n.streamingReachableProbeTimedOut,
      (
        StreamingUnlockStatus.reachable,
        StreamingUnlockFailureReason.network ||
            StreamingUnlockFailureReason.service,
      ) =>
        l10n.streamingReachableProbeFailed,
      (StreamingUnlockStatus.failed, StreamingUnlockFailureReason.timeout) =>
        l10n.streamingTimedOut,
      (StreamingUnlockStatus.failed, StreamingUnlockFailureReason.network) =>
        l10n.streamingNetworkError,
      (StreamingUnlockStatus.failed, StreamingUnlockFailureReason.service) =>
        l10n.streamingServiceError,
      (StreamingUnlockStatus.unlocked, _) => l10n.streamingUnlocked,
      (StreamingUnlockStatus.reachable, _) => l10n.streamingReachable,
      (StreamingUnlockStatus.restricted, _) => l10n.streamingRestricted,
      (StreamingUnlockStatus.failed, _) => l10n.streamingFailed,
    };
    final region = result.region ?? _exitRegion;
    return region == null ? label : '$label · $region';
  }
}

class PopularAppsDialog extends StatelessWidget {
  const PopularAppsDialog({super.key});

  static const _apps = [
    (
      name: 'Telegram',
      url: 'https://telegram.org/apps',
      brand: _Brand.telegram,
    ),
    (name: 'X', url: 'https://x.com/', brand: _Brand.x),
    (name: 'YouTube', url: 'https://www.youtube.com/', brand: _Brand.youtube),
    (name: 'Netflix', url: 'https://www.netflix.com/', brand: _Brand.netflix),
    (name: 'ChatGPT', url: 'https://chatgpt.com/', brand: _Brand.openAi),
    (
      name: 'Cloudflare Speed',
      url: 'https://speed.cloudflare.com/',
      brand: _Brand.cloudflare,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.appLocalizations.popularApps),
      content: SizedBox(
        width: 560,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.4,
          ),
          itemCount: _apps.length,
          itemBuilder: (context, index) {
            final app = _apps[index];
            return Material(
              color: context.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => globalState.openUrl(app.url),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _BrandLogo(brand: app.brand, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          app.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Icon(Icons.open_in_new_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appLocalizations.closeAction),
        ),
      ],
    );
  }
}

class ChainProxyDialog extends ConsumerStatefulWidget {
  const ChainProxyDialog({super.key, this.validator, this.coreRestarter});

  final ChainProxyValidator? validator;
  final Future<void> Function()? coreRestarter;

  @override
  ConsumerState<ChainProxyDialog> createState() => _ChainProxyDialogState();
}

class _ChainProxyDialogState extends ConsumerState<ChainProxyDialog> {
  String? _workingName;

  Future<void> _openForm([ChainProxyConfig? existing]) async {
    final settings = ref.read(appSettingProvider);
    if (activeChainProxy(settings) != null || _workingName != null) return;
    final entry = await showDialog<ChainProxyConfig>(
      context: context,
      builder: (_) => _ChainProxyFormDialog(
        existing: existing,
        entries: settings.chainProxies,
      ),
    );
    if (entry == null || !mounted) return;
    final current = ref.read(appSettingProvider);
    final entries = [...current.chainProxies];
    if (existing == null) {
      entries.add(entry);
    } else {
      final index = entries.indexWhere((item) => item.name == existing.name);
      if (index == -1) return;
      entries[index] = entry;
    }
    ref.read(appSettingProvider.notifier).value = current.copyWith(
      chainProxies: entries,
    );
  }

  void _delete(ChainProxyConfig entry) {
    final settings = ref.read(appSettingProvider);
    if (activeChainProxy(settings) != null || _workingName != null) return;
    ref.read(appSettingProvider.notifier).value = settings.copyWith(
      chainProxies: settings.chainProxies
          .where((item) => item.name != entry.name)
          .toList(),
    );
  }

  Future<ChainProxyValidationResult> _validateActiveProxy(
    ChainProxyConfig entry,
    String testUrl,
  ) async {
    final validator = widget.validator;
    if (validator != null) return validator(entry);
    try {
      final delay = await coreController.getDelay(
        testUrl,
        chainProxyRuntimeName,
      );
      final available = delay.value != null && delay.value! > 0;
      commonPrint.event(
        'chain_proxy.validation.completed',
        fields: {'success': available, 'delay_ms': delay.value},
      );
      return ChainProxyValidationResult(
        available
            ? ChainProxyValidationStatus.available
            : ChainProxyValidationStatus.unavailable,
      );
    } catch (error) {
      commonPrint.event(
        'chain_proxy.validation.failed',
        fields: {'error_type': error.runtimeType.toString(), 'error': '$error'},
      );
      return const ChainProxyValidationResult(
        ChainProxyValidationStatus.unavailable,
      );
    }
  }

  Future<void> _setActive(ChainProxyConfig entry, bool enabled) async {
    if (_workingName != null) return;
    if (enabled && ref.read(patchClashConfigProvider).mode == Mode.direct) {
      context.showNotifier(
        context.appLocalizations.chainProxyDirectModeUnsupported,
      );
      return;
    }
    final previous = ref.read(appSettingProvider);
    if (enabled && previous.activeChainProxyName != null) return;
    final settingsNotifier = ref.read(appSettingProvider.notifier);
    final restartCore =
        widget.coreRestarter ??
        ref.read(coreActionProvider.notifier).restartCore;

    Future<bool> restorePrevious() async {
      settingsNotifier.value = previous;
      try {
        await restartCore();
        return true;
      } catch (error) {
        commonPrint.event(
          'chain_proxy.rollback.failed',
          fields: {
            'error_type': error.runtimeType.toString(),
            'error': '$error',
          },
        );
        return false;
      }
    }

    setState(() => _workingName = entry.name);
    settingsNotifier.value = previous.copyWith(
      activeChainProxyName: enabled ? entry.name : null,
    );
    try {
      await restartCore();
      if (enabled) {
        final validation = await _validateActiveProxy(entry, previous.testUrl);
        if (!validation.isAvailable) {
          final restored = await restorePrevious();
          if (mounted) {
            context.showNotifier(
              restored
                  ? context.appLocalizations.chainProxyConnectivityFailed
                  : context.appLocalizations.chainProxyRollbackFailed,
            );
          }
          return;
        }
      }
      if (mounted) {
        context.showNotifier(
          enabled
              ? context.appLocalizations.chainProxyEnabled
              : context.appLocalizations.chainProxyStopped,
        );
      }
    } catch (error) {
      commonPrint.event(
        'chain_proxy.apply.failed',
        fields: {'error_type': error.runtimeType.toString(), 'error': '$error'},
      );
      final restored = await restorePrevious();
      if (mounted) {
        context.showNotifier(
          restored
              ? context.appLocalizations.chainProxyApplyFailed
              : context.appLocalizations.chainProxyRollbackFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _workingName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final settings = ref.watch(appSettingProvider);
    final entries = settings.chainProxies;
    final activeEntry = activeChainProxy(settings);
    final activeName = activeEntry?.name;
    final hasActive = activeEntry != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 18, 18),
              child: _ChainProxyHeader(
                onAdd: hasActive || _workingName != null ? null : _openForm,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: context.colorScheme.primaryContainer.withValues(
                    alpha: .28,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colorScheme.primary.withValues(alpha: .2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.chainProxySessionNotice)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: hasActive
                      ? const _RotatingProxyGear(size: 18)
                      : const Icon(Icons.shield_outlined, size: 18),
                  label: Text(
                    hasActive
                        ? '${l10n.chainProxyActive} · $activeName'
                        : l10n.chainProxyDisabled,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.link_off_rounded,
                              size: 58,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.noChainProxy,
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.noChainProxyDescription,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(26, 4, 26, 26),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final active = activeName == entry.name;
                        final working = _workingName == entry.name;
                        return _ChainProxyListItem(
                          entry: entry,
                          active: active,
                          locked: hasActive && !active,
                          working: working,
                          onToggle: working || (hasActive && !active)
                              ? null
                              : () => _setActive(entry, !active),
                          onEdit: hasActive || _workingName != null
                              ? null
                              : () => _openForm(entry),
                          onDelete: hasActive || _workingName != null
                              ? null
                              : () => _delete(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainProxyHeader extends StatelessWidget {
  const _ChainProxyHeader({required this.onAdd, required this.onClose});

  final VoidCallback? onAdd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final identity = Row(
      children: [
        const _NetworkDialogIcon(
          icon: Icons.hub_outlined,
          color: Color(0xFF1E88F7),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.chainProxy,
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                l10n.chainProxyDescription,
                style: TextStyle(color: context.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final addButton = FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.addProxy),
        );
        final closeButton = IconButton.filledTonal(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        );
        if (constraints.maxWidth < 580) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: identity),
                  closeButton,
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: addButton),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            addButton,
            const SizedBox(width: 10),
            closeButton,
          ],
        );
      },
    );
  }
}

class _ChainProxyListItem extends StatelessWidget {
  const _ChainProxyListItem({
    required this.entry,
    required this.active,
    required this.locked,
    required this.working,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ChainProxyConfig entry;
  final bool active;
  final bool locked;
  final bool working;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final leading = CircleAvatar(
      child: active
          ? const _RotatingProxyGear()
          : const Icon(Icons.hub_outlined),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          '${entry.protocol.name.toUpperCase()} · ${entry.server}:${entry.port}'
          '${locked ? '\n${l10n.chainProxyLocked}' : ''}',
        ),
      ],
    );
    final actions = <Widget>[
      TextButton(
        key: ValueKey('chain-proxy-toggle-${entry.name}'),
        onPressed: onToggle,
        child: working
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(active ? l10n.disableProxy : l10n.enableProxy),
      ),
      IconButton(
        tooltip: l10n.edit,
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: l10n.delete,
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    ];
    return Material(
      color: active
          ? context.colorScheme.primaryContainer.withValues(alpha: .34)
          : context.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leading,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ),
            );
          }
          return ListTile(
            minTileHeight: 82,
            leading: leading,
            title: details,
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          );
        },
      ),
    );
  }
}

class _ChainProxyFormDialog extends StatefulWidget {
  const _ChainProxyFormDialog({required this.entries, this.existing});

  final List<ChainProxyConfig> entries;
  final ChainProxyConfig? existing;

  @override
  State<_ChainProxyFormDialog> createState() => _ChainProxyFormDialogState();
}

class _ChainProxyFormDialogState extends State<_ChainProxyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  ChainProxyProtocol _protocol = ChainProxyProtocol.socks5;
  bool _obscurePassword = true;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _nameController.text = existing.name;
    _serverController.text = existing.server;
    _portController.text = existing.port.toString();
    _usernameController.text = existing.username;
    _passwordController.text = existing.password;
    _protocol = existing.protocol;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    final entry = ChainProxyConfig(
      name: _nameController.text.trim(),
      protocol: _protocol,
      server: _serverController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    if (hasDuplicateChainProxyName(
      widget.entries,
      entry.name,
      excludingName: widget.existing?.name,
    )) {
      setState(
        () => _validationError = context.appLocalizations.proxyNameDuplicate,
      );
      return;
    }
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      title: Text(widget.existing == null ? l10n.addProxy : l10n.editProxy),
      content: SizedBox(
        width: 650,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _ProxyFormField(
                    child: TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(labelText: l10n.name),
                      validator: (value) => value?.trim().isEmpty == true
                          ? l10n.requiredField
                          : null,
                    ),
                  ),
                  _ProxyFormField(
                    child: DropdownButtonFormField<ChainProxyProtocol>(
                      initialValue: _protocol,
                      decoration: InputDecoration(
                        labelText: l10n.protocolLabel,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ChainProxyProtocol.socks5,
                          child: Text('SOCKS5'),
                        ),
                        DropdownMenuItem(
                          value: ChainProxyProtocol.http,
                          child: Text('HTTP'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _protocol = value ?? _protocol),
                    ),
                  ),
                  _ProxyFormField(
                    child: TextFormField(
                      controller: _serverController,
                      decoration: InputDecoration(labelText: l10n.proxyServer),
                      validator: (value) => value?.trim().isEmpty == true
                          ? l10n.requiredField
                          : null,
                    ),
                  ),
                  _ProxyFormField(
                    child: TextFormField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: l10n.port),
                      validator: (value) {
                        final port = int.tryParse(value?.trim() ?? '');
                        return port == null || port < 1 || port > 65535
                            ? l10n.invalidPort
                            : null;
                      },
                    ),
                  ),
                  _ProxyFormField(
                    child: TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: l10n.username,
                        hintText: l10n.optional,
                      ),
                    ),
                  ),
                  _ProxyFormField(
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        hintText: l10n.optional,
                        suffixIcon: IconButton(
                          key: const ValueKey(
                            'chain-proxy-password-visibility',
                          ),
                          tooltip: _obscurePassword
                              ? l10n.showPassword
                              : l10n.hidePassword,
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: context.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _validationError!,
                        key: const ValueKey('chain-proxy-validation-status'),
                        style: TextStyle(color: context.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(widget.existing == null ? l10n.addProxy : l10n.save),
        ),
      ],
    );
  }
}

class _ProxyFormField extends StatelessWidget {
  const _ProxyFormField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 96;
    return SizedBox(
      width: availableWidth < 300 ? availableWidth : 300,
      child: child,
    );
  }
}

class _RotatingProxyGear extends StatefulWidget {
  const _RotatingProxyGear({this.size = 24});

  final double size;

  @override
  State<_RotatingProxyGear> createState() => _RotatingProxyGearState();
}

class _RotatingProxyGearState extends State<_RotatingProxyGear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.settings_rounded,
        size: widget.size,
        color: const Color(0xFF16B86B),
      ),
    );
  }
}

class _NetworkDialogIcon extends StatelessWidget {
  const _NetworkDialogIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: color, size: 34),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, size: 48),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.appLocalizations.retry),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label $value'));
  }
}

typedef _StreamingService = ({
  StreamingPlatform platform,
  String name,
  _Brand brand,
});

enum _Brand {
  netflix,
  disneyPlus,
  youtube,
  openAi,
  gemini,
  claude,
  tikTok,
  telegram,
  x,
  cloudflare,
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.brand, this.size = 52});

  final _Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: const Color(0xFFE3E8F2)),
      ),
      child: Padding(padding: EdgeInsets.all(size * .2), child: _brandWidget()),
    );
  }

  Widget _brandWidget() {
    if (brand == _Brand.openAi) {
      return SvgPicture.asset(
        'assets/images/openai.svg',
        colorFilter: const ColorFilter.mode(Color(0xFF10A37F), BlendMode.srcIn),
      );
    }
    if (brand == _Brand.disneyPlus) {
      return FittedBox(
        child: Text(
          'Disney+',
          style: TextStyle(
            color: const Color(0xFF113CCF),
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -1,
            fontSize: size * .32,
          ),
        ),
      );
    }
    final value = switch (brand) {
      _Brand.netflix => (SimpleIcons.netflix, SimpleIconColors.netflix),
      _Brand.youtube => (SimpleIcons.youtube, SimpleIconColors.youtube),
      _Brand.gemini => (
        SimpleIcons.googlegemini,
        SimpleIconColors.googlegemini,
      ),
      _Brand.claude => (SimpleIcons.claude, SimpleIconColors.claude),
      _Brand.tikTok => (SimpleIcons.tiktok, SimpleIconColors.tiktok),
      _Brand.telegram => (SimpleIcons.telegram, SimpleIconColors.telegram),
      _Brand.x => (SimpleIcons.x, SimpleIconColors.x),
      _Brand.cloudflare => (
        SimpleIcons.cloudflare,
        SimpleIconColors.cloudflare,
      ),
      _Brand.openAi || _Brand.disneyPlus => throw StateError('unreachable'),
    };
    return Icon(value.$1, color: value.$2, size: size * .6);
  }
}
