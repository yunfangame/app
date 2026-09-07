import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/fengwo_account_avatar.dart';
import 'package:fl_clash/widgets/fengwo_logout_button.dart';
import 'package:fl_clash/widgets/offline_mode_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FengWoPersonalCenterView extends ConsumerStatefulWidget {
  final XboardAuthService? authService;

  const FengWoPersonalCenterView({super.key, this.authService});

  @override
  ConsumerState<FengWoPersonalCenterView> createState() =>
      _FengWoPersonalCenterViewState();
}

class _FengWoPersonalCenterViewState
    extends ConsumerState<FengWoPersonalCenterView> {
  static const _wideLayoutBreakpoint = 1040.0;
  static const _loginIpWideRowBreakpoint = 700.0;
  static const _loginIpWideVisibleRecordLimit = 4;
  static const _loginIpCompactVisibleRecordLimit = 3;
  static const _loginIpWideViewportHeight = 320.0;
  static const _loginIpCompactViewportHeight = 360.0;

  final _passwordFormKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loginIpScrollController = ScrollController();
  late final XboardAuthService _authService;

  XboardUserInfo? _userInfo;
  XboardLoginIpList? _loginIpList;
  bool _loading = true;
  bool _failed = false;
  bool _loadingLoginIps = false;
  bool _loginIpListFailed = false;
  final Set<String> _updatingLoginIps = {};
  bool _changingPassword = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserInfo();
      _loadLoginIps();
    });
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _loginIpScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    if (globalState.isOfflineMode) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final session = globalState.xboardSession;
    if (session == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final userInfo = await _authService.fetchUserInfo(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!mounted) return;
      setState(() => _userInfo = userInfo);
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard user info failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLoginIps() async {
    final session = globalState.xboardSession;
    if (session == null) {
      if (mounted) {
        setState(() {
          _loginIpList = null;
          _loadingLoginIps = false;
          _loginIpListFailed = false;
        });
      }
      return;
    }
    setState(() {
      _loadingLoginIps = true;
      _loginIpListFailed = false;
    });
    try {
      final loginIps = await _authService.fetchLoginIps(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!mounted || globalState.xboardSession?.authData != session.authData) {
        return;
      }
      setState(() => _loginIpList = loginIps);
    } catch (error, stackTrace) {
      commonPrint.log(
        'load login IP records failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (!mounted) return;
      setState(() => _loginIpListFailed = true);
    } finally {
      if (mounted) setState(() => _loadingLoginIps = false);
    }
  }

  Future<void> _refreshPage() async {
    await Future.wait([_loadUserInfo(), _loadLoginIps()]);
  }

  Future<void> _blockLoginIp(XboardLoginIpRecord record) async {
    if (record.isBlocked || _updatingLoginIps.contains(record.ip)) return;
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.gpp_bad_outlined),
        title: Text(context.appLocalizations.blockLoginIpTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                record.ip,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.appLocalizations.blockLoginIpWarning,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('block-login-ip-reason-field'),
                maxLength: 255,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.appLocalizations.blockReasonOptional,
                  hintText: context.appLocalizations.blockReasonHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => reason = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('confirm-block-login-ip-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.appLocalizations.confirmBlockLoginIp),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = globalState.xboardSession;
    if (session == null) return;
    setState(() => _updatingLoginIps.add(record.ip));
    try {
      await _authService.blockLoginIp(
        endpoint: session.endpoint,
        authData: session.authData,
        ip: record.ip,
        reason: reason.trim().isEmpty ? null : reason.trim(),
      );
      if (!mounted) return;
      _showMessage(context.appLocalizations.loginIpBlocked);
      await _loadLoginIps();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _updatingLoginIps.remove(record.ip));
    }
  }

  Future<void> _unblockLoginIp(XboardLoginIpRecord record) async {
    if (!record.isBlocked || _updatingLoginIps.contains(record.ip)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded),
        title: Text(context.appLocalizations.unblockLoginIpTitle),
        content: Text(
          context.appLocalizations.unblockLoginIpMessage(record.ip),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('confirm-unblock-login-ip-button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.appLocalizations.confirmUnblockLoginIp),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = globalState.xboardSession;
    if (session == null) return;
    setState(() => _updatingLoginIps.add(record.ip));
    try {
      await _authService.unblockLoginIp(
        endpoint: session.endpoint,
        authData: session.authData,
        ip: record.ip,
      );
      if (!mounted) return;
      _showMessage(context.appLocalizations.loginIpUnblocked);
      await _loadLoginIps();
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _updatingLoginIps.remove(record.ip));
    }
  }

  Future<void> _changePassword() async {
    if (_changingPassword ||
        _passwordFormKey.currentState?.validate() != true) {
      return;
    }
    final session = globalState.xboardSession;
    if (session == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _changingPassword = true);
    try {
      await _authService.changePassword(
        endpoint: session.endpoint,
        authData: session.authData,
        oldPassword: _oldPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _passwordFormKey.currentState?.reset();
      _showMessage(context.appLocalizations.passwordChanged);
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    context.showNotifier(message);
  }

  String _errorMessage(Object error) {
    if (error is XboardAuthException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return context.appLocalizations.requestFailed;
  }

  @override
  Widget build(BuildContext context) {
    if (globalState.isOfflineMode) {
      return const OfflineModeFeaturePanel();
    }
    final colors = _AccountColors.of(context);
    final mobileLayout = ref.watch(isMobileViewProvider);
    return Material(
      color: colors.background,
      child: RefreshIndicator(
        onRefresh: _refreshPage,
        child: CustomScrollView(
          key: const ValueKey('fengwo-personal-center-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(colors)),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed || _userInfo == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _AccountStatus(
                  label: context.appLocalizations.userInfoFailed,
                  onRetry: _loadUserInfo,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  mobileLayout ? 16 : 24,
                  22,
                  mobileLayout ? 16 : 24,
                  32,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1480),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wideLayout =
                              !mobileLayout &&
                              constraints.maxWidth >= _wideLayoutBreakpoint;
                          if (!wideLayout) {
                            return Column(
                              children: [
                                _buildProfileCard(colors),
                                const SizedBox(height: 16),
                                _buildWalletCard(colors),
                                const SizedBox(height: 16),
                                _buildPasswordCard(colors),
                                const SizedBox(height: 16),
                                _buildLoginIpCard(colors),
                                if (mobileLayout) ...[
                                  const SizedBox(height: 16),
                                  const FengWoLogoutButton(),
                                ],
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildProfileCard(colors)),
                                  const SizedBox(width: 18),
                                  Expanded(child: _buildWalletCard(colors)),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _buildPasswordCard(colors),
                              const SizedBox(height: 18),
                              _buildLoginIpCard(colors),
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
      ),
    );
  }

  Widget _buildHeader(_AccountColors colors) {
    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.fromLTRB(28, 30, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primarySoft,
            colors.background,
            colors.surfaceSoft.withValues(alpha: 0.45),
          ],
        ),
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -22,
            end: 12,
            child: IgnorePointer(
              child: Icon(
                Icons.account_circle_outlined,
                size: 158,
                color: colors.primary.withValues(alpha: 0.075),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      context.appLocalizations.personalCenter,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.verified_user_outlined,
                    color: colors.primary,
                    size: 30,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.appLocalizations.accountCenterSubtitle,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(_AccountColors colors) {
    final session = globalState.xboardSession;
    final info = _userInfo!;
    final subscription = session?.subscription;
    final planName = subscription?.plan?.name?.trim();
    final expiresAt = info.expiresAt ?? subscription?.expiresAt;
    return _AccountCard(
      key: const ValueKey('account-profile-card'),
      colors: colors,
      minHeight: 300,
      child: Stack(
        children: [
          Positioned(
            left: -70,
            right: -70,
            bottom: -118,
            height: 210,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(
                  Radius.elliptical(360, 90),
                ),
                gradient: LinearGradient(
                  colors: [
                    colors.secondary.withValues(alpha: 0.18),
                    colors.primary.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 440;
              final avatar = FengWoAccountAvatar(size: compact ? 124 : 162);
              final details = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          info.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: compact ? 18 : 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _VipBadge(colors: colors),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: colors.gold,
                        size: 26,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          planName == null || planName.isEmpty
                              ? context.appLocalizations.noActivePlan
                              : planName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.gold,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    expiresAt == null
                        ? context.appLocalizations.unlimitedTime
                        : '${context.appLocalizations.memberValidUntil} ${DateFormat('yyyy-MM-dd').format(expiresAt)}',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: avatar),
                    const SizedBox(height: 20),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  avatar,
                  const SizedBox(width: 26),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(_AccountColors colors) {
    final info = _userInfo!;
    final balance = info.balanceAmount.toStringAsFixed(2);
    return _AccountCard(
      key: const ValueKey('account-wallet-card'),
      colors: colors,
      minHeight: 300,
      child: Stack(
        children: [
          PositionedDirectional(
            top: 70,
            end: 4,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              color: colors.primary.withValues(alpha: 0.09),
              size: 112,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountSectionTitle(
                colors: colors,
                icon: Icons.account_balance_wallet_rounded,
                title: context.appLocalizations.myWallet,
                trailing: context.appLocalizations.consumptionOnly,
              ),
              const SizedBox(height: 30),
              Text(
                context.appLocalizations.accountBalance,
                style: TextStyle(color: colors.muted, fontSize: 14),
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      balance,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 46,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      'CNY',
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Container(
                key: const ValueKey('account-auto-renew-row'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.outline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.autorenew_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.appLocalizations.autoRenew,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      context.appLocalizations.notEnabled,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const IgnorePointer(
                      child: Switch(value: false, onChanged: null),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginIpCard(_AccountColors colors) {
    return _AccountCard(
      key: const ValueKey('account-login-ip-card'),
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountSectionTitle(
            colors: colors,
            icon: Icons.public_rounded,
            title: context.appLocalizations.loginIpRecords,
            busy: _loadingLoginIps || _updatingLoginIps.isNotEmpty,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  context.appLocalizations.loginIpDescription,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('refresh-login-ip-button'),
                tooltip: context.appLocalizations.refreshData,
                onPressed: _loadingLoginIps ? null : _loadLoginIps,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingLoginIps && _loginIpList == null)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loginIpListFailed && _loginIpList == null)
            _LoginIpStatus(
              key: const ValueKey('login-ip-error-state'),
              colors: colors,
              icon: Icons.cloud_off_rounded,
              label: context.appLocalizations.loginIpListLoadFailed,
              action: TextButton.icon(
                key: const ValueKey('retry-login-ip-list-button'),
                onPressed: _loadLoginIps,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.appLocalizations.retry),
              ),
            )
          else if (_loginIpList == null || _loginIpList!.items.isEmpty)
            _LoginIpStatus(
              key: const ValueKey('login-ip-empty-state'),
              colors: colors,
              icon: Icons.public_off_rounded,
              label: context.appLocalizations.noLoginIpRecords,
            )
          else
            _buildLoginIpList(colors, _loginIpList!),
        ],
      ),
    );
  }

  Widget _buildLoginIpList(
    _AccountColors colors,
    XboardLoginIpList loginIpList,
  ) {
    final summary = loginIpList.summary;
    final records = loginIpList.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _LoginIpMetric(
                colors: colors,
                label: context.appLocalizations.loginIpCount,
                value: summary.uniqueIpCount.toString(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LoginIpMetric(
                colors: colors,
                label: context.appLocalizations.blockedIpCount,
                value: summary.blockedIpCount.toString(),
                emphasized: summary.blockedIpCount > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LoginIpMetric(
                colors: colors,
                label: context.appLocalizations.totalLoginCount,
                value: summary.totalLoginCount.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loginIpListFailed) ...[
          _LoginIpStatus(
            colors: colors,
            icon: Icons.warning_amber_rounded,
            label: context.appLocalizations.loginIpListLoadFailed,
          ),
          const SizedBox(height: 10),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wideRows = constraints.maxWidth >= _loginIpWideRowBreakpoint;
            final visibleLimit = wideRows
                ? _loginIpWideVisibleRecordLimit
                : _loginIpCompactVisibleRecordLimit;
            if (records.length <= visibleLimit) {
              return Column(
                children: [
                  for (var index = 0; index < records.length; index++) ...[
                    _buildLoginIpRow(colors, records[index], index),
                    if (index != records.length - 1)
                      Divider(height: 1, color: colors.outline),
                  ],
                ],
              );
            }
            return SizedBox(
              key: const ValueKey('login-ip-scroll-viewport'),
              height: wideRows
                  ? _loginIpWideViewportHeight
                  : _loginIpCompactViewportHeight,
              child: Scrollbar(
                controller: _loginIpScrollController,
                thumbVisibility: true,
                interactive: true,
                child: ListView.separated(
                  key: const ValueKey('login-ip-scroll-list'),
                  controller: _loginIpScrollController,
                  primary: false,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: records.length,
                  itemBuilder: (context, index) =>
                      _buildLoginIpRow(colors, records[index], index),
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, color: colors.outline),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: colors.muted, size: 16),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                context.appLocalizations.loginIpSecurityHint,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginIpRow(
    _AccountColors colors,
    XboardLoginIpRecord record,
    int index,
  ) {
    return _LoginIpRow(
      key: ValueKey(
        'login-ip-${record.id ?? index}-${record.clientType ?? 'unknown'}',
      ),
      colors: colors,
      record: record,
      updating: _updatingLoginIps.contains(record.ip),
      onBlock: () => _blockLoginIp(record),
      onUnblock: () => _unblockLoginIp(record),
    );
  }

  Widget _buildPasswordCard(_AccountColors colors) {
    return _AccountCard(
      key: const ValueKey('account-password-card'),
      colors: colors,
      child: Form(
        key: _passwordFormKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalFields = constraints.maxWidth >= 900;
            final oldPasswordField = _PasswordField(
              key: const ValueKey('old-password-field'),
              controller: _oldPasswordController,
              label: context.appLocalizations.oldPassword,
              hint: context.appLocalizations.enterOldPassword,
              obscureText: _obscureOldPassword,
              labelAbove: horizontalFields,
              onToggleVisibility: () {
                setState(() => _obscureOldPassword = !_obscureOldPassword);
              },
              validator: (value) => value == null || value.isEmpty
                  ? context.appLocalizations.enterOldPassword
                  : null,
            );
            final newPasswordField = _PasswordField(
              key: const ValueKey('new-password-field'),
              controller: _newPasswordController,
              label: context.appLocalizations.newPassword,
              hint: context.appLocalizations.enterNewPassword,
              obscureText: _obscureNewPassword,
              labelAbove: horizontalFields,
              onToggleVisibility: () {
                setState(() => _obscureNewPassword = !_obscureNewPassword);
              },
              validator: (value) => value == null || value.length < 8
                  ? context.appLocalizations.passwordTooShort
                  : null,
            );
            final confirmPasswordField = _PasswordField(
              key: const ValueKey('confirm-password-field'),
              controller: _confirmPasswordController,
              label: context.appLocalizations.confirmNewPassword,
              hint: context.appLocalizations.enterNewPassword,
              obscureText: _obscureConfirmPassword,
              labelAbove: horizontalFields,
              onToggleVisibility: () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
              validator: (value) => value != _newPasswordController.text
                  ? context.appLocalizations.passwordsDoNotMatch
                  : null,
            );
            final fields = horizontalFields
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: oldPasswordField),
                      const SizedBox(width: 14),
                      Expanded(child: newPasswordField),
                      const SizedBox(width: 14),
                      Expanded(child: confirmPasswordField),
                    ],
                  )
                : Column(
                    children: [
                      oldPasswordField,
                      const SizedBox(height: 10),
                      newPasswordField,
                      const SizedBox(height: 10),
                      confirmPasswordField,
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AccountSectionTitle(
                  colors: colors,
                  icon: Icons.lock_outline_rounded,
                  title: context.appLocalizations.changePasswordTitle,
                ),
                const SizedBox(height: 16),
                fields,
                const SizedBox(height: 18),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(
                    width: constraints.maxWidth >= 520
                        ? 240
                        : constraints.maxWidth,
                    child: _GradientAccountButton(
                      key: const ValueKey('save-password-button'),
                      onPressed: _changingPassword ? null : _changePassword,
                      icon: _changingPassword
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset_rounded),
                      label: Text(context.appLocalizations.saveChanges),
                    ),
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

class _AccountColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color secondary;
  final Color gold;
  final Color text;
  final Color muted;
  final Color outline;
  final Color shadow;

  const _AccountColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.secondary,
    required this.gold,
    required this.text,
    required this.muted,
    required this.outline,
    required this.shadow,
  });

  factory _AccountColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _AccountColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
        scheme.surface,
      ),
      surface: scheme.surfaceContainerLowest,
      surfaceSoft: scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.1),
      secondary: scheme.tertiary,
      gold: dark ? const Color(0xFFFFC75A) : const Color(0xFFD58B00),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: 0.82),
      shadow: Colors.black.withValues(alpha: dark ? 0.28 : 0.075),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final _AccountColors colors;
  final Widget child;
  final double? minHeight;

  const _AccountCard({
    super.key,
    required this.colors,
    required this.child,
    this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 20)],
      ),
      child: child,
    );
  }
}

class _AccountSectionTitle extends StatelessWidget {
  final _AccountColors colors;
  final IconData icon;
  final String title;
  final String? trailing;
  final bool busy;

  const _AccountSectionTitle({
    required this.colors,
    required this.icon,
    required this.title,
    this.trailing,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: colors.primary, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: colors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _VipBadge extends StatelessWidget {
  final _AccountColors colors;

  const _VipBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.22),
            blurRadius: 12,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond_outlined, color: Colors.white, size: 17),
          SizedBox(width: 5),
          Text(
            'VIP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _LoginIpStatus extends StatelessWidget {
  final _AccountColors colors;
  final IconData icon;
  final String label;
  final Widget? action;

  const _LoginIpStatus({
    super.key,
    required this.colors,
    required this.icon,
    required this.label,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _LoginIpMetric extends StatelessWidget {
  final _AccountColors colors;
  final String label;
  final String value;
  final bool emphasized;

  const _LoginIpMetric({
    required this.colors,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = emphasized
        ? Theme.of(context).colorScheme.error
        : colors.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginIpRow extends StatelessWidget {
  static const _wideBreakpoint = 700.0;

  final _AccountColors colors;
  final XboardLoginIpRecord record;
  final bool updating;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  const _LoginIpRow({
    super.key,
    required this.colors,
    required this.record,
    required this.updating,
    required this.onBlock,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final errorColor = Theme.of(context).colorScheme.error;
    final statusColor = record.isBlocked ? errorColor : const Color(0xFF188754);
    final statusBackground = record.isBlocked
        ? Theme.of(context).colorScheme.errorContainer
        : const Color(0xFFE0F5EA);
    final location = record.location.trim().isEmpty
        ? context.appLocalizations.unknownLocation
        : record.location;
    final client = record.clientName.trim().isEmpty
        ? context.appLocalizations.unknownClient
        : record.clientName;
    final firstLoginAt = record.firstLoginAt;
    final lastLoginAt = record.lastLoginAt;
    final lastLoginText = lastLoginAt == null
        ? context.appLocalizations.noSuccessfulLogin
        : context.appLocalizations.lastLoginAt(formatter.format(lastLoginAt));
    final firstLoginText = firstLoginAt == null
        ? context.appLocalizations.loginIpLoginCount(record.loginCount)
        : '${context.appLocalizations.firstLoginAt(formatter.format(firstLoginAt))} · ${context.appLocalizations.loginIpLoginCount(record.loginCount)}';
    final userAgent = record.userAgent?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final status = _buildStatusChip(
          context,
          statusColor: statusColor,
          background: statusBackground,
        );
        final icon = _buildClientIcon();
        final identity = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    record.ip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                status,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$location · $client · IPv${record.ipVersion}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.muted,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
            if (record.isBlocked && record.reason != null) ...[
              const SizedBox(height: 3),
              Text(
                context.appLocalizations.loginIpBlockReason(record.reason!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: errorColor, fontSize: 10.5),
              ),
            ],
          ],
        );
        if (!wide) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: identity),
                    const SizedBox(width: 4),
                    _buildAction(context, compact: true),
                  ],
                ),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 50, end: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lastLoginText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        firstLoginText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 10.5),
                      ),
                      if (userAgent != null && userAgent.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Tooltip(
                          message: userAgent,
                          child: Row(
                            children: [
                              Icon(
                                Icons.devices_other_rounded,
                                color: colors.muted,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  userAgent,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        final showDevice = constraints.maxWidth >= 920;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(flex: 3, child: identity),
              const SizedBox(width: 18),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lastLoginText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      firstLoginText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              if (showDevice) ...[
                const SizedBox(width: 18),
                Expanded(
                  flex: 2,
                  child: Tooltip(
                    message: userAgent?.isNotEmpty == true
                        ? userAgent!
                        : context.appLocalizations.unknownClient,
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices_other_rounded,
                          color: colors.muted,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            userAgent?.isNotEmpty == true
                                ? userAgent!
                                : context.appLocalizations.unknownClient,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              _buildAction(context, compact: false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        record.clientType == 'app'
            ? Icons.phone_android_rounded
            : Icons.language_rounded,
        color: colors.primary,
        size: 21,
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context, {
    required Color statusColor,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        record.isBlocked
            ? context.appLocalizations.loginIpBlockedStatus
            : context.appLocalizations.loginIpAllowedStatus,
        maxLines: 1,
        style: TextStyle(
          color: statusColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, {required bool compact}) {
    final key = ValueKey(
      '${record.isBlocked ? 'unblock' : 'block'}-login-ip-${record.id ?? record.clientType ?? 'unknown'}-${record.ip}',
    );
    final label = record.isBlocked
        ? context.appLocalizations.unblockLoginIp
        : context.appLocalizations.blockLoginIp;
    final callback = updating
        ? null
        : record.isBlocked
        ? onUnblock
        : onBlock;
    final icon = updating
        ? const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            record.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
            size: 17,
          );
    if (compact) {
      return IconButton(
        key: key,
        tooltip: label,
        onPressed: callback,
        visualDensity: VisualDensity.compact,
        icon: icon,
      );
    }
    return TextButton.icon(
      key: key,
      onPressed: callback,
      icon: icon,
      label: Text(label),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final bool labelAbove;
  final VoidCallback onToggleVisibility;
  final FormFieldValidator<String>? validator;

  const _PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscureText,
    this.labelAbove = false,
    required this.onToggleVisibility,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: TextStyle(
        color: context.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
    final field = TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
    );
    final visibilityButton = SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        onPressed: onToggleVisibility,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Icon(
          obscureText
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (labelAbove || constraints.maxWidth < 470) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  visibilityButton,
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              height: 52,
              child: Align(alignment: Alignment.centerLeft, child: labelWidget),
            ),
            Expanded(child: field),
            const SizedBox(width: 10),
            visibilityButton,
          ],
        );
      },
    );
  }
}

class _GradientAccountButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;

  const _GradientAccountButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final scheme = context.colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: const IconThemeData(color: Colors.white, size: 21),
                  child: icon,
                ),
                const SizedBox(width: 9),
                DefaultTextStyle.merge(
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  child: label,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountStatus extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;

  const _AccountStatus({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_off_outlined,
            color: context.colorScheme.outline,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(label),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.appLocalizations.retry),
          ),
        ],
      ),
    );
  }
}
