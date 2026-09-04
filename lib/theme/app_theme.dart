import 'package:flutter/material.dart';

class VetColors {
  static const background = Color(0xFF151A1E);
  static const surface = Color(0xFF1D2429);
  static const surface2 = Color(0xFF263036);
  static const border = Color(0xFF38444A);
  static const primary = Color(0xFF86B5AA);
  static const primaryDark = Color(0xFF5F877E);
  static const text = Color(0xFFE7ECEA);
  static const muted = Color(0xFFAAB4B1);
  static const red = Color(0xFFE2787E);
  static const orange = Color(0xFFD9A36E);
  static const yellow = Color(0xFFD8C579);
  static const green = Color(0xFF87B89B);
}

ThemeData buildVetTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VetColors.primary,
    brightness: Brightness.dark,
    surface: VetColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VetColors.background,
    colorScheme: scheme.copyWith(
      primary: VetColors.primary,
      onPrimary: const Color(0xFF18221F),
      secondary: VetColors.primaryDark,
      surface: VetColors.surface,
      onSurface: VetColors.text,
      error: VetColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VetColors.background,
      foregroundColor: VetColors.text,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: VetColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: VetColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VetColors.surface,
      labelStyle: const TextStyle(color: VetColors.muted),
      floatingLabelStyle: const TextStyle(color: VetColors.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: VetColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: VetColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: VetColors.primary, width: 1.2),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(VetColors.text),
        side: const WidgetStatePropertyAll(BorderSide(color: VetColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFF35453F);
          return VetColors.surface;
        }),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF1A2024),
      indicatorColor: Color(0xFF344740),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: const Color(0xFF16201D),
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.text,
        side: const BorderSide(color: VetColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VetColors.surface2,
      contentTextStyle: TextStyle(color: VetColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
