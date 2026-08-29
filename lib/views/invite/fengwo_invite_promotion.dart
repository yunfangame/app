import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/offline_mode_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class FengWoInvitePromotionView extends StatefulWidget {
  final XboardAuthService? authService;

  const FengWoInvitePromotionView({super.key, this.authService});

  @override
  State<FengWoInvitePromotionView> createState() =>
      _FengWoInvitePromotionViewState();
}

class _FengWoInvitePromotionViewState extends State<FengWoInvitePromotionView> {
  final _inviteCodesMeasureKey = GlobalKey();
  final _commissionScrollController = ScrollController();
  late final XboardAuthService _authService;
  XboardInviteSummary? _summary;
  List<XboardCommissionRecord> _records = const [];
  double? _desktopPanelsHeight;
  bool _loading = true;
  bool _failed = false;
  bool _generating = false;
  bool _transferring = false;
  bool _submittingWithdrawal = false;

  @override
  void dispose() {
    _commissionScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (globalState.isOfflineMode) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final session = globalState.xboardSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait<Object>([
        _authService.fetchInviteSummary(
          endpoint: session.endpoint,
          authData: session.authData,
        ),
        _authService.fetchInviteDetails(
          endpoint: session.endpoint,
          authData: session.authData,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as XboardInviteSummary;
        _records = results[1] as List<XboardCommissionRecord>;
      });
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard invite data failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateInviteCode() async {
    final session = globalState.xboardSession;
    if (session == null || _generating) return;
    setState(() => _generating = true);
    try {
      await _authService.generateInviteCode(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      await _loadData();
      if (mounted) {
        _showMessage(context.appLocalizations.inviteCodeGenerated);
      }
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _transferCommission() async {
    final session = globalState.xboardSession;
    final available = _summary?.availableCommission ?? 0;
    if (session == null || _transferring) return;
    if (available <= 0) {
      _showMessage(context.appLocalizations.availableCommissionEmpty);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.swap_horiz_rounded),
        title: Text(
          dialogContext.appLocalizations.commissionTransferConfirmTitle,
        ),
        content: Text(
          dialogContext.appLocalizations.commissionTransferConfirmMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.appLocalizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.appLocalizations.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _transferring = true);
    try {
      await _authService.transferCommission(
        endpoint: session.endpoint,
        authData: session.authData,
        amount: available,
      );
      await _loadData();
      if (mounted) {
        _showMessage(context.appLocalizations.commissionTransferred);
      }
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _showMessage(context.appLocalizations.inviteCodeCopied);
  }

  Future<void> _openWithdrawalDialog() async {
    final session = globalState.xboardSession;
    final available = _summary?.availableCommissionAmount ?? 0;
    if (session == null || _submittingWithdrawal) return;
    if (available <= 0) {
      _showMessage(context.appLocalizations.availableCommissionEmpty);
      return;
    }
    final l10n = context.appLocalizations;
    final request = await showDialog<_WithdrawalRequest>(
      context: context,
      builder: (dialogContext) => _WithdrawalDialog(
        availableAmount: available,
        methods: [
          l10n.withdrawalMethodAlipay,
          l10n.withdrawalMethodWechat,
          l10n.withdrawalMethodUsdt,
          l10n.withdrawalMethodBank,
        ],
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _submittingWithdrawal = true);
    final message = [
      '${l10n.withdrawalMethod}: ${request.method}',
      '${l10n.withdrawalAmount}: ${_money(request.amount)} CNY',
      '${l10n.withdrawalAccount}: ${request.account}',
    ].join('\n');
    try {
      await _authService.createTicket(
        endpoint: session.endpoint,
        authData: session.authData,
        subject: l10n.withdrawalRequestTitle,
        level: 2,
        message: message,
      );
      if (mounted) _showMessage(l10n.withdrawalTicketCreated);
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _submittingWithdrawal = false);
    }
  }

  String _errorMessage(Object error) {
    return error is XboardAuthException
        ? error.message
        : context.appLocalizations.requestFailed;
  }

  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colors.error : colors.inverseSurface,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (globalState.isOfflineMode) {
      return const OfflineModeFeaturePanel();
    }
    final colors = _InviteColors.of(context);
    return Material(
      color: colors.background,
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          key: const ValueKey('fengwo-invite-promotion-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 700 ? 14 : 28,
                20,
                MediaQuery.sizeOf(context).width < 700 ? 14 : 28,
                36,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1560),
                    child: _buildContent(colors),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(_InviteColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;
        return Column(
          children: [
            _buildHero(colors, isDesktop),
            const SizedBox(height: 16),
            _buildStats(colors, isDesktop),
            const SizedBox(height: 18),
            if (_loading && _summary == null)
              _buildLoadingPanel(colors)
            else if (_failed && _summary == null)
              _buildErrorPanel(colors)
            else if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 58,
                    child: KeyedSubtree(
                      key: _inviteCodesMeasureKey,
                      child: _buildInviteCodesPanel(colors, isDesktop),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 42,
                    child: SizedBox(
                      height: _desktopPanelsHeight,
                      child: _buildCommissionPanel(colors, isDesktop),
                    ),
                  ),
                ],
              )
            else ...[
              _buildInviteCodesPanel(colors, isDesktop),
              const SizedBox(height: 16),
              _buildCommissionPanel(colors, isDesktop),
            ],
          ],
        );
      },
    );
  }

  void _syncDesktopPanelsHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _inviteCodesMeasureKey.currentContext?.size?.height;
      if (height == null || height <= 0) return;
      if (_desktopPanelsHeight != null &&
          (_desktopPanelsHeight! - height).abs() < .5) {
        return;
      }
      setState(() => _desktopPanelsHeight = height);
    });
  }

  Widget _buildHero(_InviteColors colors, bool isDesktop) {
    final l10n = context.appLocalizations;
    final amount = _summary?.availableCommissionAmount ?? 0;
    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.inviteHeroTitle,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.strongText,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.inviteHeroSubtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundIcon(
              icon: Icons.people_alt_outlined,
              foreground: colors.primary,
              background: colors.primarySoft,
            ),
            const SizedBox(width: 10),
            Text(
              l10n.myInvitation,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.strongText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money(amount),
              key: const ValueKey('invite-available-commission'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                'CNY',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.strongText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Text(
          l10n.remainingCommission,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const ValueKey('invite-transfer-button'),
              onPressed: _transferring ? null : _transferCommission,
              icon: _transferring
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(l10n.commissionTransfer),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                backgroundColor: colors.primary,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('invite-withdraw-button'),
              onPressed: _submittingWithdrawal ? null : _openWithdrawalDialog,
              icon: _submittingWithdrawal
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.monetization_on_outlined),
              label: Text(l10n.commissionWithdraw),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final image = Image.asset(
      'assets/images/invite_rewards_hero.png',
      key: const ValueKey('invite-rewards-hero-image'),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    return Container(
      key: const ValueKey('invite-hero'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 64 : 22,
        isDesktop ? 32 : 26,
        isDesktop ? 34 : 22,
        isDesktop ? 26 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isDesktop ? 34 : 28),
        gradient: colors.heroGradient,
        border: Border.all(color: colors.border),
        boxShadow: [colors.shadow],
      ),
      child: isDesktop
          ? Row(
              children: [
                Expanded(flex: 47, child: textContent),
                const SizedBox(width: 20),
                Expanded(
                  flex: 53,
                  child: SizedBox(
                    height: 370,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: image,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                textContent,
                const SizedBox(height: 8),
                SizedBox(height: 230, child: image),
              ],
            ),
    );
  }

  Widget _buildStats(_InviteColors colors, bool isDesktop) {
    final l10n = context.appLocalizations;
    final summary = _summary;
    final stats = [
      _InviteStat(
        icon: Icons.group_outlined,
        color: colors.purple,
        label: l10n.registeredUsers,
        value: l10n.peopleCount(summary?.registeredUsers ?? 0),
      ),
      _InviteStat(
        icon: Icons.percent_rounded,
        color: colors.green,
        label: l10n.commissionRate,
        value: '${summary?.commissionRate ?? 0}%',
      ),
      _InviteStat(
        icon: Icons.business_center_outlined,
        color: colors.orange,
        label: l10n.pendingCommission,
        value: '¥${_money(summary?.pendingCommissionAmount ?? 0)}',
      ),
      _InviteStat(
        icon: Icons.account_balance_wallet_outlined,
        color: colors.primary,
        label: l10n.totalCommission,
        value: '¥${_money(summary?.confirmedCommissionAmount ?? 0)}',
      ),
    ];
    return Container(
      key: const ValueKey('invite-stats'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 28 : 14,
        vertical: isDesktop ? 18 : 14,
      ),
      decoration: _panelDecoration(colors, radius: 28),
      child: isDesktop
          ? Row(
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  Expanded(child: _buildStatItem(stats[index], colors)),
                  if (index < stats.length - 1)
                    Container(width: 1, height: 46, color: colors.border),
                ],
              ],
            )
          : Wrap(
              runSpacing: 12,
              children: stats
                  .map(
                    (stat) => SizedBox(
                      width: (MediaQuery.sizeOf(context).width - 58) / 2,
                      child: _buildStatItem(stat, colors),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _buildStatItem(_InviteStat stat, _InviteColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _RoundIcon(
            icon: stat.icon,
            foreground: stat.color,
            background: stat.color.withValues(alpha: .12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.strongText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCodesPanel(_InviteColors colors, bool isDesktop) {
    final l10n = context.appLocalizations;
    final codes = _summary?.codes ?? const <XboardInviteCode>[];
    return Container(
      key: const ValueKey('invite-codes-panel'),
      padding: EdgeInsets.all(isDesktop ? 24 : 18),
      decoration: _panelDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.card_giftcard_rounded,
            title: l10n.inviteCodeManagement,
            colors: colors,
            trailing: FilledButton.icon(
              key: const ValueKey('generate-invite-code-button'),
              onPressed: _generating ? null : _generateInviteCode,
              icon: _generating
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(l10n.generateInviteCode),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.inviteCodeDescription,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _TableHeader(
            columns: [l10n.inviteCode, l10n.createdAt, l10n.actions],
            colors: colors,
            flexes: const [3, 4, 4],
          ),
          if (codes.isEmpty)
            _EmptyState(
              icon: Icons.mark_email_unread_outlined,
              label: l10n.noInviteCodes,
              colors: colors,
            )
          else
            for (final code in codes)
              _InviteCodeRow(
                code: code,
                colors: colors,
                onCopy: () => _copyInviteCode(code.code),
              ),
        ],
      ),
    );
  }

  Widget _buildCommissionPanel(_InviteColors colors, bool isDesktop) {
    final l10n = context.appLocalizations;
    if (isDesktop) _syncDesktopPanelsHeight();
    return Container(
      key: const ValueKey('invite-commission-panel'),
      padding: EdgeInsets.all(isDesktop ? 24 : 18),
      decoration: _panelDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.monetization_on_outlined,
            title: l10n.commissionPayoutRecords,
            colors: colors,
          ),
          const SizedBox(height: 18),
          _TableHeader(
            columns: [l10n.payoutTime, l10n.commission],
            colors: colors,
            flexes: const [3, 2],
          ),
          if (_records.isEmpty && isDesktop && _desktopPanelsHeight != null)
            Expanded(
              child: _EmptyState(
                icon: Icons.near_me_outlined,
                label: l10n.noCommissionRecords,
                colors: colors,
                minHeight: 0,
              ),
            )
          else if (_records.isEmpty)
            _EmptyState(
              icon: Icons.near_me_outlined,
              label: l10n.noCommissionRecords,
              colors: colors,
              minHeight: 192,
            )
          else if (isDesktop && _desktopPanelsHeight != null)
            Expanded(
              child: Scrollbar(
                controller: _commissionScrollController,
                child: ListView.builder(
                  key: const ValueKey('invite-commission-records-scroll'),
                  controller: _commissionScrollController,
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _records.length,
                  itemBuilder: (context, index) =>
                      _CommissionRow(record: _records[index], colors: colors),
                ),
              ),
            )
          else
            for (final record in _records)
              _CommissionRow(record: record, colors: colors),
        ],
      ),
    );
  }

  Widget _buildLoadingPanel(_InviteColors colors) {
    return Container(
      height: 280,
      decoration: _panelDecoration(colors),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: colors.primary),
    );
  }

  Widget _buildErrorPanel(_InviteColors colors) {
    return Container(
      height: 260,
      decoration: _panelDecoration(colors),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: colors.mutedText),
          const SizedBox(height: 12),
          Text(
            context.appLocalizations.inviteLoadFailed,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.strongText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.appLocalizations.retry),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(_InviteColors colors, {double radius = 30}) {
    return BoxDecoration(
      color: colors.panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: colors.border),
      boxShadow: [colors.shadow],
    );
  }

  String _money(double value) {
    return NumberFormat('#,##0.00').format(value);
  }
}

class _WithdrawalDialog extends StatefulWidget {
  final double availableAmount;
  final List<String> methods;

  const _WithdrawalDialog({
    required this.availableAmount,
    required this.methods,
  });

  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _accountController = TextEditingController();
  String? _method;

  @override
  void dispose() {
    _amountController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  double? _amountValue() {
    return double.tryParse(_amountController.text.trim().replaceAll(',', '.'));
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true || _method == null) return;
    Navigator.pop(
      context,
      _WithdrawalRequest(
        method: _method!,
        amount: _amountValue()!,
        account: _accountController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      icon: const Icon(Icons.monetization_on_outlined),
      title: Text(l10n.withdrawalRequestTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.withdrawalTicketDescription,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: const ValueKey('withdrawal-method-field'),
                  initialValue: _method,
                  decoration: InputDecoration(
                    labelText: l10n.withdrawalMethod,
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  items: widget.methods
                      .map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _method = value),
                  validator: (value) =>
                      value == null ? l10n.selectWithdrawalMethod : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('withdrawal-amount-field'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.withdrawalAmount,
                    prefixText: '¥ ',
                    suffixText:
                        '/ ¥${NumberFormat('#,##0.00').format(widget.availableAmount)}',
                  ),
                  validator: (_) {
                    final amount = _amountValue();
                    if (amount == null || amount <= 0) {
                      return l10n.withdrawalAmountInvalid;
                    }
                    if (amount > widget.availableAmount) {
                      return l10n.withdrawalAmountExceeds;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('withdrawal-account-field'),
                  controller: _accountController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.withdrawalAccount,
                    hintText: l10n.enterWithdrawalAccount,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.enterWithdrawalAccount
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('submit-withdrawal-ticket-button'),
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: Text(l10n.submitWithdrawalTicket),
        ),
      ],
    );
  }
}

class _WithdrawalRequest {
  final String method;
  final double amount;
  final String account;

  const _WithdrawalRequest({
    required this.method,
    required this.amount,
    required this.account,
  });
}

class _InviteCodeRow extends StatelessWidget {
  final XboardInviteCode code;
  final _InviteColors colors;
  final VoidCallback onCopy;

  const _InviteCodeRow({
    required this.code,
    required this.colors,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd HH:mm').format(code.createdAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              code.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.strongText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.mutedText),
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('copy-invite-${code.code}'),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(context.appLocalizations.copyInviteCode),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  final XboardCommissionRecord record;
  final _InviteColors colors;

  const _CommissionRow({required this.record, required this.colors});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy/MM/dd HH:mm').format(record.createdAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(date, style: TextStyle(color: colors.mutedText)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '¥${NumberFormat('#,##0.00').format(record.amount)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final List<String> columns;
  final List<int> flexes;
  final _InviteColors colors;

  const _TableHeader({
    required this.columns,
    required this.flexes,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colors.tableHeader,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var index = 0; index < columns.length; index++)
            Expanded(
              flex: flexes[index],
              child: Text(
                columns[index],
                textAlign: columns.length == 2 && index == 1
                    ? TextAlign.end
                    : TextAlign.start,
                style: TextStyle(
                  color: colors.strongText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final _InviteColors colors;
  final Widget? trailing;

  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.colors,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIcon(
          icon: icon,
          foreground: colors.primary,
          background: colors.primarySoft,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.strongText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final _InviteColors colors;
  final double minHeight;

  const _EmptyState({
    required this.icon,
    required this.label,
    required this.colors,
    this.minHeight = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: minHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.mutedText.withValues(alpha: .4)),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final Color foreground;
  final Color background;

  const _RoundIcon({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: foreground, size: 25),
    );
  }
}

class _InviteStat {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _InviteStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
}

class _InviteColors {
  final Color background;
  final Color panel;
  final Color tableHeader;
  final Color border;
  final Color strongText;
  final Color mutedText;
  final Color primary;
  final Color primarySoft;
  final Color purple;
  final Color green;
  final Color orange;
  final LinearGradient heroGradient;
  final BoxShadow shadow;

  const _InviteColors({
    required this.background,
    required this.panel,
    required this.tableHeader,
    required this.border,
    required this.strongText,
    required this.mutedText,
    required this.primary,
    required this.primarySoft,
    required this.purple,
    required this.green,
    required this.orange,
    required this.heroGradient,
    required this.shadow,
  });

  factory _InviteColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = scheme.primary;
    final panel = isDark
        ? Color.alphaBlend(primary.withValues(alpha: .045), scheme.surface)
        : Color.alphaBlend(primary.withValues(alpha: .025), scheme.surface);
    return _InviteColors(
      background: isDark
          ? Color.alphaBlend(primary.withValues(alpha: .04), scheme.surface)
          : const Color(0xFFF4F8FF),
      panel: panel,
      tableHeader: Color.alphaBlend(
        primary.withValues(alpha: isDark ? .12 : .055),
        panel,
      ),
      border: scheme.outlineVariant.withValues(alpha: isDark ? .36 : .6),
      strongText: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      primary: primary,
      primarySoft: primary.withValues(alpha: .11),
      purple: const Color(0xFF7358F4),
      green: const Color(0xFF17C995),
      orange: const Color(0xFFFF9518),
      heroGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                Color.alphaBlend(
                  primary.withValues(alpha: .16),
                  scheme.surface,
                ),
                Color.alphaBlend(
                  const Color(0xFF6956D9).withValues(alpha: .12),
                  scheme.surface,
                ),
              ]
            : const [Color(0xFFF8FBFF), Color(0xFFEAF1FF)],
      ),
      shadow: BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: .18)
            : const Color(0xFF6889BD).withValues(alpha: .13),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    );
  }
}
