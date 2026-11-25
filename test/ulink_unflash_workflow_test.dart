import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';
import 'package:ulink_batterylab/services/ulink_flash_workflow.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';
import 'package:ulink_batterylab/services/ulink_unflash_workflow.dart';

void main() {
  test('UNFLASH_UCODE is LF framed and split into 20-byte response writes', () {
    const ucode = 'U20260718220700';
    final command = UlinkFlashProtocol.encodeUnflashUcode(ucode);
    expect(command, '{"cmd":"UNFLASH_UCODE","ucode":"$ucode"}\n');
    final chunks = UlinkBleWriteChunks.split(utf8.encode(command));
    expect(chunks.every((chunk) => chunk.length <= 20), isTrue);
    expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), command);
  });

  test('only an exact selected ucode_cleared ACK completes unflash', () async {
    const ucode = 'U20260718220700';
    final parser = UlinkSettingsParser();
    final event = parser
        .add(
          utf8.encode('{"ok":true,"event":"ucode_cleared","ucode":"$ucode"}\n'),
        )
        .single;
    final gate = UlinkUnflashResponseGate(ucode);
    gate.accept(event);
    await expectLater(gate.wait(const Duration(milliseconds: 1)), completes);

    final mismatch = UlinkUnflashResponseGate(ucode);
    mismatch.accept(const UlinkUcodeClearedEvent('other'));
    await expectLater(
      mismatch.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );
  });

  test('negative firmware ACK never succeeds', () async {
    final gate = UlinkUnflashResponseGate('Expected');
    gate.accept(const UlinkErrorEvent('NETWORK_BUSY'));
    await expectLater(
      gate.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );
  });

  test('assigned scan and post-reset verification names stay exact', () {
    const ucode = 'U20260718220700';
    expect(
      UlinkAdvertisementMatcher.isAssignedName('ULINK-$ucode', ucode),
      isTrue,
    );
    expect(UlinkAdvertisementMatcher.isAssignedName(ucode, ucode), isTrue);
    expect(
      UlinkAdvertisementMatcher.isAssignedName('ULINK-${ucode}x', ucode),
      isFalse,
    );
    expect(UlinkAdvertisementMatcher.isFactoryName('ULINK'), isTrue);
    expect(UlinkAdvertisementMatcher.isFactoryName('ULINK-$ucode'), isFalse);
  });

  test(
    'unflash API update follows positive ACK and exact ULINK verification',
    () async {
      final log = <String>[];
      final api = _FakeApi(log);
      final result = await UlinkUnflashWorkflow(
        ble: _FakeBle(log),
        api: api,
      ).run(_selection(), onProgress: (_) {});
      expect(result.single.uif, isFalse);
      expect(
        log.indexOf('api-update'),
        greaterThan(log.indexOf('ble-verify-ulink')),
      );
      expect(log.where((item) => item == 'ble-clear'), hasLength(1));
    },
  );

  test('fresh-login preflight failure prevents all BLE work', () async {
    final log = <String>[];
    await expectLater(
      UlinkUnflashWorkflow(
        ble: _FakeBle(log),
        api: _FakeApi(log, rejectPreflight: true),
      ).run(_selection(), onProgress: (_) {}),
      throwsA(isA<UlinkUnflashException>()),
    );
    expect(log, isNot(contains('ble-ready')));
    expect(log, isNot(contains('ble-find-assigned')));
  });

  test(
    'no positive clear ACK means no server reset and no command retry',
    () async {
      final log = <String>[];
      final ble = _FakeBle(log, clearFails: true);
      await expectLater(
        UlinkUnflashWorkflow(
          ble: ble,
          api: _FakeApi(log),
        ).run(_selection(), onProgress: (_) {}),
        throwsA(isA<UlinkUnflashException>()),
      );
      expect(log, isNot(contains('api-update')));
      expect(log.where((item) => item == 'ble-clear'), hasLength(1));
      expect(log, isNot(contains('ble-verify-ulink')));
    },
  );
}

UlinkUnflashSelection _selection() => UlinkUnflashSelection(
  session: ApiSession(
    userId: 'user-1',
    userRole: 'SI',
    userName: 'si',
    accessToken: 'access',
    accessTokenExpiresAtUtc: DateTime.utc(2030),
    refreshToken: 'refresh',
    refreshTokenExpiresAtUtc: DateTime.utc(2030),
    authenticationId: 'fresh-login',
  ),
  company: const ApiCompany(cid: 'company-1', cName: 'Factory One'),
  ulink: const ApiUlink(uid: 'ulink-1', uCode: 'U20260718220700', uif: true),
);

class _FakeBle implements UlinkUnflashBleGateway {
  _FakeBle(this.log, {this.clearFails = false});
  final List<String> log;
  final bool clearFails;
  @override
  Future<void> clearUcode(String ucode) async {
    log.add('ble-clear');
    if (clearFails) throw const UlinkSettingsException('NETWORK_BUSY');
  }

  @override
  Future<void> connectAssigned() async => log.add('ble-connect');
  @override
  Future<void> disconnect() async => log.add('ble-disconnect');
  @override
  Future<void> ensureBluetoothReady() async => log.add('ble-ready');
  @override
  Future<void> findAssigned(String ucode) async => log.add('ble-find-assigned');
  @override
  Future<void> prepare() async => log.add('ble-prepare');
  @override
  Future<void> verifyFactory() async => log.add('ble-verify-ulink');
  @override
  Future<void> waitForRestart() async => log.add('ble-restart');
}

class _FakeApi implements UlinkUnflashApiGateway {
  _FakeApi(this.log, {this.rejectPreflight = false});
  final List<String> log;
  final bool rejectPreflight;
  @override
  Future<ApiLoginResult> authenticateFreshly({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyPrerequisites(UlinkUnflashSelection selection) async {
    if (rejectPreflight) {
      throw const UlinkUnflashException('fresh login required');
    }
  }

  @override
  Future<List<ApiUlink>> updateCleared(UlinkUnflashSelection selection) async {
    log.add('api-update');
    return [
      ApiUlink(uid: selection.ulink.uid, uCode: selection.ucode, uif: false),
    ];
  }

  @override
  Future<List<ApiUlink>> retryPendingUpdate(UlinkUnflashSelection selection) =>
      throw UnimplementedError();
}
