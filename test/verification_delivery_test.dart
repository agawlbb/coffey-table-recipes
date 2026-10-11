import 'dart:convert';

import 'package:coffey_table_recipes/src/api.dart';
import 'package:coffey_table_recipes/src/invitation_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'home_design_test.dart' show TestUser;

class DeliveryUser extends TestUser {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
}

void main() {
  test(
    'verification posts authenticated request with no client-selected email',
    () async {
      final api = RecipeApi(
        baseUrl: 'https://example.test/api/v1',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/me/verification-email');
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), isEmpty);
          return http.Response('{"sent":true}', 200);
        }),
      );
      await InvitationVerification.sendHosted(DeliveryUser(), api: api);
      api.close();
    },
  );
  test('SMTP failure is propagated instead of reporting email sent', () async {
    final api = RecipeApi(
      baseUrl: 'https://example.test/api/v1',
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"message":"The verification email could not be sent."}}',
          503,
        ),
      ),
    );
    await expectLater(
      InvitationVerification.sendHosted(DeliveryUser(), api: api),
      throwsA(
        isA<ApiException>().having((error) => error.status, 'status', 503),
      ),
    );
    api.close();
  });
}
