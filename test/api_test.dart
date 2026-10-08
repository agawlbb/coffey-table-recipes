import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coffey_table_recipes/src/api.dart';

void main() {
  test('web API follows the page origin, including scheme and port', () {
    expect(
      resolveApiBaseUrl(
        isWeb: true,
        pageUrl: Uri.parse('http://172.20.10.2/CoffeyTableRecipes/app/'),
      ),
      'http://172.20.10.2/CoffeyTableRecipes/api/v1',
    );
    expect(
      resolveApiBaseUrl(
        isWeb: true,
        pageUrl: Uri.parse(
          'https://recipes.example:8443/CoffeyTableRecipes/app/',
        ),
      ),
      'https://recipes.example:8443/CoffeyTableRecipes/api/v1',
    );
  });
  test('explicit API override and Android emulator default are preserved', () {
    expect(
      resolveApiBaseUrl(isWeb: true, override: 'https://api.example/api/v1'),
      'https://api.example/api/v1',
    );
    expect(
      resolveApiBaseUrl(isWeb: false),
      'http://10.0.2.2/CoffeyTableRecipes/api/v1',
    );
  });
  test(
    'authenticated creation includes token and JSON without client user IDs',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer firebase-id-token');
          expect(request.headers['Content-Type'], 'application/json');
          expect(request.body, '{"name":"Our table","person_name":"Alice"}');
          return http.Response(
            '{"household":{"id":"1","name":"Our table","role":"owner"}}',
            201,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.request(
        '/households',
        'firebase-id-token',
        body: {'name': 'Our table', 'person_name': 'Alice'},
      );
      expect((result['household'] as Map)['role'], 'owner');
    },
  );
  test(
    'authorization errors retain their status for token refresh handling',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Please sign in again."}}',
            401,
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.request('/me', 'expired-token'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    },
  );
  test(
    'health uses the configured API URL and validates the response',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/health');
          return http.Response(
            '{"status":"ok","service":"Coffey Table Recipes"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      expect(await api.health(), 'Coffey Table Recipes');
    },
  );
  test('server failures do not report a healthy connection', () async {
    final api = RecipeApi(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    addTearDown(api.close);
    await expectLater(api.health(), throwsException);
  });
}
