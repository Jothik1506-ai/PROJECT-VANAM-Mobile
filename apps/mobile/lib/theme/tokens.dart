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
  static const avatarPalette = [
    Color(0xFF1F5D2E),
    Color(0xFF7B3F2A),
    Color(0xFF4B6F8F),
    Color(0xFF7A5C1F),
    Color(0xFF6B4A7A),
  ];

  static Color avatarColorFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (value, unit) => value + unit);
    return avatarPalette[hash % avatarPalette.length];
  }
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

@immutable
class VanamPalette extends ThemeExtension<VanamPalette> {
  const VanamPalette({
    required this.brand,
    required this.brandStrong,
    required this.surface,
    required this.surfaceCard,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.danger,
    required this.noticeSurface,
    required this.noticeBorder,
    required this.memoryGradient,
    required this.shadow,
  });

  final Color brand;
  final Color brandStrong;
  final Color surface;
  final Color surfaceCard;
  final Color ink;
  final Color inkMuted;
  final Color line;
  final Color danger;
  final Color noticeSurface;
  final Color noticeBorder;
  final List<Color> memoryGradient;
  final Color shadow;

  static const light = VanamPalette(
    brand: VanamColors.brand,
    brandStrong: VanamColors.brandDark,
    surface: VanamColors.surface,
    surfaceCard: VanamColors.surfaceCard,
    ink: VanamColors.ink,
    inkMuted: VanamColors.inkMuted,
    line: VanamColors.line,
    danger: VanamColors.danger,
    noticeSurface: Color(0xFFEAF2E8),
    noticeBorder: Color(0xFFCFE0CE),
    memoryGradient: [Color(0xFFDDEAD7), Color(0xFFFFF1D2)],
    shadow: Color(0x14000000),
  );

  static const dark = VanamPalette(
    brand: Color(0xFF8DCB91),
    brandStrong: Color(0xFFE0F1DF),
    surface: Color(0xFF10150F),
    surfaceCard: Color(0xFF182117),
    ink: Color(0xFFF2F0E8),
    inkMuted: Color(0xFFB9C2B3),
    line: Color(0xFF344032),
    danger: Color(0xFFFFB4AB),
    noticeSurface: Color(0xFF1F3320),
    noticeBorder: Color(0xFF456349),
    memoryGradient: [Color(0xFF243C24), Color(0xFF4B3F22)],
    shadow: Color(0x66000000),
  );

  @override
  VanamPalette copyWith({
    Color? brand,
    Color? brandStrong,
    Color? surface,
    Color? surfaceCard,
    Color? ink,
    Color? inkMuted,
    Color? line,
    Color? danger,
    Color? noticeSurface,
    Color? noticeBorder,
    List<Color>? memoryGradient,
    Color? shadow,
  }) {
    return VanamPalette(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      surface: surface ?? this.surface,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      danger: danger ?? this.danger,
      noticeSurface: noticeSurface ?? this.noticeSurface,
      noticeBorder: noticeBorder ?? this.noticeBorder,
      memoryGradient: memoryGradient ?? this.memoryGradient,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  VanamPalette lerp(ThemeExtension<VanamPalette>? other, double t) {
    if (other is! VanamPalette) return this;
    return VanamPalette(
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      noticeSurface: Color.lerp(noticeSurface, other.noticeSurface, t)!,
      noticeBorder: Color.lerp(noticeBorder, other.noticeBorder, t)!,
      memoryGradient: [
        Color.lerp(memoryGradient.first, other.memoryGradient.first, t)!,
        Color.lerp(memoryGradient.last, other.memoryGradient.last, t)!,
      ],
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension VanamThemeContext on BuildContext {
  VanamPalette get vanam => Theme.of(this).extension<VanamPalette>()!;
}

ThemeData buildVanamTheme({Brightness brightness = Brightness.light}) {
  final palette = brightness == Brightness.dark
      ? VanamPalette.dark
      : VanamPalette.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: palette.brand,
      primary: palette.brand,
      surface: palette.surface,
    ),
    scaffoldBackgroundColor: palette.surface,
    fontFamily: 'Roboto',
    extensions: [palette],
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: TextStyle(
        color: palette.ink,
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      bodyMedium: TextStyle(color: palette.inkMuted, fontSize: 14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: VanamSpacing.md,
        vertical: VanamSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: BorderSide(color: palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: BorderSide(color: palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VanamRadii.field),
        borderSide: BorderSide(color: palette.brand, width: 1.5),
      ),
      hintStyle: TextStyle(color: palette.inkMuted),
      prefixIconColor: palette.brand,
      suffixIconColor: palette.inkMuted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.brand,
        foregroundColor: brightness == Brightness.dark
            ? VanamColors.brandDark
            : Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VanamRadii.button),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
  );
}
