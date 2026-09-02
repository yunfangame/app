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
  final _passwordFormKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final XboardAuthService _authService;

  XboardUserInfo? _userInfo;
  bool _loading = true;
  bool _failed = false;
  bool _savingPreferences = false;
  bool _changingPassword = false;
  bool _resettingSubscription = false;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserInfo());
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _updatePreferences({
    bool? remindExpire,
    bool? remindTraffic,
  }) async {
    final session = globalState.xboardSession;
    final current = _userInfo;
    if (session == null || current == null || _savingPreferences) return;
    final nextExpire = remindExpire ?? current.remindExpire;
    final nextTraffic = remindTraffic ?? current.remindTraffic;
    setState(() {
      _savingPreferences = true;
      _userInfo = XboardUserInfo(
        email: current.email,
        balance: current.balance,
        commissionBalance: current.commissionBalance,
        remindExpire: nextExpire,
        remindTraffic: nextTraffic,
        avatarUrl: current.avatarUrl,
        telegramId: current.telegramId,
        planId: current.planId,
        expiredAtEpochSeconds: current.expiredAtEpochSeconds,
        rawData: current.rawData,
      );
    });
    try {
      await _authService.updateUserPreferences(
        endpoint: session.endpoint,
        authData: session.authData,
        remindExpire: nextExpire,
        remindTraffic: nextTraffic,
      );
      if (!mounted) return;
      _showMessage(context.appLocalizations.notificationSettingsSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _userInfo = current);
      _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _savingPreferences = false);
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

  Future<void> _resetSubscription() async {
    if (_resettingSubscription) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(context.appLocalizations.resetSubscriptionConfirmTitle),
        content: Text(context.appLocalizations.resetSubscriptionConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.appLocalizations.confirmReset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = globalState.xboardSession;
    if (session == null) return;
    setState(() => _resettingSubscription = true);
    try {
      await _authService.resetSecurity(
        endpoint: session.endpoint,
        authData: session.authData,
        userToken: session.token,
        secureSubscription: session.secureSubscription,
      );
      final refreshed = await globalState.refreshXboardSubscription?.call();
      if (refreshed != true) {
        throw const XboardAuthException(
          failure: XboardAuthFailure.subscriptionUnavailable,
          message: '订阅刷新失败，请稍后重试',
        );
      }
      if (!mounted) return;
      _showMessage(context.appLocalizations.subscriptionResetSuccess);
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _resettingSubscription = false);
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
        onRefresh: _loadUserInfo,
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
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, _) {
                      if (mobileLayout) {
                        return Column(
                          children: [
                            _buildProfileCard(colors),
                            const SizedBox(height: 16),
                            _buildWalletCard(colors),
                            const SizedBox(height: 16),
                            _buildPasswordCard(colors),
                            const SizedBox(height: 16),
                            _buildNotificationsCard(colors),
                            const SizedBox(height: 16),
                            _buildResetSubscriptionCard(colors),
                            const SizedBox(height: 16),
                            const FengWoLogoutButton(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 11,
                            child: Column(
                              children: [
                                _buildProfileCard(colors),
                                const SizedBox(height: 18),
                                _buildPasswordCard(colors),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 10,
                            child: Column(
                              children: [
                                _buildWalletCard(colors),
                                const SizedBox(height: 18),
                                _buildNotificationsCard(colors),
                                const SizedBox(height: 18),
                                _buildResetSubscriptionCard(colors),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
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

  Widget _buildNotificationsCard(_AccountColors colors) {
    final info = _userInfo!;
    return _AccountCard(
      key: const ValueKey('account-notifications-card'),
      colors: colors,
      child: Column(
        children: [
          _AccountSectionTitle(
            colors: colors,
            icon: Icons.notifications_none_rounded,
            title: context.appLocalizations.notificationSettings,
            busy: _savingPreferences,
          ),
          const SizedBox(height: 12),
          _AccountSwitchRow(
            colors: colors,
            icon: Icons.mark_email_unread_outlined,
            label: context.appLocalizations.expiryEmailReminder,
            value: info.remindExpire,
            onChanged: _savingPreferences
                ? null
                : (value) => _updatePreferences(remindExpire: value),
          ),
          Divider(height: 1, color: colors.outline),
          _AccountSwitchRow(
            colors: colors,
            icon: Icons.data_usage_rounded,
            label: context.appLocalizations.trafficEmailReminder,
            value: info.remindTraffic,
            onChanged: _savingPreferences
                ? null
                : (value) => _updatePreferences(remindTraffic: value),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard(_AccountColors colors) {
    return _AccountCard(
      key: const ValueKey('account-password-card'),
      colors: colors,
      minHeight: 420,
      child: Form(
        key: _passwordFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountSectionTitle(
              colors: colors,
              icon: Icons.lock_outline_rounded,
              title: context.appLocalizations.changePasswordTitle,
            ),
            const SizedBox(height: 18),
            _PasswordField(
              key: const ValueKey('old-password-field'),
              controller: _oldPasswordController,
              label: context.appLocalizations.oldPassword,
              hint: context.appLocalizations.enterOldPassword,
              obscureText: _obscureOldPassword,
              onToggleVisibility: () {
                setState(() => _obscureOldPassword = !_obscureOldPassword);
              },
              validator: (value) => value == null || value.isEmpty
                  ? context.appLocalizations.enterOldPassword
                  : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(
              key: const ValueKey('new-password-field'),
              controller: _newPasswordController,
              label: context.appLocalizations.newPassword,
              hint: context.appLocalizations.enterNewPassword,
              obscureText: _obscureNewPassword,
              onToggleVisibility: () {
                setState(() => _obscureNewPassword = !_obscureNewPassword);
              },
              validator: (value) => value == null || value.length < 8
                  ? context.appLocalizations.passwordTooShort
                  : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(
              key: const ValueKey('confirm-password-field'),
              controller: _confirmPasswordController,
              label: context.appLocalizations.confirmNewPassword,
              hint: context.appLocalizations.enterNewPassword,
              obscureText: _obscureConfirmPassword,
              onToggleVisibility: () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
              validator: (value) => value != _newPasswordController.text
                  ? context.appLocalizations.passwordsDoNotMatch
                  : null,
            ),
            const SizedBox(height: 22),
            _GradientAccountButton(
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
          ],
        ),
      ),
    );
  }

  Widget _buildResetSubscriptionCard(_AccountColors colors) {
    return _AccountCard(
      key: const ValueKey('reset-subscription-card'),
      colors: colors,
      minHeight: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountSectionTitle(
            colors: colors,
            icon: Icons.warning_amber_rounded,
            title: context.appLocalizations.resetSubscription,
          ),
          const SizedBox(height: 18),
          Text(
            context.appLocalizations.resetSubscriptionDescription,
            style: TextStyle(
              color: colors.muted,
              fontSize: 13,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          _GradientAccountButton(
            key: const ValueKey('reset-subscription-button'),
            onPressed: _resettingSubscription ? null : _resetSubscription,
            icon: _resettingSubscription
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(context.appLocalizations.resetSubscription),
          ),
        ],
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

class _AccountSwitchRow extends StatelessWidget {
  final _AccountColors colors;
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _AccountSwitchRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final FormFieldValidator<String>? validator;

  const _PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscureText,
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
        if (constraints.maxWidth < 470) {
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
