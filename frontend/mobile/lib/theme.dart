import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors from index.css
  static const Color bg = Color(0xFF0A0C0F);
  static const Color panel = Color(0xFF10141A);
  static const Color panelAlt = Color(0xFF0D1117);
  static const Color border = Color(0xFF1E2530);
  static const Color borderHover = Color(0xFF2A3444);
  static const Color accent = Color(0xFFF5A623);
  static const Color accentDim = Color(0xFFB87A1A);
  static const Color red = Color(0xFFE84040);
  static const Color green = Color(0xFF2FD67A);
  static const Color blue = Color(0xFF4A9EFF);
  static const Color text = Color(0xFFE8ECF0);
  static const Color muted = Color(0xFF5A6470);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: blue,
        surface: panel,
        surfaceContainerHighest: panelAlt,
        error: red,
      ),
      textTheme: GoogleFonts.jetBrainsMonoTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: muted),
        titleTextStyle: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 4.0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: muted,
          side: const BorderSide(color: border),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg,
        prefixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(6),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: accent),
          borderRadius: BorderRadius.circular(6),
        ),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
      ),
    );
  }
}
