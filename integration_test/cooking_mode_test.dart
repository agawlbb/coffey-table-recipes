import 'package:integration_test/integration_test.dart';
import '../test/cooking_mode_test.dart' as cooking_checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  cooking_checks.main();
}
