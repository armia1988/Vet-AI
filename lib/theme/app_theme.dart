import 'package:flutter/material.dart';

class VetColors {
  static const background = Color(0xFFF3F7F8);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF0F5F5);
  static const surface3 = Color(0xFFE5F0EE);
  static const border = Color(0xFFD5E1E2);
  static const primary = Color(0xFF3C9787);
  static const primaryDark = Color(0xFF2E756A);
  static const text = Color(0xFF17242A);
  static const muted = Color(0xFF637178);
  static const red = Color(0xFFD94E5A);
  static const orange = Color(0xFFE58B3D);
  static const yellow = Color(0xFFC49A28);
  static const green = Color(0xFF48A56D);
  static const blue = Color(0xFF397FC3);
  static const purple = Color(0xFF8461C5);
  static const history = Color(0xFFB1842D);
  static const softRed = Color(0xFFFFEAEC);
  static const softOrange = Color(0xFFFFF0E3);
  static const softBlue = Color(0xFFEAF3FC);
  static const softPurple = Color(0xFFF0EBFA);
  static const softGreen = Color(0xFFE9F6EE);
}

ThemeData buildVetTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VetColors.primary,
    brightness: Brightness.light,
    surface: VetColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: VetColors.background,
    colorScheme: scheme.copyWith(
      primary: VetColors.primary,
      onPrimary: Colors.white,
      secondary: VetColors.blue,
      surface: VetColors.surface,
      onSurface: VetColors.text,
      error: VetColors.red,
    ),
    dividerColor: VetColors.border,
    iconTheme: const IconThemeData(size: 29, color: VetColors.text),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: VetColors.text,
      displayColor: VetColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VetColors.background,
      foregroundColor: VetColors.text,
      iconTheme: IconThemeData(size: 30, color: VetColors.text),
      actionsIconTheme: IconThemeData(size: 31, color: VetColors.text),
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
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VetColors.surface,
      prefixIconColor: VetColors.primary,
      hintStyle: const TextStyle(color: VetColors.muted),
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
        borderSide: const BorderSide(color: VetColors.primary, width: 1.6),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        iconSize: const WidgetStatePropertyAll(28),
        foregroundColor: const WidgetStatePropertyAll(VetColors.text),
        side: const WidgetStatePropertyAll(BorderSide(color: VetColors.border)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return VetColors.surface3;
          return VetColors.surface;
        }),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 80,
      backgroundColor: Color(0xFFFFFFFF),
      indicatorColor: Color(0xFFE6EFEE),
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 30)),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: VetColors.text)),
      elevation: 2,
      shadowColor: Color(0x18000000),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(58),
        iconSize: 30,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.text,
        backgroundColor: VetColors.surface,
        minimumSize: const Size.fromHeight(54),
        iconSize: 29,
        side: const BorderSide(color: VetColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: VetColors.surface,
      selectedColor: VetColors.surface3,
      side: const BorderSide(color: VetColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: const TextStyle(color: VetColors.text, fontWeight: FontWeight.w700),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VetColors.text,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
