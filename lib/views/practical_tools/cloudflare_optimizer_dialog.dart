import 'package:fl_clash/common/cloudflare_optimizer.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloudflareOptimizerDialog extends ConsumerStatefulWidget {
  const CloudflareOptimizerDialog({super.key, this.optimizer});

  final CloudflareOptimizer? optimizer;

  @override
  ConsumerState<CloudflareOptimizerDialog> createState() =>
      _CloudflareOptimizerDialogState();
}

class _CloudflareOptimizerDialogState
    extends ConsumerState<CloudflareOptimizerDialog> {
  late final CloudflareOptimizer _optimizer;
  CloudflareOptimizeConfig _config = const CloudflareOptimizeConfig();
  CloudflareOptimizeProgress _progress = const CloudflareOptimizeProgress(
    completed: 0,
    total: 1,
    stage: CloudflareOptimizeStage.loading,
  );
  List<CloudflareOptimizeResult> _results = const [];
  Duration _elapsed = Duration.zero;
  bool _running = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _optimizer = widget.optimizer ?? CloudflareOptimizer();
    Future.microtask(_run);
  }

  Future<void> _run() async {
    if (_running) return;
    final stopwatch = Stopwatch()..start();
    setState(() {
      _running = true;
      _results = const [];
      _progress = const CloudflareOptimizeProgress(
        completed: 0,
        total: 1,
        stage: CloudflareOptimizeStage.loading,
      );
    });
    try {
      final config = await _optimizer.loadConfig();
      final results = await _optimizer.optimize(
        config,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _config = config;
        _results = results;
        _elapsed = stopwatch.elapsed;
      });
    } finally {
      stopwatch.stop();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _showMissingTarget() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(context.appLocalizations.cfTargetMissingTitle),
        content: Text(context.appLocalizations.cfTargetMissingMessage),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.appLocalizations.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    if (_applying || _running || _results.isEmpty) return;
    if (!_config.canApply) {
      await _showMissingTarget();
      return;
    }
    setState(() => _applying = true);
    final previous = ref.read(patchClashConfigProvider);
    try {
      final mappings = await _optimizer.validateTargets(_config, _results);
      if (!mounted) return;
      if (mappings.length != _config.targets.length) {
        context.showNotifier(context.appLocalizations.cfTargetValidationFailed);
        return;
      }
      ref
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.copyWith(hosts: {...state.hosts, ...mappings}),
          );
      try {
        await ref.read(coreActionProvider.notifier).restartCore();
      } catch (_) {
        ref.read(patchClashConfigProvider.notifier).update((_) => previous);
        rethrow;
      }
      if (!mounted) return;
      context.showNotifier(context.appLocalizations.cfApplySuccess);
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      commonPrint.log(
        'apply Cloudflare preferred IPs failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        context.showNotifier(context.appLocalizations.cfApplyFailed);
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _status(BuildContext context) {
    if (!_running && _results.isEmpty) {
      return context.appLocalizations.optimizationFailed;
    }
    return switch (_progress.stage) {
      CloudflareOptimizeStage.loading =>
        context.appLocalizations.optimizationPreparing,
      CloudflareOptimizeStage.latency =>
        context.appLocalizations.optimizationLatency,
      CloudflareOptimizeStage.download =>
        context.appLocalizations.optimizationDownload,
      CloudflareOptimizeStage.completed =>
        context.appLocalizations.optimizationComplete,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 840),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8A1F).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.cloud_rounded,
                      color: Color(0xFFFF8A1F),
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.appLocalizations.cloudflarePreferredIp,
                          style: context.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          context
                              .appLocalizations
                              .cloudflarePreferredIpDescription,
                          style: context.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _applying
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusPanel(
                      status: _applying
                          ? context.appLocalizations.validatingTargets
                          : _status(context),
                      subtitle:
                          '${context.appLocalizations.candidateCount} '
                          '${_config.candidateCount}  ·  '
                          '${context.appLocalizations.availableCount} '
                          '${_results.length}  ·  '
                          '${context.appLocalizations.keptCount} '
                          '${_results.length}  ·  '
                          '${_elapsed.inMilliseconds / 1000}s',
                      running: _running || _applying,
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: _running ? _progress.value : 1,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: colors.primaryContainer,
                    ),
                    const SizedBox(height: 18),
                    if (_results.isNotEmpty) ...[
                      _SummaryGrid(results: _results),
                      const SizedBox(height: 18),
                      _ResultTable(results: _results),
                    ] else if (!_running)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 54),
                        child: Column(
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 54,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              context.appLocalizations.optimizationFailed,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _running || _applying ? null : _run,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.appLocalizations.rerunOptimization),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _running || _applying || _results.isEmpty
                          ? null
                          : _apply,
                      icon: _applying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline_rounded),
                      label: Text(context.appLocalizations.applyPreferredIps),
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
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.subtitle,
    required this.running,
  });

  final String status;
  final String subtitle;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: running
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.results});

  final List<CloudflareOptimizeResult> results;

  @override
  Widget build(BuildContext context) {
    final fastest = results.reduce(
      (left, right) =>
          left.downloadBytesPerSecond >= right.downloadBytesPerSecond
          ? left
          : right,
    );
    final lowest = results.reduce(
      (left, right) => left.latency <= right.latency ? left : right,
    );
    final highest = results.reduce(
      (left, right) => left.latency >= right.latency ? left : right,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _SummaryCard(
            label: context.appLocalizations.fastestDownload,
            value: _formatSpeed(fastest.downloadBytesPerSecond),
            detail: fastest.ip,
          ),
          _SummaryCard(
            label: context.appLocalizations.lowestLatency,
            value: '${lowest.latency.inMilliseconds} ms',
            detail: lowest.ip,
          ),
          _SummaryCard(
            label: context.appLocalizations.highestLatency,
            value: '${highest.latency.inMilliseconds} ms',
            detail: highest.ip,
          ),
        ];
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(detail, style: context.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.results});

  final List<CloudflareOptimizeResult> results;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
          columns: [
            DataColumn(label: Text(context.appLocalizations.ipAddress)),
            DataColumn(label: Text(context.appLocalizations.currentNodeDelay)),
            DataColumn(label: Text(context.appLocalizations.downloadSpeed)),
            DataColumn(label: Text(context.appLocalizations.region)),
          ],
          rows: [
            for (final result in results)
              DataRow(
                cells: [
                  DataCell(Text(result.ip)),
                  DataCell(Text('${result.latency.inMilliseconds} ms')),
                  DataCell(Text(_formatSpeed(result.downloadBytesPerSecond))),
                  DataCell(Text(result.region)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _formatSpeed(double bytesPerSecond) {
  return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
}
