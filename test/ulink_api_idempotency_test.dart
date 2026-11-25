import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/api_session_store.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';

void main() {
  test('repository rejects a flashed update without a valid AppType', () async {
    final repository = UlinkApiRepository(
      client: MockClient((_) async => http.Response('{"Result":1}', 200)),
      sessionStore: MemoryApiSessionStore(),
    );

    await expectLater(
      repository.updateUlinkProvisioning(
        companyId: 'company-1',
        ulinkId: 'stock-uid',
        flashed: true,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

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
      final bodies = <Map<String, dynamic>>[];
      var calls = 0;
      final repository = UlinkApiRepository(
        sessionStore: store,
        client: MockClient((request) async {
          calls += 1;
          keys.add(request.headers['idempotency-key']);
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
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
          appType: UlinkAppType.demo,
        ),
        throwsA(isA<UlinkApiException>()),
      );
      final pending = await store.readPending();
      expect(pending, isNotNull);
      expect(pending!.body['UlinkID'], 'stock-uid');
      expect(pending.body['AppType'], 'D');

      expect(await repository.retryPendingProvisioning(), isTrue);
      expect(keys, hasLength(2));
      expect(keys[0], isNotEmpty);
      expect(keys[1], keys[0]);
      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
      expect(bodies.first['AppType'], 'D');
      expect(await store.readPending(), isNull);
    },
  );

  test(
    'unflash pending request is reusable only in the same fresh login',
    () async {
      final session = ApiSession(
        userId: 'user-1',
        userRole: 'SI',
        userName: 'si',
        accessToken: 'access',
        accessTokenExpiresAtUtc: DateTime.utc(2030),
        refreshToken: 'refresh',
        refreshTokenExpiresAtUtc: DateTime.utc(2030),
        authenticationId: 'fresh-login-a',
      );
      final store = MemoryApiSessionStore()..value = session;
      final pending = PendingApiOperation(
        endpoint: '/api/v1/ulinks/UpdateUlinkProvisioning',
        body: <String, dynamic>{
          'UserId': 'user-1',
          'CompanyID': 'company-1',
          'UlinkID': 'ulink-1',
          'AppType': '',
          'IsFlashed': 0,
        },
        idempotencyKey: 'same-unflash-operation',
        userId: 'user-1',
        userRole: 'SI',
        createdAtUtc: DateTime.utc(2029),
        kind: ApiProvisioningKind.ulink,
        authenticationId: 'fresh-login-a',
        requiresFreshAuthentication: true,
      );
      store.pending = pending;
      final keys = <String?>[];
      final repository = UlinkApiRepository(
        sessionStore: store,
        client: MockClient((request) async {
          keys.add(request.headers['idempotency-key']);
          return http.Response('{"Result":1}', 200);
        }),
        now: () => DateTime.utc(2029),
      );
      expect(await repository.retryPendingProvisioning(), isTrue);
      expect(keys.single, pending.idempotencyKey);

      // A second password login must not replay that same pending request.
      store.pending = pending;
      store.value = session.withAuthenticationId('fresh-login-b');
      final secondLoginRepository = UlinkApiRepository(
        sessionStore: store,
        client: MockClient((_) async => http.Response('{"Result":1}', 200)),
        now: () => DateTime.utc(2029),
      );
      expect(await secondLoginRepository.retryPendingProvisioning(), isFalse);
    },
  );
}
