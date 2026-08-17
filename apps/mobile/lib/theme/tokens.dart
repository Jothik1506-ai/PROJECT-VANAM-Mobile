import 'package:flutter/material.dart';

/// VANAM semantic design tokens.
/// Widgets should reference these, never a raw hex value directly.
/// Mirrors the palette locked in ARCHITECTURE.md / the web platform's tokens.
class VanamColors {
  VanamColors._();

  static const brand = Color(0xFF1F5D2E); // forest green — platform chrome
  static const brandDark = Color(0xFF163F20);
  static const surface = Color(0xFFFAF6EC); // cream background
  static const surfaceCard = Color(0xFFFFFFFF);
  static const ink = Color(0xFF20241F); // primary text
  static const inkMuted = Color(0xFF6B7268); // secondary text
  static const line = Color(0xFFE3DECD); // borders, dividers
  static const danger = Color(0xFFB3261E); // destructive actions only
}

class VanamSpacing {
  VanamSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class VanamRadii {
  VanamRadii._();

  static const field = 14.0;
  static const button = 28.0;
  static const card = 20.0;
}

ThemeData buildVanamTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: VanamColors.brand,
      primary: VanamColors.brand,
      surface: VanamColors.surface,
    ),
    scaffoldBackgroundColor: VanamColors.surface,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: const TextStyle(
        color: VanamColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      bodyMedium: const TextStyle(color: VanamColors.inkMuted, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VanamColors.surfaceCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: VanamSpacing.md,
        vertical: VanamSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: const BorderSide(color: VanamColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: const BorderSide(color: VanamColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: const BorderSide(color: VanamColors.brand, width: 1.5),
      ),
      hintStyle: const TextStyle(color: VanamColors.inkMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VanamColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VanamRadii.button),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
      ),
    ),
  );
}
