import 'package:integration_test/integration_test.dart';
import '../test/recipe_browser_test.dart' as recipe_checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recipe_checks.main();
}
