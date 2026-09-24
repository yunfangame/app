import 'dart:math' as math;

import 'package:fl_clash/common/fengwo_mobile_theme.dart';
import 'package:fl_clash/widgets/fengwo_mobile_auth_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ColorScheme makeScheme({
    Color seed = const Color(0xFF08749F),
    Brightness brightness = Brightness.light,
  }) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.content,
  );

  ColorScheme applyScheme(
    ColorScheme original, {
    TargetPlatform platform = TargetPlatform.android,
    bool useBrandColor = true,
    DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.content,
  }) => fengWoMobileColorScheme(
    colorScheme: original,
    platform: platform,
    useBrandColor: useBrandColor,
    schemeVariant: schemeVariant,
  );

  test('Android default has white cards and readable vivid actions', () {
    final scheme = applyScheme(makeScheme());

    expect(scheme.primary, fengWoMobileBrandColor);
    expect(scheme.surfaceContainerLow, Colors.white);
    expect(scheme.surface, isNot(scheme.surfaceContainerLow));
    expect(
      _contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.surfaceContainerLow, scheme.onSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('custom and dynamic palettes keep their selected accent colors', () {
    for (final seed in [Colors.purple, Colors.green, Colors.amber]) {
      final original = makeScheme(seed: seed);
      final scheme = applyScheme(original, useBrandColor: false);

      expect(scheme.primary, original.primary);
      expect(scheme.onPrimary, original.onPrimary);
      expect(scheme.error, original.error);
      expect(scheme.surfaceContainerLow, Colors.white);
      expect(
        _contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('dark mode retains dark surfaces and readable colors', () {
    final original = makeScheme(brightness: Brightness.dark);
    final scheme = applyScheme(original);

    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface.computeLuminance(), lessThan(0.1));
    expect(
      _contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.surfaceContainerLow, scheme.onSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(applyScheme(original, useBrandColor: false), original);
  });

  test('monochrome selection remains monochrome', () {
    final scheme = applyScheme(
      makeScheme(),
      schemeVariant: DynamicSchemeVariant.monochrome,
    );

    expect(scheme.primary.r, scheme.primary.g);
    expect(scheme.primary.g, scheme.primary.b);
    expect(
      _contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('desktop and iOS color schemes are not changed', () {
    final original = makeScheme();
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.iOS,
    ]) {
      expect(applyScheme(original, platform: platform), same(original));
    }
  });
  test('light authentication actions use the vivid brand color', () {
    final scheme = fengWoMobileAuthColorScheme(makeScheme());
    expect(scheme.primary, fengWoMobileBrandColor);
    expect(
      _contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.secondaryContainer, scheme.onSecondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark authentication preserves readable text and selected colors', () {
    final original = makeScheme(brightness: Brightness.dark);
    final scheme = fengWoMobileAuthColorScheme(original);
    expect(scheme, same(original));
    expect(
      _contrast(scheme.primary, scheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(scheme.onSurface, scheme.surfaceContainerLow),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  return (math.max(firstLuminance, secondLuminance) + 0.05) /
      (math.min(firstLuminance, secondLuminance) + 0.05);
}
