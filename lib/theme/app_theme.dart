import 'package:flutter/material.dart';

class VetColors {
  static const background = Color(0xFF20282D);
  static const surface = Color(0xFF2B353B);
  static const surface2 = Color(0xFF354249);
  static const surface3 = Color(0xFF3E4C53);
  static const border = Color(0xFF526168);
  static const primary = Color(0xFF9BC9BD);
  static const primaryDark = Color(0xFF78A79B);
  static const text = Color(0xFFF2F5F4);
  static const muted = Color(0xFFC4CECB);
  static const red = Color(0xFFF08A91);
  static const orange = Color(0xFFF0B275);
  static const yellow = Color(0xFFE4CF7F);
  static const green = Color(0xFF9AC6A9);
  static const blue = Color(0xFF83B7E8);
  static const purple = Color(0xFFB7A2E8);
  static const history = Color(0xFFD9C58A);
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
      onPrimary: const Color(0xFF16211E),
      secondary: VetColors.blue,
      surface: VetColors.surface,
      onSurface: VetColors.text,
      error: VetColors.red,
    ),
    dividerColor: VetColors.border,
    iconTheme: const IconThemeData(size: 29, color: VetColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: VetColors.background,
      foregroundColor: VetColors.text,
      iconTheme: IconThemeData(size: 30, color: VetColors.text),
      actionsIconTheme: IconThemeData(size: 31, color: VetColors.text),
      titleTextStyle: TextStyle(color: VetColors.text, fontSize: 22, fontWeight: FontWeight.w850),
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
      fillColor: VetColors.surface2,
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
        borderSide: const BorderSide(color: VetColors.primary, width: 1.4),
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
      backgroundColor: Color(0xFF273137),
      indicatorColor: Color(0xFF405057),
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: 30)),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w650)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: VetColors.primary,
        foregroundColor: const Color(0xFF16201D),
        minimumSize: const Size.fromHeight(58),
        iconSize: 30,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w850, fontSize: 16.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VetColors.text,
        minimumSize: const Size.fromHeight(54),
        iconSize: 29,
        side: const BorderSide(color: VetColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VetColors.surface3,
      contentTextStyle: TextStyle(color: VetColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
