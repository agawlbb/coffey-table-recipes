import 'package:flutter/foundation.dart';
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
    builder: (context, child) => MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: child!,
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff294d3b),
        surface: const Color(0xfffffbf3),
      ),
      scaffoldBackgroundColor: const Color(0xfff6f0e5),
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
  final _api = RecipeApi(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: kIsWeb
          ? 'http://localhost/CoffeyTableRecipes/api/v1'
          : 'http://10.0.2.2/CoffeyTableRecipes/api/v1',
    ),
  );

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
    appBar: AppBar(title: const Text('Coffey Table Recipes')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'A little planning. A good dinner.',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'What’s for dinner?',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            AccountPanel(
              configured: widget.authConfigured,
              initializationError: widget.initializationError,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.soup_kitchen_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Your table starts here',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your dinner plans and recipes will appear here as your collection grows.',
                    ),
                    const SizedBox(height: 16),
                    const Text('No meals have been loaded yet.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Foundation checkpoint',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
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
                          ? 'Check that Apache is running, then retry.'
                          : 'Coffey Table Recipes API',
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
