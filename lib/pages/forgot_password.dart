import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/brand_logo.dart';
import 'package:flutter/material.dart';

class ForgotPasswordFormData {
  const ForgotPasswordFormData({
    required this.email,
    required this.emailCode,
    required this.password,
  });

  final String email;
  final String emailCode;
  final String password;
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    this.onBack,
    this.onSendVerificationCode,
    this.onResetPassword,
  });

  final VoidCallback? onBack;
  final Future<void> Function(String email)? onSendVerificationCode;
  final Future<void> Function(ForgotPasswordFormData data)? onResetPassword;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _verificationController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitted = false;
  bool _isSendingCode = false;
  bool _isResetting = false;
  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _verificationController.dispose();
    _passwordController.dispose();
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
      await sender(_emailController.text.trim());
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
    if (_isResetting) return;
    setState(() => _submitted = true);
    if (_formKey.currentState?.validate() != true) return;
    final resetPassword = widget.onResetPassword;
    if (resetPassword == null) {
      _showMessage(context.appLocalizations.passwordResetFailed);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isResetting = true);
    final data = ForgotPasswordFormData(
      email: _emailController.text.trim(),
      emailCode: _verificationController.text.trim(),
      password: _passwordController.text,
    );
    try {
      await resetPassword(data);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(data.email);
      } else {
        _showMessage(context.appLocalizations.passwordResetSuccess);
      }
    } on XboardAuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) {
        _showMessage(context.appLocalizations.passwordResetFailed);
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
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
                Expanded(
                  flex: 4,
                  child: _ForgotPasswordBrandPanel(onBack: _goBack),
                ),
              Expanded(
                flex: 6,
                child: _ForgotPasswordFormPanel(
                  formKey: _formKey,
                  emailFieldKey: _emailFieldKey,
                  emailController: _emailController,
                  verificationController: _verificationController,
                  passwordController: _passwordController,
                  obscurePassword: _obscurePassword,
                  submitted: _submitted,
                  isSendingCode: _isSendingCode,
                  secondsRemaining: _secondsRemaining,
                  isResetting: _isResetting,
                  showCompactHeader: !showBrandPanel,
                  onBack: _goBack,
                  onTogglePassword: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  onSendVerificationCode: _sendVerificationCode,
                  onResetPassword: _submit,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForgotPasswordBrandPanel extends StatelessWidget {
  const _ForgotPasswordBrandPanel({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _ForgotPasswordBackgroundPainter()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    key: const Key('forgot-password-back-button'),
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
                    child: FengWoBrandLockup(
                      key: Key('forgot-password-brand-lockup'),
                    ),
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

class _ForgotPasswordFormPanel extends StatelessWidget {
  const _ForgotPasswordFormPanel({
    required this.formKey,
    required this.emailFieldKey,
    required this.emailController,
    required this.verificationController,
    required this.passwordController,
    required this.obscurePassword,
    required this.submitted,
    required this.isSendingCode,
    required this.secondsRemaining,
    required this.isResetting,
    required this.showCompactHeader,
    required this.onBack,
    required this.onTogglePassword,
    required this.onSendVerificationCode,
    required this.onResetPassword,
  });

  final GlobalKey<FormState> formKey;
  final GlobalKey<FormFieldState<String>> emailFieldKey;
  final TextEditingController emailController;
  final TextEditingController verificationController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool submitted;
  final bool isSendingCode;
  final int secondsRemaining;
  final bool isResetting;
  final bool showCompactHeader;
  final VoidCallback onBack;
  final VoidCallback onTogglePassword;
  final VoidCallback onSendVerificationCode;
  final VoidCallback onResetPassword;

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
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showCompactHeader) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                key: const Key(
                                  'forgot-password-mobile-back-button',
                                ),
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
                            l10n.forgotPasswordTitle,
                            key: const Key('forgot-password-page-title'),
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: showCompactHeader ? 38 : 46,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.forgotPasswordSubtitle,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: showCompactHeader ? 18 : 21,
                            ),
                          ),
                          const SizedBox(height: 30),
                          _ForgotPasswordFieldLabel(
                            label: l10n.email,
                            child: TextFormField(
                              key: emailFieldKey,
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (email.isEmpty) {
                                  return l10n.enterEmailAddress;
                                }
                                if (!RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(email)) {
                                  return l10n.invalidEmail;
                                }
                                return null;
                              },
                              decoration: _forgotPasswordInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterEmailAddress,
                                prefixIcon: Icons.mail_outline_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ForgotPasswordFieldLabel(
                            label: l10n.emailVerificationCode,
                            child: TextFormField(
                              key: const Key(
                                'forgot-password-verification-field',
                              ),
                              controller: verificationController,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? l10n.enterVerificationCode
                                  : null,
                              decoration: _forgotPasswordInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterVerificationCode,
                                prefixIcon: Icons.shield_outlined,
                                suffixIcon: Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: FilledButton.tonal(
                                    key: const Key(
                                      'forgot-password-send-code-button',
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
                              key: const Key(
                                'forgot-password-email-delivery-hint',
                              ),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          _ForgotPasswordFieldLabel(
                            label: l10n.newPassword,
                            child: TextFormField(
                              key: const Key('forgot-password-new-field'),
                              controller: passwordController,
                              obscureText: obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.newPassword],
                              onFieldSubmitted: (_) => onResetPassword(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.enterNewPassword;
                                }
                                if (value.length < 8) {
                                  return l10n.passwordTooShort;
                                }
                                return null;
                              },
                              decoration: _forgotPasswordInputDecoration(
                                colorScheme: colorScheme,
                                hintText: l10n.enterNewPassword,
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
                          const SizedBox(height: 30),
                          FilledButton.icon(
                            key: const Key('forgot-password-submit-button'),
                            onPressed: isResetting ? null : onResetPassword,
                            iconAlignment: IconAlignment.end,
                            icon: isResetting
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.lock_reset_rounded,
                                    size: 26,
                                  ),
                            label: Text(
                              isResetting
                                  ? l10n.resettingPassword
                                  : l10n.resetPasswordAction,
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
                                l10n.rememberedPassword,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 17,
                                ),
                              ),
                              TextButton(
                                key: const Key('forgot-password-back-to-login'),
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

class _ForgotPasswordFieldLabel extends StatelessWidget {
  const _ForgotPasswordFieldLabel({required this.label, required this.child});

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

InputDecoration _forgotPasswordInputDecoration({
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

class _ForgotPasswordBackgroundPainter extends CustomPainter {
  const _ForgotPasswordBackgroundPainter();

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
