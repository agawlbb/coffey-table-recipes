import 'package:flutter/material.dart';

import 'api.dart';
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

class MealPlanHome extends StatefulWidget {
  const MealPlanHome({
    super.key,
    required this.authConfigured,
    this.initializationError,
  });
  final bool authConfigured;
  final String? initializationError;
  @override
  State<MealPlanHome> createState() => _MealPlanHomeState();
}

class _MealPlanHomeState extends State<MealPlanHome> {
  late Future<String> _health;
  final _api = RecipeApi(baseUrl: apiBaseUrl);

  @override
  void initState() {
    super.initState();
    _health = _api.health();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_dining_outlined),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Coffey Table',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const TableWelcomeBanner(),
            const SizedBox(height: 24),
            AccountPanel(
              configured: widget.authConfigured,
              initializationError: widget.initializationError,
            ),
            const SizedBox(height: 24),
            FutureBuilder<String>(
              future: _health,
              builder: (context, snapshot) {
                final waiting =
                    snapshot.connectionState != ConnectionState.done;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      waiting
                          ? Icons.sync
                          : snapshot.hasError
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_done_outlined,
                    ),
                    title: Text(
                      waiting
                          ? 'Connecting to the recipe service…'
                          : snapshot.hasError
                          ? 'Recipe service unavailable'
                          : 'Recipe service connected',
                    ),
                    subtitle: Text(
                      snapshot.hasError
                          ? 'Please try connecting again.'
                          : 'Ready for your next good dinner',
                    ),
                    trailing: IconButton(
                      tooltip: 'Retry connection',
                      onPressed: waiting
                          ? null
                          : () => setState(() {
                              _health = _api.health();
                            }),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Keeps the complete brand artwork visible at both phone and desktop widths.
class TableWelcomeBanner extends StatelessWidget {
  const TableWelcomeBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xfffff9ee),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xffdfd1bb)),
    ),
    padding: const EdgeInsets.all(24),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final artwork = ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            'assets/images/coffey_table.jpg',
            width: wide ? 250 : 180,
            height: wide ? 250 : 180,
            fit: BoxFit.contain,
            semanticLabel:
                'Coffey Table Recipes cookbook, coffee, and fresh herbs',
          ),
        );
        final welcome = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'GATHER. COOK. SHARE.',
              style: TextStyle(
                color: Color(0xff465334),
                letterSpacing: 2,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "What's for dinner?",
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: const Color(0xff3b2416),
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            Container(width: 48, height: 3, color: const Color(0xffa55d24)),
            const SizedBox(height: 16),
            const Text(
              'A little planning. A good dinner.',
              style: TextStyle(
                color: Color(0xff665442),
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  Expanded(child: welcome),
                  const SizedBox(width: 32),
                  artwork,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: artwork),
                  const SizedBox(height: 24),
                  welcome,
                ],
              );
      },
    ),
  );
}
