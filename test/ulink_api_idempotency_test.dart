import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/api_session_store.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';

void main() {
  test(
    'lost U-Link assignment response retries with the persisted idempotency key',
    () async {
      final store = MemoryApiSessionStore()
        ..value = ApiSession(
          userId: 'user-1',
          userRole: 'SI',
          userName: 'si',
          accessToken: 'access',
          accessTokenExpiresAtUtc: DateTime.utc(2030),
          refreshToken: 'refresh',
          refreshTokenExpiresAtUtc: DateTime.utc(2030),
        );
      final keys = <String?>[];
      var calls = 0;
      final repository = UlinkApiRepository(
        sessionStore: store,
        client: MockClient((request) async {
          calls += 1;
          keys.add(request.headers['idempotency-key']);
          if (calls == 1) throw http.ClientException('connection lost');
          return http.Response('{"Result":1}', 200);
        }),
        now: () => DateTime.utc(2029),
      );

      await expectLater(
        repository.updateUlinkProvisioning(
          companyId: 'company-1',
          ulinkId: 'stock-uid',
          flashed: true,
        ),
        throwsA(isA<UlinkApiException>()),
      );
      final pending = await store.readPending();
      expect(pending, isNotNull);
      expect(pending!.body['UlinkID'], 'stock-uid');

      expect(await repository.retryPendingProvisioning(), isTrue);
      expect(keys, hasLength(2));
      expect(keys[0], isNotEmpty);
      expect(keys[1], keys[0]);
      expect(await store.readPending(), isNull);
    },
  );
}
