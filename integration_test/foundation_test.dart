import 'package:coffey_table_recipes/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app starts without promotional home content', (tester) async {
    await app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text("What's for dinner?"), findsNothing);
    expect(find.text('GATHER. COOK. SHARE.'), findsNothing);
    expect(find.text('Recipe service connected'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
