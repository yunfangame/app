import 'package:fl_clash/common/common.dart';
import 'package:flutter/material.dart';

class ApiHealthControl extends StatefulWidget {
  const ApiHealthControl({
    super.key,
    this.service,
    this.autoCheck = true,
    this.foregroundColor,
    this.buttonBackgroundColor,
    this.buttonBorderColor,
  });

  final ApiHealthService? service;
  final bool autoCheck;
  final Color? foregroundColor;
  final Color? buttonBackgroundColor;
  final Color? buttonBorderColor;

  @override
  State<ApiHealthControl> createState() => _ApiHealthControlState();
}

class _ApiHealthControlState extends State<ApiHealthControl> {
  late final ApiHealthService _service;
  ApiHealthSnapshot? _snapshot;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ApiHealthService();
    if (widget.autoCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final snapshot = await _service.check();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _checking = false;
    });
  }

  Color get _statusColor {
    if (_checking) return const Color(0xFF6F7FFF);
    return switch (_snapshot?.level) {
      ApiHealthLevel.healthy => const Color(0xFF2BD984),
      ApiHealthLevel.warning => const Color(0xFFFFB020),
      ApiHealthLevel.critical => const Color(0xFFFF4D5E),
      ApiHealthLevel.unavailable || null => const Color(0xFF9BA6B5),
    };
  }

  String _tooltip(BuildContext context) {
    if (_checking) return context.appLocalizations.checkingApiStatus;
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.total == 0) {
      return context.appLocalizations.apiStatusUnavailable;
    }
    return '${context.appLocalizations.apiStatus}: ${snapshot.percentage}%';
  }

  Future<void> _showDetails() async {
    final result = await showDialog<_ApiHealthDialogResult>(
      context: context,
      builder: (_) =>
          _ApiHealthDialog(service: _service, initialSnapshot: _snapshot),
    );
    if (!mounted || result == null) return;
    setState(() => _snapshot = result.snapshot);
    if (result.applied) {
      context.showNotifier(context.appLocalizations.apiEndpointApplied);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip(context),
      child: _ApiHealthStatusButton(
        key: const Key('api-health-status-button'),
        color: _statusColor,
        foregroundColor: widget.foregroundColor ?? Colors.white,
        backgroundColor:
            widget.buttonBackgroundColor ??
            Colors.white.withValues(alpha: 0.14),
        borderColor:
            widget.buttonBorderColor ??
            const Color(0xFF7387FF).withValues(alpha: 0.3),
        pulse: !_checking && (_snapshot?.shouldPulse ?? false),
        checking: _checking,
        onPressed: _showDetails,
      ),
    );
  }
}

class _ApiHealthDialogResult {
  const _ApiHealthDialogResult({required this.snapshot, required this.applied});

  final ApiHealthSnapshot? snapshot;
  final bool applied;
}

class _ApiHealthDialog extends StatefulWidget {
  const _ApiHealthDialog({
    required this.service,
    required this.initialSnapshot,
  });

  final ApiHealthService service;
  final ApiHealthSnapshot? initialSnapshot;

  @override
  State<_ApiHealthDialog> createState() => _ApiHealthDialogState();
}

class _ApiHealthDialogState extends State<_ApiHealthDialog> {
  ApiHealthSnapshot? _snapshot;
  bool _checkingAll = false;
  bool _loadingSelection = true;
  bool _savingSelection = false;
  Uri? _selectedEndpoint;
  final _testingIndexes = <int>{};

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    if (_snapshot == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncSelection());
    }
  }

  Future<void> _syncSelection() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final currentSelection = _selectedEndpoint;
    final currentStillReachable =
        currentSelection != null &&
        snapshot.endpoints.any(
          (endpoint) =>
              endpoint.reachable &&
              isSameApiEndpoint(endpoint.endpoint, currentSelection),
        );
    final selected = currentStillReachable
        ? currentSelection
        : (await widget.service.orderedReachableEndpoints(
            snapshot,
          )).firstOrNull?.endpoint;
    if (!mounted) return;
    setState(() {
      _selectedEndpoint = selected;
      _loadingSelection = false;
    });
  }

  Future<void> _refreshAll() async {
    if (_checkingAll) return;
    setState(() => _checkingAll = true);
    try {
      final snapshot = await widget.service.check();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      await _syncSelection();
    } finally {
      if (mounted) setState(() => _checkingAll = false);
    }
  }

  Future<void> _testEndpoint(int index) async {
    final snapshot = _snapshot;
    if (snapshot == null || _testingIndexes.contains(index)) return;
    setState(() => _testingIndexes.add(index));
    try {
      final result = await widget.service.probeEndpoint(
        snapshot.endpoints[index].endpoint,
      );
      if (!mounted) return;
      final endpoints = List<ApiEndpointHealth>.from(snapshot.endpoints)
        ..[index] = result;
      setState(() {
        _snapshot = ApiHealthSnapshot(
          endpoints: List.unmodifiable(endpoints),
          checkedAt: DateTime.now(),
        );
      });
      await _syncSelection();
    } finally {
      if (mounted) setState(() => _testingIndexes.remove(index));
    }
  }

  int get _currentIndex {
    final endpoints = _snapshot?.endpoints ?? const <ApiEndpointHealth>[];
    final selected = _selectedEndpoint;
    final index = selected == null
        ? endpoints.indexWhere((endpoint) => endpoint.reachable)
        : endpoints.indexWhere(
            (endpoint) => isSameApiEndpoint(endpoint.endpoint, selected),
          );
    return index < 0 ? 0 : index;
  }

  Future<void> _confirmSelection() async {
    if (_savingSelection || _loadingSelection) return;
    final selected = _selectedEndpoint;
    if (selected == null) {
      Navigator.pop(
        context,
        _ApiHealthDialogResult(snapshot: _snapshot, applied: false),
      );
      return;
    }
    setState(() => _savingSelection = true);
    try {
      await widget.service.savePreferredEndpoint(selected);
      if (!mounted) return;
      Navigator.pop(
        context,
        _ApiHealthDialogResult(snapshot: _snapshot, applied: true),
      );
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _savingSelection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final l10n = context.appLocalizations;
    final snapshot = _snapshot;
    return Dialog(
      key: const Key('api-health-dialog'),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: (MediaQuery.sizeOf(context).height - 40).clamp(520, 760),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18B981).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.dns_rounded,
                      color: Color(0xFF00A56E),
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.loginEndpoint,
                          style: context.textTheme.titleMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          l10n.serviceStatus,
                          style: context.textTheme.headlineMedium?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    key: const Key('api-health-dialog-close'),
                    onPressed: () => Navigator.pop(
                      context,
                      _ApiHealthDialogResult(
                        snapshot: _snapshot,
                        applied: false,
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _ApiHealthSummaryCard(
                      label: l10n.availableEndpoints,
                      value: snapshot == null
                          ? '--/--'
                          : '${snapshot.reachableCount}/${snapshot.total}',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ApiHealthSummaryCard(
                      label: l10n.currentEndpoint,
                      value: snapshot == null || snapshot.total == 0
                          ? '--'
                          : l10n.loginEndpointLabel(_currentIndex + 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    key: const Key('api-health-refresh-config-button'),
                    onPressed: _checkingAll ? null : _refreshAll,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l10n.refreshConfiguration),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('api-health-test-all-button'),
                    onPressed: _checkingAll ? null : _refreshAll,
                    icon: const Icon(Icons.speed_rounded),
                    label: Text(l10n.testAllEndpoints),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: snapshot == null || snapshot.total == 0
                    ? Center(
                        child: _checkingAll
                            ? const CircularProgressIndicator()
                            : Text(l10n.apiStatusUnavailable),
                      )
                    : ListView.separated(
                        key: const Key('api-health-endpoints-list'),
                        itemCount: snapshot.endpoints.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final endpoint = snapshot.endpoints[index];
                          final selected =
                              _selectedEndpoint != null &&
                              isSameApiEndpoint(
                                endpoint.endpoint,
                                _selectedEndpoint!,
                              );
                          final testing = _testingIndexes.contains(index);
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey('api-health-endpoint-$index'),
                              onTap: endpoint.reachable && !_savingSelection
                                  ? () => setState(
                                      () =>
                                          _selectedEndpoint = endpoint.endpoint,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? colors.primaryContainer.withValues(
                                          alpha: .38,
                                        )
                                      : colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selected
                                        ? colors.primary.withValues(alpha: .72)
                                        : colors.outlineVariant,
                                    width: selected ? 1.6 : 1,
                                  ),
                                ),
                                child: _ApiHealthEndpointRow(
                                  endpoint: endpoint,
                                  index: index,
                                  selected: selected,
                                  testing: testing,
                                  onTest: () => _testEndpoint(index),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('api-health-confirm-button'),
                onPressed:
                    _loadingSelection ||
                        _savingSelection ||
                        _selectedEndpoint == null
                    ? null
                    : _confirmSelection,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _savingSelection
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(l10n.confirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiHealthEndpointRow extends StatelessWidget {
  const _ApiHealthEndpointRow({
    required this.endpoint,
    required this.index,
    required this.selected,
    required this.testing,
    required this.onTest,
  });

  final ApiEndpointHealth endpoint;
  final int index;
  final bool selected;
  final bool testing;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final l10n = context.appLocalizations;
    final statusIcon = Icon(
      endpoint.reachable
          ? Icons.check_circle_outline_rounded
          : Icons.cancel_outlined,
      color: endpoint.reachable ? const Color(0xFF00A56E) : colors.error,
    );
    final endpointLabel = Text(
      l10n.loginEndpointLabel(index + 1),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
    final selectionIcon = selected
        ? Icon(Icons.check_rounded, color: colors.onSurface)
        : const SizedBox.shrink();
    final latency = Text(
      endpoint.reachable
          ? '${endpoint.latency.inMilliseconds} ms'
          : l10n.unreachable,
      style: TextStyle(
        color: endpoint.reachable ? const Color(0xFF00A56E) : colors.error,
        fontWeight: FontWeight.w700,
      ),
    );
    final testButton = OutlinedButton.icon(
      key: ValueKey('api-health-test-$index'),
      onPressed: testing ? null : onTest,
      icon: testing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.speed_rounded),
      label: Text(l10n.testEndpoint),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  statusIcon,
                  const SizedBox(width: 12),
                  Expanded(child: endpointLabel),
                  selectionIcon,
                  const SizedBox(width: 8),
                  latency,
                ],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: testButton),
            ],
          );
        }
        return Row(
          children: [
            statusIcon,
            const SizedBox(width: 12),
            Expanded(child: endpointLabel),
            selectionIcon,
            const SizedBox(width: 10),
            latency,
            const SizedBox(width: 12),
            testButton,
          ],
        );
      },
    );
  }
}

class _ApiHealthSummaryCard extends StatelessWidget {
  const _ApiHealthSummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.titleSmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiHealthStatusButton extends StatefulWidget {
  const _ApiHealthStatusButton({
    super.key,
    required this.color,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.pulse,
    required this.checking,
    required this.onPressed,
  });

  final Color color;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final bool pulse;
  final bool checking;
  final VoidCallback onPressed;

  @override
  State<_ApiHealthStatusButton> createState() => _ApiHealthStatusButtonState();
}

class _ApiHealthStatusButtonState extends State<_ApiHealthStatusButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ApiHealthStatusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.pulse) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.dns_outlined, size: 29),
          Positioned(
            right: -3,
            bottom: -3,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) => Transform.scale(
                scale: widget.pulse ? 0.78 + _pulseController.value * 0.32 : 1,
                child: Opacity(
                  opacity: widget.pulse
                      ? 0.45 + _pulseController.value * 0.55
                      : 1,
                  child: child,
                ),
              ),
              child: Container(
                key: const Key('api-health-status-dot'),
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45),
                      blurRadius: widget.pulse ? 8 : 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      color: widget.foregroundColor,
      style: IconButton.styleFrom(
        backgroundColor: widget.backgroundColor,
        fixedSize: const Size(58, 58),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: widget.borderColor),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
