import 'package:fl_clash/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ColorScheme fengWoMobileAuthColorScheme(ColorScheme base) {
  if (base.brightness == Brightness.dark) return base;
  return base.copyWith(
    primary: const Color(0xFF075EE8),
    onPrimary: Colors.white,
    secondaryContainer: const Color(0xFFE5EFFF),
    onSecondaryContainer: const Color(0xFF075EE8),
    surfaceContainerLow: const Color(0xFFF3F7FF),
  );
}

class FengWoMobileAuthLayout extends StatelessWidget {
  const FengWoMobileAuthLayout({
    super.key,
    required this.pageId,
    required this.toolbar,
    this.appVersion,
    required this.child,
  });

  final String pageId;
  final Widget toolbar;
  final String? appVersion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = fengWoMobileAuthColorScheme(
      Theme.of(context).colorScheme,
    );
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: colorScheme),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF100735),
        ),
        child: CustomPaint(
          painter: const _MobileAuthBackgroundPainter(),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        if (appVersion != null) ...[
                          Expanded(
                            child: Text(
                              'V$appVersion',
                              key: Key('$pageId-page-version'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD2DFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        toolbar,
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: Key('$pageId-mobile-scroll'),
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!keyboardVisible) ...[
                            Center(
                              child: FengWoBrandLockup(
                                key: Key('$pageId-mobile-brand-lockup'),
                                width: constraints.maxHeight < 700 ? 120 : 150,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Center(
                            child: Container(
                              key: Key('$pageId-mobile-form-card'),
                              constraints: const BoxConstraints(maxWidth: 660),
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAuthBackgroundPainter extends CustomPainter {
  const _MobileAuthBackgroundPainter();

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
