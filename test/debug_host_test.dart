import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/debug_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugApiOverride.value = null;
  });
  tearDown(() => debugApiOverride.value = null);

  testWidgets('debug address validates, persists and routes both API calls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DebugHostPanel(currentUrl: defaultApiBaseUrl)),
      ),
    );
    await tester.tap(find.text('Debug: server address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a URL');
    await tester.tap(find.text('Save and apply'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a full http:// or https:// API URL.'),
      findsOneWidget,
    );
    expect(debugApiOverride.value, isNull);

    await tester.enterText(
      find.byType(TextField),
      ' http://192.168.1.42:8080/CoffeyTableRecipes/api/v1/ ',
    );
    await tester.tap(find.text('Save and apply'));
    await tester.pumpAndSettle();
    const expected = 'http://192.168.1.42:8080/CoffeyTableRecipes/api/v1';
    expect(apiBaseUrl, expected);
    debugApiOverride.value = null;
    await loadDebugApiOverride();
    expect(apiBaseUrl, expected);

    final visited = <String>[];
    final api = RecipeApi(
      baseUrl: apiBaseUrl,
      client: MockClient((request) async {
        visited.add(request.url.toString());
        return http.Response(
          request.url.path.endsWith('/health')
              ? '{"status":"ok","service":"Coffey Table Recipes"}'
              : '{"households":[]}',
          200,
        );
      }),
    );
    addTearDown(api.close);
    await api.health();
    await api.request('/households', 'test-token');
    expect(visited, ['$expected/health', '$expected/households']);
  });

  test('debug address rejects credentials and URL query or fragment', () {
    for (final value in [
      'http://user:password@example.test/api/v1',
      'https://example.test/api/v1?key=value',
      'https://example.test/api/v1#fragment',
      'file:///tmp/api',
    ]) {
      expect(normalizeDebugApiUrl(value), isNull);
    }
  });
}
