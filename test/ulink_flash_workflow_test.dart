import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/ulink_api_models.dart';
import 'package:ulink_batterylab/services/ulink_api_repository.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';
import 'package:ulink_batterylab/services/ulink_flash_workflow.dart';

void main() {
  const serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  test('each flash stage maps to a safe user-facing failure message', () {
    expect(
      UlinkFlashStage.checkingApiConnection.failureMessage,
      'Flashing stopped while checking the API connection.',
    );
    expect(
      UlinkFlashStage.lookingForFactoryUlink.failureMessage,
      'Flashing stopped while looking for the factory U-Link.',
    );
    expect(
      UlinkFlashStage.connectingSecurely.failureMessage,
      'Flashing stopped while connecting to the U-Link.',
    );
    expect(
      UlinkFlashStage.preparingUlink.failureMessage,
      'Flashing stopped while preparing the U-Link.',
    );
    expect(
      UlinkFlashStage.writingUcode.failureMessage,
      'Flashing stopped while waiting for the UCode acknowledgement.',
    );
    expect(
      UlinkFlashStage.waitingForRestart.failureMessage,
      'Flashing stopped while waiting for the U-Link to restart.',
    );
    expect(
      UlinkFlashStage.verifyingAssignedUlink.failureMessage,
      'Flashing stopped while verifying the assigned U-Link.',
    );
    expect(
      UlinkFlashStage.updatingServerAssignment.failureMessage,
      'Flashing stopped while updating the server assignment.',
    );
    expect(
      UlinkFlashStage.completed.failureMessage,
      'Flashing stopped before completion.',
    );
  });

  test('factory matching accepts only the exact factory name', () {
    final nonFactoryName = <String>['RAW', 'ULINK'].join();
    expect(UlinkAdvertisementMatcher.isFactoryName('ULINK'), isTrue);
    expect(UlinkAdvertisementMatcher.isFactoryName(nonFactoryName), isFalse);
    expect(UlinkAdvertisementMatcher.isFactoryName('ULINK-X'), isFalse);
  });

  test('assigned matching is exact, with bare UCode compatibility only', () {
    const ucode = 'U20260718220700';
    final wrongPrefix = <String>['RAW', 'ULINK'].join();
    expect(
      UlinkAdvertisementMatcher.isAssignedName('ULINK-$ucode', ucode),
      isTrue,
    );
    expect(UlinkAdvertisementMatcher.isAssignedName(ucode, ucode), isTrue);
    expect(
      UlinkAdvertisementMatcher.isAssignedName('ULINK-${ucode}X', ucode),
      isFalse,
    );
    expect(
      UlinkAdvertisementMatcher.isAssignedName('$wrongPrefix-$ucode', ucode),
      isFalse,
    );
  });

  test('configured service UUID is required by the matcher', () {
    expect(
      UlinkAdvertisementMatcher.hasService([serviceUuid], serviceUuid),
      isTrue,
    );
    expect(
      UlinkAdvertisementMatcher.hasService([
        '12345678-1234-1234-1234-1234567890ab',
      ], serviceUuid),
      isFalse,
    );
  });

  test('SET_UCODE is LF terminated and split into 20-byte writes', () {
    const ucode = 'U20260718220700';
    final command = UlinkFlashProtocol.encodeSetUcode(ucode);
    expect(command, '{"cmd":"SET_UCODE","ucode":"$ucode"}\n');
    final chunks = UlinkBleWriteChunks.split(utf8.encode(command));
    expect(chunks.every((chunk) => chunk.length <= 20), isTrue);
    expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), command);
  });

  test('UCode validation rejects spaces and invalid lengths', () {
    expect(UlinkFlashProtocol.isValidUcode('A-1_x'), isTrue);
    expect(UlinkFlashProtocol.isValidUcode('has space'), isFalse);
    expect(UlinkFlashProtocol.isValidUcode(''), isFalse);
    expect(
      UlinkFlashProtocol.isValidUcode('abcdefghijklmnopqrstuvwx'),
      isFalse,
    );
  });

  test(
    'fragmented UCode acknowledgement is buffered and matched exactly',
    () async {
      const ucode = 'U20260718220700';
      final parser = UlinkSettingsParser();
      final frame = utf8.encode(
        '{"ok":true,"event":"ucode_written","ucode":"$ucode"}\n',
      );
      expect(parser.add(frame.sublist(0, 11)), isEmpty);
      final event = parser.add(frame.sublist(11)).single;
      final gate = UlinkUcodeResponseGate(ucode);
      gate.accept(event);
      await expectLater(gate.wait(const Duration(milliseconds: 1)), completes);
    },
  );

  test('wrong or negative UCode acknowledgements fail', () async {
    final wrong = UlinkUcodeResponseGate('Expected');
    wrong.accept(const UlinkUcodeWrittenEvent('Other'));
    await expectLater(
      wrong.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );

    final negative = UlinkUcodeResponseGate('Expected');
    negative.accept(const UlinkErrorEvent('write_once'));
    await expectLater(
      negative.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );
  });

  test(
    'API update follows positive ACK and assigned advertisement verification',
    () async {
      final log = <String>[];
      final ble = _FakeBle(log);
      final api = _FakeApi(log);
      final result = await UlinkFlashWorkflow(
        ble: ble,
        api: api,
      ).run(_selection(), onProgress: (_) {});

      expect(result.companyUlinks.single.uif, isTrue);
      expect(
        log.indexOf('api-update'),
        greaterThan(log.indexOf('ble-verify-assigned')),
      );
      expect(ble.writeCalls, 1);
      expect(ble.resetCalls, 0);
    },
  );

  test(
    'disconnect before positive acknowledgement reconciles but never updates API',
    () async {
      final log = <String>[];
      final ble = _FakeBle(log, writeFails: true);
      final api = _FakeApi(log);
      await expectLater(
        UlinkFlashWorkflow(
          ble: ble,
          api: api,
        ).run(_selection(), onProgress: (_) {}),
        throwsA(isA<UlinkFlashException>()),
      );
      expect(ble.writeCalls, 1);
      expect(log, contains('ble-verify-assigned'));
      expect(log, isNot(contains('api-update')));
    },
  );

  test(
    'preflight failure stops at checkingApiConnection before BLE work',
    () async {
      final log = <String>[];
      final stages = <UlinkFlashStage>[];
      final ble = _FakeBle(log);

      await expectLater(
        UlinkFlashWorkflow(
          ble: ble,
          api: _PreflightFailingApi(),
        ).run(_selection(), onProgress: stages.add),
        throwsA(
          isA<UlinkFlashException>()
              .having(
                (error) => error.stage,
                'stage',
                UlinkFlashStage.checkingApiConnection,
              )
              .having(
                (error) => error.message,
                'message',
                'Flashing stopped while checking the API connection.',
              ),
        ),
      );

      expect(stages, [UlinkFlashStage.checkingApiConnection]);
      expect(log, isNot(contains('ble-factory')));
      expect(log, isNot(contains('ble-connect')));
      expect(log, isNot(contains('ble-prepare')));
      expect(log, isNot(contains('ble-write')));
    },
  );

  test(
    'lost assignment response retries the same pending operation once',
    () async {
      final log = <String>[];
      final api = _FakeApi(log, loseFirstAssignmentResponse: true);
      await UlinkFlashWorkflow(
        ble: _FakeBle(log),
        api: api,
      ).run(_selection(), onProgress: (_) {});
      expect(api.updateCalls, 1);
      expect(api.retryCalls, 1);
      expect(log.indexOf('api-retry'), greaterThan(log.indexOf('api-update')));
    },
  );
}

UlinkFlashSelection _selection() => UlinkFlashSelection(
  session: ApiSession(
    userId: 'user-1',
    userRole: 'SI',
    userName: 'integrator',
    accessToken: 'access',
    accessTokenExpiresAtUtc: DateTime.utc(2030),
    refreshToken: 'refresh',
    refreshTokenExpiresAtUtc: DateTime.utc(2030),
  ),
  company: const ApiCompany(cid: 'company-1', cName: 'Factory One'),
  stockUlink: const ApiUlink(
    uid: 'stock-uid',
    uCode: 'U20260718220700',
    uif: false,
  ),
);

class _FakeBle implements UlinkFlashBleGateway {
  _FakeBle(this.log, {this.writeFails = false});
  final List<String> log;
  final bool writeFails;
  int writeCalls = 0;
  int resetCalls = 0;

  @override
  Future<void> connectFactory() async => log.add('ble-connect');
  @override
  Future<void> disconnect() async => log.add('ble-disconnect');
  @override
  Future<void> findFactory() async => log.add('ble-factory');
  @override
  Future<void> prepare() async => log.add('ble-prepare');
  @override
  Future<UlinkSettingsClient> reconnectForSettings() async {
    log.add('ble-reconnect');
    return _FakeSettingsClient();
  }

  @override
  Future<void> verifyAssigned(String ucode) async =>
      log.add('ble-verify-assigned');
  @override
  Future<void> waitForRestart() async => log.add('ble-restart');
  @override
  Future<void> writeUcode(String ucode) async {
    writeCalls += 1;
    log.add('ble-write');
    if (writeFails) throw const UlinkSettingsException('disconnected');
  }
}

class _FakeApi implements UlinkFlashApiGateway {
  _FakeApi(this.log, {this.loseFirstAssignmentResponse = false});
  final List<String> log;
  final bool loseFirstAssignmentResponse;
  int updateCalls = 0;
  int retryCalls = 0;

  @override
  Future<void> verifyPrerequisites(UlinkFlashSelection selection) async =>
      log.add('api-check');
  @override
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection) async {
    updateCalls += 1;
    log.add('api-update');
    if (loseFirstAssignmentResponse) {
      throw const UlinkApiException('lost response');
    }
    return [
      ApiUlink(
        uid: selection.stockUlink.uid,
        uCode: selection.ucode,
        uif: true,
      ),
    ];
  }

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) async {
    retryCalls += 1;
    log.add('api-retry');
    return [
      ApiUlink(
        uid: selection.stockUlink.uid,
        uCode: selection.ucode,
        uif: true,
      ),
    ];
  }
}

class _PreflightFailingApi implements UlinkFlashApiGateway {
  @override
  Future<void> verifyPrerequisites(UlinkFlashSelection selection) =>
      Future<void>.error(FormatException('unexpected API response'));

  @override
  Future<List<ApiUlink>> retryPendingAssignment(
    UlinkFlashSelection selection,
  ) => Future<List<ApiUlink>>.error(UnimplementedError());

  @override
  Future<List<ApiUlink>> updateAssignment(UlinkFlashSelection selection) =>
      Future<List<ApiUlink>>.error(UnimplementedError());
}

class _FakeSettingsClient implements UlinkSettingsClient {
  final StreamController<UlinkProtocolEvent> _events =
      StreamController<UlinkProtocolEvent>.broadcast();
  @override
  String get deviceName => 'ULINK-U20260718220700';
  @override
  Stream<UlinkProtocolEvent> get events => _events.stream;
  @override
  UlinkSettings? get latestSettings => null;
  @override
  Future<void> disconnect() async => _events.close();
  @override
  Future<UlinkSettings> refreshSettings() => throw UnimplementedError();
  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) async {}
}
