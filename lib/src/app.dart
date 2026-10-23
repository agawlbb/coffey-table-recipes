import 'sync_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'account_panel.dart';
import 'shared_recipe_link.dart';
import 'administration.dart';
import 'touch_capability.dart';
import 'offline_recipes.dart';
import 'active_timers.dart';

final _appNavigatorKey = GlobalKey<NavigatorState>();

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
    navigatorKey: _appNavigatorKey,
    scaffoldMessengerKey: syncMessengerKey,
    onGenerateRoute: (settings) {
      final id = recipeIdFromLink(settings.name ?? '');
      return id == null
          ? null
          : MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => SharedRecipeLink(recipeId: id),
            );
    },
    routes: {
      '/administration': (_) =>
          AuthenticatedAdministration(configured: authConfigured),
    },
    debugShowCheckedModeBanner: false,
    scrollBehavior: const AppScrollBehavior(),
    builder: (context, child) => MouseRegion(
      cursor: SystemMouseCursors.basic,
      // These controls are siblings of Navigator, so they need their own
      // overlay for tooltips (including the keyboard and offline controls).
      child: Overlay.wrap(
        child: Stack(
          children: [
            ActiveTimerHost(navigatorKey: _appNavigatorKey, child: child!),
            if (MediaQuery.viewInsetsOf(context).bottom > 0)
              Positioned(
                right: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
                child: Material(
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    tooltip: 'Dismiss keyboard',
                    icon: const Icon(Icons.keyboard_hide),
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
              ),
            if (mobileOfflineEnabled)
              Positioned(
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: const IgnorePointer(child: OfflineIndicator()),
                ),
              ),
          ],
        ),
      ),
    ),
    theme: ThemeData(
      useMaterial3: true,
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Color(0xff858c79)),
        trackColor: WidgetStatePropertyAll(Color(0xffe3dacb)),
        trackBorderColor: WidgetStatePropertyAll(Color(0xffc9bda9)),
      ),
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

/// Each scrollable receives its own controller from the scroll behavior.
/// This also covers horizontal photo strips and independent settings lists.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior({this.webScrollbars = kIsWeb, this.touchCapable});
  final bool webScrollbars;
  final bool? touchCapable;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (!webScrollbars) return super.buildScrollbar(context, child, details);
    if (touchCapable ?? deviceSupportsTouch()) return child;
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      trackVisibility: false,
      interactive: true,
      thickness: 7,
      radius: const Radius.circular(4),
      child: child,
    );
  }
}
