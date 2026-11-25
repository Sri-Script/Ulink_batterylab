import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/api_provisioning_policy.dart';

void main() {
  final si = ApiSession(
    userId: 'si-1',
    userRole: 'SI',
    userName: 'si',
    accessToken: 'a',
    refreshToken: 'r',
    accessTokenExpiresAtUtc: DateTime.utc(2030),
    refreshTokenExpiresAtUtc: DateTime.utc(2030),
  );
  final ca = ApiSession(
    userId: 'ca-1',
    userRole: 'CA',
    userName: 'ca',
    accessToken: 'a',
    refreshToken: 'r',
    accessTokenExpiresAtUtc: DateTime.utc(2030),
    refreshTokenExpiresAtUtc: DateTime.utc(2030),
  );

  test('SI cannot provision devices', () {
    expect(ApiProvisioningPolicy.canProvisionDevice(si), isFalse);
    expect(ApiProvisioningPolicy.canProvisionDevice(ca), isTrue);
  });

  test('destructive re-auth expires after five minutes', () {
    final authenticated = DateTime.utc(2030, 1, 1, 12);
    expect(
      ApiProvisioningPolicy.freshPasswordIsValid(
        authenticated,
        now: authenticated.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );
    expect(
      ApiProvisioningPolicy.freshPasswordIsValid(
        authenticated,
        now: authenticated.add(const Duration(minutes: 5, seconds: 1)),
      ),
      isFalse,
    );
    expect(
      ApiProvisioningPolicy.freshPasswordIsValid(null, now: authenticated),
      isFalse,
    );
  });

  test('Demo flash provisioning payload uses AppType D', () {
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.ulink,
      userId: 'u',
      companyId: 'c',
      ulinkId: 'l',
      isFlashed: 1,
      appType: UlinkAppType.demo,
    );
    expect(request.toJson(), <String, dynamic>{
      'UserId': 'u',
      'CompanyID': 'c',
      'UlinkID': 'l',
      'AppType': 'D',
      'IsFlashed': 1,
    });
  });

  test('Live flash provisioning payload uses AppType L', () {
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.ulink,
      userId: 'u',
      companyId: 'c',
      ulinkId: 'l',
      isFlashed: 1,
      appType: UlinkAppType.live,
    );
    expect(request.toJson()['AppType'], 'L');
  });

  test('unflash provisioning payload uses an empty AppType', () {
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.ulink,
      userId: 'u',
      companyId: 'c',
      ulinkId: 'l',
      isFlashed: 0,
    );
    expect(request.toJson()['AppType'], '');
  });

  test('flash provisioning payload rejects a missing AppType', () {
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.ulink,
      userId: 'u',
      companyId: 'c',
      ulinkId: 'l',
      isFlashed: 1,
    );
    expect(request.toJson, throwsStateError);
  });
}
