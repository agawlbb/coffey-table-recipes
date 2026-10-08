import 'package:coffey_table_recipes/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:coffey_table_recipes/src/firebase_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home connects to the real local recipe service', (tester) async {
    await app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('What’s for dinner?'), findsOneWidget);
    if (FirebaseConfig.options != null) {
      expect(find.text('Sign in with email'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(
        find.text(
          'Google sign-in setup is in progress. Your household will be ready here once it is connected.',
        ),
        findsNothing,
      );
    }
    await tester.scrollUntilVisible(
      find.byTooltip('Retry connection'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    for (var attempt = 0; attempt < 15; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Recipe service connected').evaluate().isNotEmpty) break;
    }
    expect(find.text('Recipe service connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
