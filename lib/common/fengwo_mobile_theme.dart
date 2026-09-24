import 'package:flutter/material.dart';

const fengWoMobileBrandColor = Color(0xFF075EE8);

ColorScheme fengWoMobileColorScheme({
  required ColorScheme colorScheme,
  required TargetPlatform platform,
  required bool useBrandColor,
  required DynamicSchemeVariant schemeVariant,
}) {
  if (platform != TargetPlatform.android) return colorScheme;

  final scheme = useBrandColor
      ? ColorScheme.fromSeed(
          seedColor: fengWoMobileBrandColor,
          brightness: colorScheme.brightness,
          dynamicSchemeVariant: schemeVariant,
        )
      : colorScheme;
  if (scheme.brightness == Brightness.dark) return scheme;

  final useBrandPrimary =
      useBrandColor && schemeVariant == DynamicSchemeVariant.content;
  final primary = useBrandPrimary ? fengWoMobileBrandColor : scheme.primary;
  Color tint(double opacity) =>
      Color.alphaBlend(primary.withValues(alpha: opacity), Colors.white);

  return scheme.copyWith(
    primary: primary,
    onPrimary: useBrandPrimary ? Colors.white : scheme.onPrimary,
    primaryContainer: tint(0.12),
    onPrimaryContainer: primary,
    secondaryContainer: tint(0.14),
    onSecondaryContainer: primary,
    surface: tint(0.03),
    surfaceDim: tint(0.08),
    surfaceBright: Colors.white,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: tint(0.04),
    surfaceContainerHigh: tint(0.07),
    surfaceContainerHighest: tint(0.10),
    outlineVariant: tint(0.20),
  );
}
