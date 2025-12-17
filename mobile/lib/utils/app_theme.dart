import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Private constructor to avoid instantiation
  AppTheme._();

  // --- COLORS ---
  static const Color neonGreen = Color(0xFF00FF9D);
  static const Color neonPurple = Color(0xFFBD00FF);
  static const Color neonPink = Color(0xFFFF0055);
  static const Color neonBlue = Color(0xFF00C2FF);
  static const Color surfaceDark = Color(0xFF111111);
  static const Color white10 = Colors.white10;
  static const Color white38 = Colors.white38;

  // --- TEXT STYLES ---
  static TextStyle get headerLarge => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.5,
        color: Colors.white,
      );

  static TextStyle get labelSmall => GoogleFonts.inter(
        fontWeight: FontWeight.bold,
        color: Colors.white24,
        letterSpacing: 2,
        fontSize: 10,
      );

  static TextStyle get valueLarge => GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      );

  static TextStyle get subText => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.bold, // Often used for small labels
        color: Colors.white54,
      );

  // --- THEME DATA ---
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      colorScheme: const ColorScheme.dark(
        primary: neonGreen,
        secondary: neonPurple,
        error: neonPink,
        surface: surfaceDark,
      ),
    );
  }
}
