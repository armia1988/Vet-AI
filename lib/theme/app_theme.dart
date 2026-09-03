import 'package:flutter/material.dart';

class VetColors {
  static const background = Color(0xFF07181B);
  static const surface = Color(0xFF0C2427);
  static const surface2 = Color(0xFF123237);
  static const primary = Color(0xFF39E6B1);
  static const primaryDark = Color(0xFF159B79);
  static const text = Color(0xFFF4FBF9);
  static const muted = Color(0xFF9DB8B2);
  static const red = Color(0xFFFF4D5D);
  static const orange = Color(0xFFFF9A3D);
  static const yellow = Color(0xFFF8D14B);
  static const green = Color(0xFF45D483);
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
      secondary: VetColors.primaryDark,
      surface: VetColors.surface,
      error: VetColors.red,
    ),
    cardTheme: CardThemeData(
      color: VetColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VetColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF214348)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VetColors.primary, width: 1.4),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF091E21),
      indicatorColor: Color(0x3339E6B1),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: const Color(0xFF03231A),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
  );
}
