import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF1B5E20); // Deep green — calming, educational
  static const _secondaryColor = Color(0xFF00897B); // Teal accent
  static const _surfaceColor = Color(0xFFF5F5F5);
  static const _errorColor = Color(0xFFD32F2F);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryColor,
      secondary: _secondaryColor,
      surface: _surfaceColor,
      error: _errorColor,
    ),
    textTheme: GoogleFonts.vazirmatnTextTheme().copyWith(
      // Use Vazirmatn for Persian text, falls back to Roboto for Latin
      displayLarge: GoogleFonts.vazirmatn(fontSize: 32, fontWeight: FontWeight.bold),
      headlineLarge: GoogleFonts.vazirmatn(fontSize: 28, fontWeight: FontWeight.bold),
      headlineMedium: GoogleFonts.vazirmatn(fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.vazirmatn(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.vazirmatn(fontSize: 16, fontWeight: FontWeight.w500),
      bodyLarge: GoogleFonts.vazirmatn(fontSize: 16),
      bodyMedium: GoogleFonts.vazirmatn(fontSize: 14),
      bodySmall: GoogleFonts.vazirmatn(fontSize: 12),
      labelLarge: GoogleFonts.vazirmatn(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      selectedIconTheme: IconThemeData(color: _primaryColor),
      unselectedIconTheme: IconThemeData(color: Colors.grey),
      labelType: NavigationRailLabelType.all,
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.dark,
      secondary: _secondaryColor,
    ),
    textTheme: GoogleFonts.vazirmatnTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  // CEFR level colors
  static Color cefrColor(String level) => switch (level) {
    'A1' => const Color(0xFF4CAF50),
    'A2' => const Color(0xFF8BC34A),
    'B1' => const Color(0xFFFFC107),
    'B2' => const Color(0xFFFF9800),
    'C1' => const Color(0xFFFF5722),
    'C2' => const Color(0xFF9C27B0),
    _ => Colors.grey,
  };
}
