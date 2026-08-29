import 'package:flutter/material.dart';

class FengWoBrandLockup extends StatelessWidget {
  const FengWoBrandLockup({
    super.key,
    this.width = 340,
    this.taglineColor = const Color(0xFFFFC342),
  });

  final double width;
  final Color taglineColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '蜂窝加速器，更快，更稳，更实惠',
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/brand_logo_with_text.png',
              key: const Key('fengwo-brand-logo'),
              width: width,
              height: width,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 4),
            Text(
              '更快，更稳，更实惠',
              key: const Key('fengwo-brand-tagline'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: taglineColor,
                fontSize: width >= 300 ? 17 : 12,
                fontWeight: FontWeight.w600,
                letterSpacing: width >= 300 ? 3 : 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
