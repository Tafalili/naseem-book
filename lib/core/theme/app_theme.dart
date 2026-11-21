import 'package:material_ui/material_ui.dart';

import 'tokens.dart';
import 'typography.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: NColors.sage,
    brightness: Brightness.light,
  ).copyWith(
    primary: NColors.sage,
    onPrimary: Colors.white,
    primaryContainer: NColors.sageSoft,
    onPrimaryContainer: NColors.sageDark,
    secondary: NColors.sand,
    onSecondary: NColors.ink,
    secondaryContainer: NColors.sandSoft,
    tertiary: NColors.sky,
    tertiaryContainer: NColors.skySoft,
    surface: NColors.surface,
    onSurface: NColors.ink,
    onSurfaceVariant: NColors.inkMuted,
    surfaceContainerLow: NColors.paper,
    surfaceContainer: NColors.surfaceAlt,
    outline: NColors.line,
    outlineVariant: NColors.line,
    error: NColors.danger,
  );

  final text = buildTextTheme();
  const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(NRadius.md));
  const btnPadding = EdgeInsets.symmetric(horizontal: NSpace.lg, vertical: NSpace.md);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: NColors.paper,
    fontFamily: NFonts.ui,
    textTheme: text,
    dividerColor: NColors.line,
    appBarTheme: AppBarTheme(
      backgroundColor: NColors.paper,
      foregroundColor: NColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: NColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(NRadius.lg),
        side: BorderSide(color: NColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NColors.sage,
        foregroundColor: Colors.white,
        padding: btnPadding,
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NColors.sageDark,
        side: const BorderSide(color: NColors.sage, width: 1.4),
        padding: btnPadding,
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: NColors.sageDark,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: NSpace.md, vertical: 14),
      hintStyle: text.bodyMedium?.copyWith(color: NColors.inkMuted),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(NRadius.md),
        borderSide: BorderSide(color: NColors.line),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(NRadius.md),
        borderSide: BorderSide(color: NColors.line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(NRadius.md),
        borderSide: BorderSide(color: NColors.sage, width: 1.6),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(NRadius.md),
        borderSide: BorderSide(color: NColors.danger),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: NColors.surfaceAlt,
      selectedColor: NColors.sageSoft,
      side: const BorderSide(color: NColors.line),
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: NColors.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
