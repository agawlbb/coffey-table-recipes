import 'package:flutter/material.dart';

ThemeData previewTheme() => ThemeData(
  useMaterial3: true,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: const Color(0xff465334),
        surface: const Color(0xfffff9ee),
      ).copyWith(
        primary: const Color(0xff465334),
        onPrimary: const Color(0xfffff9ee),
        secondary: const Color(0xffa55d24),
        onSurface: const Color(0xff3b2416),
      ),
  scaffoldBackgroundColor: const Color(0xfff5eddf),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xfff5eddf),
    foregroundColor: Color(0xff465334),
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: const Color(0xfffff9ee),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xffdfd1bb)),
    ),
  ),
);
