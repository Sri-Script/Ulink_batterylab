import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/api_session_store.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';

void main() {
  test('GetUlinks reads the documented root-level Ulinks array', () async {
    final repository = _repository((request) async {
      expect(request.url.path, '/api/v1/ulinks/GetUlinks');
      return http.Response(
        '{"Result":1,"Message":"ok","Ulinks":[{"UID":11,"UCode":"U20260918173000"}]}',
        200,
      );
    });

    final ulinks = await repository.getCompanyUlinks(
      userId: 'user-1',
      companyId: '4',
    );

    expect(ulinks, hasLength(1));
    expect(ulinks.single.uid, '11');
    expect(ulinks.single.uCode, 'U20260918173000');
  });

  test('GetDevices reads the documented root-level Devices array', () async {
    final repository = _repository((request) async {
      expect(request.url.path, '/api/v1/devices/GetDevices');
      return http.Response(
        '{"Result":1,"Message":"ok","Devices":[{"DID":22,"DCode":"D-22"}]}',
        200,
      );
    });

    final devices = await repository.getDevices(
      userId: 'user-1',
      companyId: '4',
      ulinkId: '11',
    );

    expect(devices, hasLength(1));
    expect(devices.single.did, '22');
    expect(devices.single.dCode, 'D-22');
  });

  test(
    'GetUlinks and GetDevices support nested Data compatibility lists',
    () async {
      final repository = _repository((request) async {
        if (request.url.path.endsWith('/GetUlinks')) {
          return http.Response(
            '{"Result":1,"Data":{"Ulinks":[{"UID":"11","UCode":"U-11"}]}}',
            200,
          );
        }
        return http.Response(
          '{"Result":1,"Data":{"Devices":[{"DID":"22","DCode":"D-22"}]}}',
          200,
        );
      });

      final ulinks = await repository.getCompanyUlinks(
        userId: 'user-1',
        companyId: '4',
      );
      final devices = await repository.getDevices(
        userId: 'user-1',
        companyId: '4',
        ulinkId: '11',
      );

      expect(ulinks.single.uid, '11');
      expect(devices.single.did, '22');
    },
  );

  test('an empty Ulinks array is a successful API preflight', () async {
    final repository = _repository((request) async {
      expect(request.url.path, '/api/v1/ulinks/GetUlinks');
      expect(request.url.queryParameters, {
        'UserId': 'user-1',
        'CompanyID': '4',
      });
      return http.Response('{"Result":1,"Ulinks":[]}', 200);
    });

    await expectLater(
      repository.verifyUlinkApiReachability(userId: 'user-1', companyId: '4'),
      completes,
    );
  });

  test(
    'a malformed read response becomes UlinkApiException, not TypeError',
    () async {
      final repository = _repository(
        (_) async => http.Response('{"Result":1,"Ulinks":{}}', 200),
      );

      await expectLater(
        repository.getCompanyUlinks(userId: 'user-1', companyId: '4'),
        throwsA(
          isA<UlinkApiException>().having(
            (error) => error.message,
            'message',
            'The API returned an invalid Ulinks response.',
          ),
        ),
      );
    },
  );
}

UlinkApiRepository _repository(
  Future<http.Response> Function(http.Request request) callback,
) {
  final store = MemoryApiSessionStore()
    ..value = ApiSession(
      userId: 'user-1',
      userRole: 'SI',
      userName: 'integrator',
      accessToken: 'access-token',
      accessTokenExpiresAtUtc: DateTime.utc(2030),
      refreshToken: 'refresh-token',
      refreshTokenExpiresAtUtc: DateTime.utc(2030),
    );
  return UlinkApiRepository(
    client: MockClient(callback),
    sessionStore: store,
    now: () => DateTime.utc(2029),
  );
}
