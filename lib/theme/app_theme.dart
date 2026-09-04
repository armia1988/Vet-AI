import 'package:flutter/material.dart';

class VetColors {
  static const background = Color(0xFF181D21);
  static const surface = Color(0xFF21282D);
  static const surface2 = Color(0xFF2A3338);
  static const border = Color(0xFF3C484E);
  static const primary = Color(0xFF8EB9AF);
  static const primaryDark = Color(0xFF698E86);
  static const text = Color(0xFFE3E8E6);
  static const muted = Color(0xFFACB6B3);
  static const red = Color(0xFFE17C82);
  static const orange = Color(0xFFD6A16F);
  static const yellow = Color(0xFFD4C27B);
  static const green = Color(0xFF8AB79D);
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
    iconTheme: const IconThemeData(size: 28, color: VetColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: VetColors.background,
      foregroundColor: VetColors.text,
      iconTheme: IconThemeData(size: 29, color: VetColors.text),
      actionsIconTheme: IconThemeData(size: 30, color: VetColors.text),
      titleTextStyle: TextStyle(color: VetColors.text, fontSize: 22, fontWeight: FontWeight.w800),
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
    listTileTheme: const ListTileThemeData(
      iconColor: VetColors.primary,
      textColor: VetColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VetColors.surface,
      prefixIconColor: VetColors.muted,
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
        borderSide: const BorderSide(color: VetColors.primary, width: 1.25),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        iconSize: const WidgetStatePropertyAll(27),
        foregroundColor: const WidgetStatePropertyAll(VetColors.text),
        side: const WidgetStatePropertyAll(BorderSide(color: VetColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFF394A45);
          return VetColors.surface;
        }),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 78,
      backgroundColor: Color(0xFF1D2327),
      indicatorColor: Color(0xFF394A45),
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 29)),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: const Color(0xFF16201D),
        minimumSize: const Size.fromHeight(56),
        iconSize: 29,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w850, fontSize: 16.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.text,
        minimumSize: const Size.fromHeight(52),
        iconSize: 28,
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
