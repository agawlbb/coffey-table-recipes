import 'package:flutter/material.dart';

import 'account_panel.dart';

class CoffeyTableApp extends StatelessWidget {
  const CoffeyTableApp({
    super.key,
    this.authConfigured = false,
    this.initializationError,
  });
  final bool authConfigured;
  final String? initializationError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Coffey Table Recipes',
    debugShowCheckedModeBanner: false,
    builder: (context, child) =>
        MouseRegion(cursor: SystemMouseCursors.basic, child: child!),
    theme: ThemeData(
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff7f0e4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: MealPlanHome(
      authConfigured: authConfigured,
      initializationError: initializationError,
    ),
  );
}

class MealPlanHome extends StatelessWidget {
  const MealPlanHome({
    super.key,
    required this.authConfigured,
    this.initializationError,
  });
  final bool authConfigured;
  final String? initializationError;

  @override
  Widget build(BuildContext context) => AccountPanel(
    configured: authConfigured,
    initializationError: initializationError,
  );
}
