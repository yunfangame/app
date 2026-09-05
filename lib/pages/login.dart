import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LoginFormPrefill {
  const LoginFormPrefill({required this.email, required this.password});

  final String email;
  final String password;
}

typedef LoginAuthenticatedCallback =
    Future<void> Function(
      XboardLoginResult session,
      String email,
      String password,
      bool rememberMe,
      bool autoLogin,
    );

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLogin,
    required this.onLanguagePressed,
    required this.onThemePressed,
    required this.onSupportPressed,
    required this.appVersion,
    this.authenticate,
    this.rememberedEmail,
    this.restoreRemembered,
    this.onRegisterPressed,
    this.onForgotPasswordPressed,
    this.configuredLocale,
    this.apiHealthService,
    this.prefill,
    this.onAuthenticated,
    this.initialRememberMe = false,
    this.initialAutoLogin = false,
    this.onRememberMeDisabled,
    this.onAutomaticLoginDisabled,
    this.offlineAvailable = false,
    this.onOfflinePressed,
  });

  final VoidCallback onLogin;
  final ValueChanged<BuildContext> onLanguagePressed;
  final ValueChanged<BuildContext> onThemePressed;
  final ValueChanged<BuildContext> onSupportPressed;
  final String appVersion;
  final Future<XboardLoginResult> Function(String email, String password)?
  authenticate;
  final String? rememberedEmail;
  final Future<XboardLoginResult> Function(String email)? restoreRemembered;
  final VoidCallback? onRegisterPressed;
  final VoidCallback? onForgotPasswordPressed;
  final String? configuredLocale;
  final ApiHealthService? apiHealthService;
  final LoginFormPrefill? prefill;
  final LoginAuthenticatedCallback? onAuthenticated;
  final bool initialRememberMe;
  final bool initialAutoLogin;
  final VoidCallback? onRememberMeDisabled;
  final VoidCallback? onAutomaticLoginDisabled;
  final bool offlineAvailable;
  final Future<void> Function()? onOfflinePressed;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _autoLogin = false;
  bool _submitted = false;
  bool _isSubmitting = false;
  bool _isOpeningOffline = false;
  bool _rememberedLoginRejected = false;

  bool get _canRestoreRemembered =>
      _rememberMe &&
      !_rememberedLoginRejected &&
      widget.restoreRemembered != null &&
      (widget.rememberedEmail?.trim().isNotEmpty ?? false) &&
      widget.rememberedEmail!.trim().toLowerCase() ==
          _emailController.text.trim().toLowerCase() &&
      _passwordController.text.isEmpty;

  void _credentialsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _autoLogin = widget.initialAutoLogin;
    _rememberMe = widget.initialRememberMe || _autoLogin;
    _applyPrefill(widget.prefill);
    _emailController.addListener(_credentialsChanged);
    _passwordController.addListener(_credentialsChanged);
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.prefill, widget.prefill)) {
      _applyPrefill(widget.prefill);
    }
  }

  void _applyPrefill(LoginFormPrefill? prefill) {
    if (prefill == null) return;
    _emailController.value = TextEditingValue(
      text: prefill.email,
      selection: TextSelection.collapsed(offset: prefill.email.length),
    );
    _passwordController.value = TextEditingValue(
      text: prefill.password,
      selection: TextSelection.collapsed(offset: prefill.password.length),
    );
    _submitted = false;
  }

  @override
  void dispose() {
    _emailController.removeListener(_credentialsChanged);
    _passwordController.removeListener(_credentialsChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || _isOpeningOffline) return;
    final useRemembered = _canRestoreRemembered;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final rememberMe = _rememberMe;
    final autoLogin = _autoLogin;
    setState(() => _submitted = true);
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      final authenticate = widget.authenticate;
      XboardLoginResult? session;
      if (useRemembered) {
        session = await widget.restoreRemembered!(email);
      } else if (authenticate != null) {
        session = await authenticate(email, password);
      }
      if (!mounted) return;
      final onAuthenticated = widget.onAuthenticated;
      if (session != null && onAuthenticated != null) {
        await onAuthenticated(session, email, password, rememberMe, autoLogin);
      }
      if (!mounted) return;
      widget.onLogin();
    } on XboardAuthException catch (error) {
      if (!mounted) return;
      final expired =
          useRemembered &&
          error.failure == XboardAuthFailure.authenticationRejected;
      if (expired) {
        setState(() {
          _rememberedLoginRejected = true;
          _autoLogin = false;
        });
        _passwordFocusNode.requestFocus();
      }
      _showLoginError(
        expired ? context.appLocalizations.loginSessionExpired : error.message,
      );
    } catch (_) {
      if (!mounted) return;
      _showLoginError(context.appLocalizations.loginFailed);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openOffline() async {
    if (_isSubmitting || _isOpeningOffline || !widget.offlineAvailable) return;
    final callback = widget.onOfflinePressed;
    if (callback == null) return;
    setState(() => _isOpeningOffline = true);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _isOpeningOffline = false);
    }
  }

  void _showLoginError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPendingMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.appLocalizations.featureComingSoon)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showBrandPanel = constraints.maxWidth >= 900;
          return Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    if (showBrandPanel)
                      Expanded(
                        flex: 4,
                        child: _BrandPanel(
                          onLanguagePressed: widget.onLanguagePressed,
                          onThemePressed: widget.onThemePressed,
                          onSupportPressed: widget.onSupportPressed,
                          appVersion: widget.appVersion,
                          configuredLocale: widget.configuredLocale,
                        ),
                      ),
                    Expanded(
                      flex: 6,
                      child: _LoginFormPanel(
                        formKey: _formKey,
                        emailController: _emailController,
                        passwordController: _passwordController,
                        emailFocusNode: _emailFocusNode,
                        passwordFocusNode: _passwordFocusNode,
                        obscurePassword: _obscurePassword,
                        rememberMe: _rememberMe,
                        canRestoreRemembered: _canRestoreRemembered,
                        autoLogin: _autoLogin,
                        submitted: _submitted,
                        isSubmitting: _isSubmitting,
                        isOpeningOffline: _isOpeningOffline,
                        offlineAvailable: widget.offlineAvailable,
                        onTogglePassword: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                        onRememberChanged: (value) {
                          if (_isSubmitting) return;
                          setState(() {
                            _rememberMe = value;
                            if (!value) {
                              _autoLogin = false;
                              _rememberedLoginRejected = true;
                            }
                          });
                          if (!value) widget.onRememberMeDisabled?.call();
                        },
                        onAutoLoginChanged: (value) {
                          if (_isSubmitting) return;
                          setState(() {
                            _autoLogin = value;
                            if (value) _rememberMe = true;
                          });
                          if (!value) {
                            widget.onAutomaticLoginDisabled?.call();
                          }
                        },
                        onSubmit: _submit,
                        onOffline: _openOffline,
                        onRegister:
                            widget.onRegisterPressed ?? _showPendingMessage,
                        onForgotPassword:
                            widget.onForgotPasswordPressed ??
                            _showPendingMessage,
                        topPadding: showBrandPanel ? 28 : 104,
                        showCompactBrand: !showBrandPanel,
                      ),
                    ),
                  ],
                ),
              ),
              if (showBrandPanel)
                Positioned.fill(
                  child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(16, 18, 24, 16),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: ApiHealthControl(
                        service: widget.apiHealthService,
                        foregroundColor: context.colorScheme.onSurfaceVariant,
                        buttonBackgroundColor:
                            context.colorScheme.surfaceContainerHighest,
                        buttonBorderColor: context.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              if (!showBrandPanel)
                Positioned.fill(
                  child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _MobileLoginToolbar(
                        onLanguagePressed: widget.onLanguagePressed,
                        onThemePressed: widget.onThemePressed,
                        onSupportPressed: widget.onSupportPressed,
                        configuredLocale: widget.configuredLocale,
                        apiHealthService: widget.apiHealthService,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.onLanguagePressed,
    required this.onThemePressed,
    required this.onSupportPressed,
    required this.appVersion,
    required this.configuredLocale,
  });

  final ValueChanged<BuildContext> onLanguagePressed;
  final ValueChanged<BuildContext> onThemePressed;
  final ValueChanged<BuildContext> onSupportPressed;
  final String appVersion;
  final String? configuredLocale;

  @override
  Widget build(BuildContext context) {
    final locale = configuredLocale ?? '';
    final isDefaultLocale = locale.isEmpty;
    final localeLabel = isDefaultLocale ? null : Intl.message(locale);
    final displayVersion = appVersion.replaceFirst(RegExp(r'^[vV]'), '');
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _BrandBackgroundPainter()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Builder(
                        builder: (buttonContext) => _BrandActionButton(
                          key: const Key('login-language-button'),
                          tooltip: context.appLocalizations.language,
                          icon: Icons.translate_rounded,
                          iconSize: isDefaultLocale ? 24 : 30,
                          label: localeLabel,
                          onPressed: () => onLanguagePressed(buttonContext),
                        ),
                      ),
                      Builder(
                        builder: (buttonContext) => _BrandActionButton(
                          tooltip: context.appLocalizations.theme,
                          icon: Icons.palette_outlined,
                          badge: true,
                          onPressed: () => onThemePressed(buttonContext),
                        ),
                      ),
                      Builder(
                        builder: (buttonContext) => _BrandActionButton(
                          tooltip: context.appLocalizations.onlineSupport,
                          icon: Icons.headset_mic_outlined,
                          onPressed: () => onSupportPressed(buttonContext),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 3),
                  const Center(
                    child: FengWoBrandLockup(key: Key('login-brand-lockup')),
                  ),
                  const Spacer(flex: 4),
                  Center(
                    child: Text(
                      '© 2026 蜂窝加速器 V$displayVersion',
                      key: const Key('login-copyright'),
                      style: const TextStyle(
                        color: Color(0xFFC8D0F0),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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

class _MobileLoginToolbar extends StatelessWidget {
  const _MobileLoginToolbar({
    required this.onLanguagePressed,
    required this.onThemePressed,
    required this.onSupportPressed,
    required this.configuredLocale,
    required this.apiHealthService,
  });

  final ValueChanged<BuildContext> onLanguagePressed;
  final ValueChanged<BuildContext> onThemePressed;
  final ValueChanged<BuildContext> onSupportPressed;
  final String? configuredLocale;
  final ApiHealthService? apiHealthService;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = context.colorScheme.onSurfaceVariant;
    final backgroundColor = context.colorScheme.surfaceContainerHighest;
    final isDefaultLocale = (configuredLocale ?? '').isEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (buttonContext) => _BrandActionButton(
            key: const Key('login-language-button'),
            tooltip: context.appLocalizations.language,
            icon: Icons.translate_rounded,
            iconSize: isDefaultLocale ? 24 : 28,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            onPressed: () => onLanguagePressed(buttonContext),
          ),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (buttonContext) => _BrandActionButton(
            tooltip: context.appLocalizations.theme,
            icon: Icons.palette_outlined,
            badge: true,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            onPressed: () => onThemePressed(buttonContext),
          ),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (buttonContext) => _BrandActionButton(
            tooltip: context.appLocalizations.onlineSupport,
            icon: Icons.headset_mic_outlined,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            onPressed: () => onSupportPressed(buttonContext),
          ),
        ),
        const SizedBox(width: 8),
        ApiHealthControl(
          service: apiHealthService,
          foregroundColor: foregroundColor,
          buttonBackgroundColor: backgroundColor,
          buttonBorderColor: context.colorScheme.outlineVariant,
        ),
      ],
    );
  }
}

class _BrandActionButton extends StatelessWidget {
  const _BrandActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge = false,
    this.label,
    this.iconSize = 30,
    this.foregroundColor,
    this.backgroundColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool badge;
  final String? label;
  final double iconSize;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final resolvedForegroundColor = foregroundColor ?? Colors.white;
    final resolvedBackgroundColor =
        backgroundColor ?? Colors.white.withValues(alpha: 0.18);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (label == null)
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, size: iconSize),
            color: resolvedForegroundColor,
            style: IconButton.styleFrom(
              backgroundColor: resolvedBackgroundColor,
              fixedSize: const Size(58, 58),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )
        else
          Tooltip(
            message: tooltip,
            child: TextButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: iconSize),
              label: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(
                foregroundColor: resolvedForegroundColor,
                backgroundColor: resolvedBackgroundColor,
                fixedSize: const Size(140, 58),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        if (badge)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC928),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.obscurePassword,
    required this.rememberMe,
    required this.canRestoreRemembered,
    required this.autoLogin,
    required this.submitted,
    required this.isSubmitting,
    required this.isOpeningOffline,
    required this.offlineAvailable,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onAutoLoginChanged,
    required this.onSubmit,
    required this.onOffline,
    required this.onRegister,
    required this.onForgotPassword,
    required this.topPadding,
    required this.showCompactBrand,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final bool obscurePassword;
  final bool rememberMe;
  final bool canRestoreRemembered;
  final bool autoLogin;
  final bool submitted;
  final bool isSubmitting;
  final bool isOpeningOffline;
  final bool offlineAvailable;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onAutoLoginChanged;
  final VoidCallback onSubmit;
  final VoidCallback onOffline;
  final VoidCallback onRegister;
  final VoidCallback onForgotPassword;
  final double topPadding;
  final bool showCompactBrand;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final formWidth = (constraints.maxWidth - 80).clamp(300.0, 620.0);
          return Padding(
            padding: EdgeInsets.fromLTRB(40, topPadding, 40, 28),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: formWidth,
                  child: Form(
                    key: formKey,
                    autovalidateMode: submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          key: const Key('login-page-title'),
                          showCompactBrand ? '蜂窝加速器' : appLocalizations.login,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 46,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appLocalizations.loginWelcome,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 42),
                        _FieldLabel(
                          label: appLocalizations.email,
                          child: TextFormField(
                            key: const Key('login-email-field'),
                            controller: emailController,
                            readOnly: isSubmitting,
                            focusNode: emailFocusNode,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            onFieldSubmitted: (_) =>
                                passwordFocusNode.requestFocus(),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) {
                                return appLocalizations.enterEmail;
                              }
                              if (!RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(email)) {
                                return appLocalizations.invalidEmail;
                              }
                              return null;
                            },
                            decoration: _inputDecoration(
                              colorScheme: colorScheme,
                              hintText: appLocalizations.enterEmail,
                              prefixIcon: Icons.mail_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _FieldLabel(
                          label: appLocalizations.password,
                          child: TextFormField(
                            key: const Key('login-password-field'),
                            controller: passwordController,
                            readOnly: isSubmitting,
                            focusNode: passwordFocusNode,
                            obscureText: obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => onSubmit(),
                            validator: (value) {
                              if (!canRestoreRemembered &&
                                  (value == null || value.isEmpty)) {
                                return appLocalizations.enterPassword;
                              }
                              return null;
                            },
                            decoration: _inputDecoration(
                              colorScheme: colorScheme,
                              hintText: canRestoreRemembered
                                  ? appLocalizations.rememberedLoginHint
                                  : appLocalizations.enterPassword,
                              prefixIcon: Icons.lock_outline_rounded,
                              suffixIcon: IconButton(
                                tooltip: obscurePassword
                                    ? appLocalizations.showPassword
                                    : appLocalizations.hidePassword,
                                onPressed: onTogglePassword,
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _LoginOptions(
                          compact: formWidth < 420,
                          rememberMe: rememberMe,
                          autoLogin: autoLogin,
                          onRememberChanged: onRememberChanged,
                          onAutoLoginChanged: onAutoLoginChanged,
                        ),
                        const SizedBox(height: 44),
                        FilledButton.icon(
                          key: const Key('login-submit-button'),
                          onPressed: isSubmitting ? null : onSubmit,
                          iconAlignment: IconAlignment.end,
                          icon: isSubmitting
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 26),
                          label: Text(
                            isSubmitting
                                ? appLocalizations.loggingIn
                                : appLocalizations.login,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            minimumSize: const Size.fromHeight(76),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                            shadowColor: Colors.black.withValues(alpha: 0.28),
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key('login-offline-button'),
                          onPressed: offlineAvailable && !isOpeningOffline
                              ? onOffline
                              : null,
                          icon: isOpeningOffline
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_off_rounded),
                          label: Text(
                            offlineAvailable
                                ? appLocalizations.offlineEntry
                                : appLocalizations.offlineEntryUnavailable,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        if (offlineAvailable) ...[
                          const SizedBox(height: 8),
                          Text(
                            appLocalizations.offlineEntryHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: onRegister,
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: Text(appLocalizations.registerAccount),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: onForgotPassword,
                              icon: const Icon(Icons.help_outline_rounded),
                              label: Text(appLocalizations.forgotPassword),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration({
    required ColorScheme colorScheme,
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 20),
      prefixIcon: Icon(
        prefixIcon,
        color: colorScheme.onSurfaceVariant,
        size: 28,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 62),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 23),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error, width: 2.5),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.colorScheme.onSurface,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _LoginOptions extends StatelessWidget {
  const _LoginOptions({
    required this.compact,
    required this.rememberMe,
    required this.autoLogin,
    required this.onRememberChanged,
    required this.onAutoLoginChanged,
  });

  final bool compact;
  final bool rememberMe;
  final bool autoLogin;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onAutoLoginChanged;

  @override
  Widget build(BuildContext context) {
    final remember = _LoginCheckbox(
      label: context.appLocalizations.rememberMe,
      value: rememberMe,
      onChanged: onRememberChanged,
    );
    final automatic = _LoginCheckbox(
      label: context.appLocalizations.automaticLogin,
      value: autoLogin,
      onChanged: onAutoLoginChanged,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [remember, const SizedBox(height: 4), automatic],
      );
    }
    return Row(
      children: [
        Expanded(child: remember),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: automatic),
        ),
      ],
    );
  }
}

class _LoginCheckbox extends StatelessWidget {
  const _LoginCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
              activeColor: context.colorScheme.primary,
              checkColor: context.colorScheme.onPrimary,
              side: BorderSide(color: context.colorScheme.outline, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: context.colorScheme.onSurfaceVariant,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandBackgroundPainter extends CustomPainter {
  const _BrandBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF141155), Color(0xFF10022F), Color(0xFF07005A)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    _drawGlow(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.66, -size.height * 0.02),
        width: size.width * 0.88,
        height: size.height * 0.25,
      ),
      const [Color(0xFF1ABDE0), Color(0xFFE53173), Colors.transparent],
    );
    _drawGlow(
      canvas,
      Rect.fromCenter(
        center: Offset(-size.width * 0.08, size.height * 0.48),
        width: size.width * 0.72,
        height: size.height * 0.28,
      ),
      const [Color(0xFF00D8F1), Color(0xFF1157D1), Colors.transparent],
    );
    _drawGlow(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.2, size.height * 1.03),
        width: size.width * 0.76,
        height: size.height * 0.32,
      ),
      const [Color(0xFF08D7E8), Color(0xFF1328BE), Colors.transparent],
    );
  }

  void _drawGlow(Canvas canvas, Rect rect, List<Color> colors) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        radius: 0.9,
        colors: colors,
        stops: const [0, 0.48, 1],
      ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
