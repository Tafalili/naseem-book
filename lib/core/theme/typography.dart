import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Font families bundled in assets/fonts (no runtime font fetching).
abstract final class NFonts {
  static const ui = 'IBMPlexSansArabic'; // body, UI, forms
  static const display = 'ReemKufi'; // headings, hero titles
  static const playful = 'Marhey'; // alt heading candidate
  static const tajawal = 'Tajawal'; // alt UI candidate
  static const naskh = 'Amiri'; // long printed text in the book
  static const ruqaa = 'ArefRuqaa'; // child name / calligraphic accents

  /// Fonts offered to customers for printed text (mirrors app_settings.enabled_fonts).
  static const printable = [naskh, ruqaa, display];
}

TextTheme buildTextTheme() {
  const ink = NColors.ink;
  TextStyle d(double size, FontWeight w, double h) => TextStyle(
        fontFamily: NFonts.display,
        fontSize: size,
        fontWeight: w,
        height: h,
        color: ink,
      );
  TextStyle u(double size, FontWeight w, double h, [Color c = ink]) => TextStyle(
        fontFamily: NFonts.ui,
        fontSize: size,
        fontWeight: w,
        height: h,
        color: c,
      );

  return TextTheme(
    displayLarge: d(56, FontWeight.w700, 1.25),
    displayMedium: d(44, FontWeight.w700, 1.25),
    displaySmall: d(36, FontWeight.w600, 1.3),
    headlineLarge: d(32, FontWeight.w600, 1.35),
    headlineMedium: d(28, FontWeight.w600, 1.35),
    headlineSmall: d(24, FontWeight.w600, 1.4),
    titleLarge: u(20, FontWeight.w600, 1.5),
    titleMedium: u(17, FontWeight.w600, 1.5),
    titleSmall: u(15, FontWeight.w600, 1.5),
    bodyLarge: u(17, FontWeight.w400, 1.75),
    bodyMedium: u(15, FontWeight.w400, 1.7),
    bodySmall: u(13, FontWeight.w400, 1.6, NColors.inkMuted),
    labelLarge: u(15, FontWeight.w600, 1.4),
    labelMedium: u(13, FontWeight.w500, 1.4),
    labelSmall: u(12, FontWeight.w500, 1.4, NColors.inkMuted),
  );
}
