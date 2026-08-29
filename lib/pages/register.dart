import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/brand_logo.dart';
import 'package:flutter/material.dart';

class RegisterFormData {
  const RegisterFormData({
    required this.email,
    required this.password,
    this.emailCode,
    this.invitationCode,
  });

  final String email;
  final String password;
  final String? emailCode;
  final String? invitationCode;
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.config,
    this.onBack,
    this.onRegister,
    this.onSendVerificationCode,
  });

  final XboardGuestConfig config;
  final VoidCallback? onBack;
  final Future<void> Function(RegisterFormData data)? onRegister;
  final Future<void> Function(String email)? onSendVerificationCode;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _invitationController = TextEditingController();
  final _verificationController = TextEditingController();

  late final List<String> _emailDomains;
  late String _emailDomain;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _isSendingCode = false;
  bool _isRegistering = false;
  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  String get _email => '${_emailController.text.trim()}$_emailDomain';

  @override
  void initState() {
    super.initState();
    _emailDomains = widget.config.emailDomains;
    _emailDomain = _emailDomains.first;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationController.dispose();
    _verificationController.dispose();
    super.dispose();
  }

  void _goBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendVerificationCode() async {
    if (_isSendingCode ||
        _secondsRemaining > 0 ||
        _emailFieldKey.currentState?.validate() != true) {
      return;
    }
    final sender = widget.onSendVerificationCode;
    if (sender == null) {
      _showMessage(context.appLocalizations.verificationApiPending);
      return;
    }
    setState(() => _isSendingCode = true);
    try {
      await sender(_email);
      if (!mounted) return;
      _startVerificationCountdown();
      _showMessage(context.appLocalizations.verificationEmailSent);
    } on XboardAuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(context.appLocalizations.verificationApiPending);
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  void _startVerificationCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  Future<void> _submit() async {
    if (_isRegistering) return;
    setState(() => _submitted = true);
    if (_formKey.currentState?.validate() != true) return;
    final register = widget.onRegister;
    if (register == null) {
      _showMessage(context.appLocalizations.registrationApiPending);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isRegistering = true);
    try {
      final invitationCode = _invitationController.text.trim();
      final data = RegisterFormData(
        email: _email,
        password: _passwordController.text,
        emailCode: widget.config.isEmailVerify
            ? _verificationController.text.trim()
            : null,
        invitationCode: invitationCode.isEmpty ? null : invitationCode,
      );
      await register(data);
      if (mounted) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(data);
        } else {
          _showMessage(context.appLocalizations.registrationSuccess);
        }
      }
    } on XboardAuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(context.appLocalizations.registrationFailed);
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showBrandPanel = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (showBrandPanel)
                Expanded(flex: 4, child: _RegisterBrandPanel(onBack: _goBack)),
              Expanded(
                flex: 6,
                child: _RegisterFormPanel(
                  formKey: _formKey,
                  emailFieldKey: _emailFieldKey,
                  emailController: _emailController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  invitationController: _invitationController,
                  verificationController: _verificationController,
                  emailDomains: _emailDomains,
                  emailDomain: _emailDomain,
                  isEmailVerify: widget.config.isEmailVerify,
                  isInviteForce: widget.config.isInviteForce,
                  obscurePassword: _obscurePassword,
                  submitted: _submitted,
                  isSendingCode: _isSendingCode,
                  secondsRemaining: _secondsRemaining,
                  isRegistering: _isRegistering,
                  showCompactHeader: !showBrandPanel,
                  onBack: _goBack,
                  onEmailDomainChanged: (domain) {
                    if (domain != null) setState(() => _emailDomain = domain);
                  },
                  onTogglePassword: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  onSendVerificationCode: _sendVerificationCode,
                  onRegister: _submit,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RegisterBrandPanel extends StatelessWidget {
  const _RegisterBrandPanel({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _RegisterBackgroundPainter()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    key: const Key('register-back-button'),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 32),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      fixedSize: const Size(58, 58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Center(
                    child: FengWoBrandLockup(key: Key('register-brand-lockup')),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterFormPanel extends StatelessWidget {
  const _RegisterFormPanel({
    required this.formKey,
    required this.emailFieldKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.invitationController,
    required this.verificationController,
    required this.emailDomains,
    required this.emailDomain,
    required this.isEmailVerify,
    required this.isInviteForce,
    required this.obscurePassword,
    required this.submitted,
    required this.isSendingCode,
    required this.secondsRemaining,
    required this.isRegistering,
    required this.showCompactHeader,
    required this.onBack,
    required this.onEmailDomainChanged,
    required this.onTogglePassword,
    required this.onSendVerificationCode,
    required this.onRegister,
  });

  final GlobalKey<FormState> formKey;
  final GlobalKey<FormFieldState<String>> emailFieldKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final TextEditingController invitationController;
  final TextEditingController verificationController;
  final List<String> emailDomains;
  final String emailDomain;
  final bool isEmailVerify;
  final bool isInviteForce;
  final bool obscurePassword;
  final bool submitted;
  final bool isSendingCode;
  final int secondsRemaining;
  final bool isRegistering;
  final bool showCompactHeader;
  final VoidCallback onBack;
  final ValueChanged<String?> onEmailDomainChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSendVerificationCode;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colorScheme = context.colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = showCompactHeader ? 24.0 : 48.0;
            final formWidth = (constraints.maxWidth - horizontalPadding * 2)
                .clamp(300.0, 620.0);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                showCompactHeader ? 16 : 32,
                horizontalPadding,
                28,
              ),
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showCompactHeader) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                key: const Key('register-mobile-back-button'),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).backButtonTooltip,
                                onPressed: onBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  fixedSize: const Size(48, 48),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Text(
                            l10n.createAccountTitle,
                            key: const Key('register-page-title'),
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: showCompactHeader ? 38 : 46,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.createAccountSubtitle,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: showCompactHeader ? 18 : 21,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _RegisterFieldLabel(
                            label: l10n.email,
                            child: TextFormField(
                              key: emailFieldKey,
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (value) {
                                final account = value?.trim() ?? '';
                                if (account.isEmpty) return l10n.enterEmail;
                                if (!RegExp(r'^[^@\s]+$').hasMatch(account)) {
                                  return l10n.invalidEmailAccount;
                                }
                                return null;
                              },
                              decoration: _registerInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterEmail,
                                prefixIcon: Icons.mail_outline_rounded,
                                suffixIcon: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      key: const Key(
                                        'register-email-domain-dropdown',
                                      ),
                                      value: emailDomain,
                                      isDense: true,
                                      isExpanded: true,
                                      borderRadius: BorderRadius.circular(14),
                                      onChanged: onEmailDomainChanged,
                                      items: emailDomains
                                          .map(
                                            (domain) => DropdownMenuItem(
                                              value: domain,
                                              child: Text(
                                                domain,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 130,
                                  maxWidth: 170,
                                ),
                              ),
                            ),
                          ),
                          if (isEmailVerify) ...[
                            const SizedBox(height: 18),
                            _RegisterFieldLabel(
                              label: l10n.emailVerificationCode,
                              child: TextFormField(
                                key: const Key('register-verification-field'),
                                controller: verificationController,
                                textInputAction: TextInputAction.next,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? l10n.enterVerificationCode
                                    : null,
                                decoration: _registerInputDecoration(
                                  colorScheme: colorScheme,
                                  hintText: l10n.enterVerificationCode,
                                  prefixIcon: Icons.shield_outlined,
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: FilledButton.tonal(
                                      key: const Key(
                                        'register-send-code-button',
                                      ),
                                      onPressed:
                                          isSendingCode || secondsRemaining > 0
                                          ? null
                                          : onSendVerificationCode,
                                      child: Text(
                                        isSendingCode
                                            ? l10n.sendingVerificationCode
                                            : secondsRemaining > 0
                                            ? '${secondsRemaining}s'
                                            : l10n.sendVerificationCode,
                                      ),
                                    ),
                                  ),
                                  suffixIconConstraints: const BoxConstraints(
                                    minWidth: 108,
                                    minHeight: 48,
                                  ),
                                ),
                              ),
                            ),
                            if (secondsRemaining > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                l10n.verificationEmailSent,
                                key: const Key('register-email-delivery-hint'),
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 18),
                          _RegisterFieldLabel(
                            label: l10n.password,
                            child: TextFormField(
                              key: const Key('register-password-field'),
                              controller: passwordController,
                              obscureText: obscurePassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.enterPassword;
                                }
                                if (value.length < 8) {
                                  return l10n.passwordTooShort;
                                }
                                return null;
                              },
                              decoration: _registerInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterPassword,
                                prefixIcon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  tooltip: obscurePassword
                                      ? l10n.showPassword
                                      : l10n.hidePassword,
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
                          const SizedBox(height: 18),
                          _RegisterFieldLabel(
                            label: l10n.confirmPassword,
                            child: TextFormField(
                              key: const Key('register-confirm-password-field'),
                              controller: confirmPasswordController,
                              obscureText: obscurePassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.enterConfirmPassword;
                                }
                                if (value != passwordController.text) {
                                  return l10n.passwordsDoNotMatch;
                                }
                                return null;
                              },
                              decoration: _registerInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterConfirmPassword,
                                prefixIcon: Icons.lock_reset_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _RegisterFieldLabel(
                            label: isInviteForce
                                ? l10n.invitationCode
                                : l10n.invitationCodeOptional,
                            child: TextFormField(
                              key: const Key('register-invitation-field'),
                              controller: invitationController,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (isInviteForce &&
                                    (value == null || value.trim().isEmpty)) {
                                  return l10n.invitationCodeRequired;
                                }
                                return null;
                              },
                              decoration: _registerInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterInvitationCode,
                                prefixIcon: Icons.redeem_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            key: const Key('register-submit-button'),
                            onPressed: isRegistering ? null : onRegister,
                            iconAlignment: IconAlignment.end,
                            icon: isRegistering
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_add_alt_1_rounded,
                                    size: 25,
                                  ),
                            label: Text(
                              l10n.registerAction,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(70),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.28),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                l10n.alreadyHaveAccount,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 17,
                                ),
                              ),
                              TextButton(
                                key: const Key('register-back-to-login'),
                                onPressed: onBack,
                                child: Text(
                                  l10n.backToLogin,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
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
      ),
    );
  }
}

class _RegisterFieldLabel extends StatelessWidget {
  const _RegisterFieldLabel({required this.label, required this.child});

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
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

InputDecoration _registerInputDecoration({
  required ColorScheme colorScheme,
  required String hintText,
  required IconData prefixIcon,
  Widget? suffixIcon,
  BoxConstraints? suffixIconConstraints,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18),
    prefixIcon: Icon(prefixIcon, size: 28),
    suffixIcon: suffixIcon,
    suffixIconConstraints: suffixIconConstraints,
    filled: true,
    fillColor: colorScheme.surfaceContainerLowest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.primary, width: 2.4),
    ),
    errorBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.error, width: 1.8),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.error, width: 2.2),
    ),
  );
}

class _RegisterBackgroundPainter extends CustomPainter {
  const _RegisterBackgroundPainter();

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
