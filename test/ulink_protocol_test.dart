import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/services/ulink_ble_protocol_config.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';

void main() {
  const settingsFrame =
      '{"ok":true,"event":"settings","ssid":"PlantWiFi","password":"secret","apn":"internet","mode":"WIFI"}\n';

  test('validates Rev4 setting values and rejects control characters', () {
    expect(
      UlinkSettingsProtocol.validate(UlinkSettingsKey.ssid, ''),
      isNotNull,
    );
    expect(
      UlinkSettingsProtocol.validate(
        UlinkSettingsKey.ssid,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isNotNull,
    );
    expect(
      UlinkSettingsProtocol.validate(
        UlinkSettingsKey.password,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isNull,
    );
    expect(
      UlinkSettingsProtocol.validate(UlinkSettingsKey.apn, 'line\nbreak'),
      isNotNull,
    );
    expect(
      UlinkSettingsProtocol.validate(UlinkSettingsKey.mode, 'LTE'),
      isNotNull,
    );
    expect(
      UlinkSettingsProtocol.validate(UlinkSettingsKey.mode, 'GSM'),
      isNull,
    );
  });

  test('encodes the exact GET_SETTINGS and SET commands with newlines', () {
    expect(UlinkSettingsProtocol.getSettingsCommand, 'GET_SETTINGS\n');
    expect(
      UlinkSettingsProtocol.encodeSet(UlinkSettingsKey.ssid, 'PlantWiFi'),
      '{"cmd":"SET","key":"ssid","value":"PlantWiFi"}\n',
    );
    expect(
      UlinkSettingsProtocol.encodeSet(UlinkSettingsKey.password, 'pw'),
      '{"cmd":"SET","key":"password","value":"pw"}\n',
    );
    expect(
      UlinkSettingsProtocol.encodeSet(UlinkSettingsKey.apn, 'internet'),
      '{"cmd":"SET","key":"apn","value":"internet"}\n',
    );
    expect(
      UlinkSettingsProtocol.encodeSet(UlinkSettingsKey.mode, 'GSM'),
      '{"cmd":"SET","key":"mode","value":"GSM"}\n',
    );
  });

  test('parses fragmented and multiple settings notification frames', () {
    final parser = UlinkSettingsParser();
    final bytes = utf8.encode('$settingsFrame$settingsFrame');
    expect(parser.add(bytes.sublist(0, 17)), isEmpty);
    final events = parser.add(bytes.sublist(17));
    expect(events, hasLength(2));
    final first = events.first as UlinkSettingsEvent;
    expect(first.settings.ssid, 'PlantWiFi');
    expect(first.settings.apn, 'internet');
    expect(first.settings.mode, 'WIFI');
  });

  test('matching saved reply succeeds', () async {
    final gate = UlinkSetResponseGate(UlinkSettingsKey.ssid);
    gate.accept(const UlinkSetReplyEvent(ok: true, key: 'ssid', saved: true));
    await expectLater(gate.wait(const Duration(milliseconds: 1)), completes);
  });

  test('error, timeout, malformed JSON, and wrong key replies fail', () async {
    final error = UlinkSetResponseGate(UlinkSettingsKey.ssid);
    error.accept(const UlinkSetReplyEvent(ok: false));
    await expectLater(
      error.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );

    final malformed = UlinkSetResponseGate(UlinkSettingsKey.ssid);
    malformed.accept(const UlinkMalformedEvent());
    await expectLater(
      malformed.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );

    final wrongKey = UlinkSetResponseGate(UlinkSettingsKey.ssid);
    wrongKey.accept(
      const UlinkSetReplyEvent(ok: true, key: 'apn', saved: true),
    );
    await expectLater(
      wrongKey.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );

    final timeout = UlinkSetResponseGate(UlinkSettingsKey.ssid);
    await expectLater(
      timeout.wait(const Duration(milliseconds: 1)),
      throwsA(isA<UlinkSettingsException>()),
    );
  });

  test('password text never appears in save failures', () async {
    const password = 'not-for-diagnostics';
    final gate = UlinkSetResponseGate(UlinkSettingsKey.password);
    gate.accept(const UlinkSetReplyEvent(ok: false));
    try {
      await gate.wait(const Duration(milliseconds: 1));
      fail('Expected a failed save.');
    } catch (error) {
      expect(error.toString(), isNot(contains(password)));
    }
  });

  test('Rev4 defaults configure U-Link without dart-defines', () {
    final config = UlinkBleProtocolConfig.environment;
    expect(config.namePrefix, UlinkBleProtocolConfig.productionNamePrefix);
    expect(config.serviceUuid, UlinkBleProtocolConfig.productionServiceUuid);
    expect(
      config.commandCharacteristicUuid,
      UlinkBleProtocolConfig.productionCommandCharacteristicUuid,
    );
    expect(
      config.responseCharacteristicUuid,
      UlinkBleProtocolConfig.productionResponseCharacteristicUuid,
    );
    expect(config.ackTimeout, UlinkBleProtocolConfig.productionAckTimeout);
    expect(config.isConfigured, isTrue);
  });

  test('blank dart-defines fall back to Rev4 defaults', () {
    final config = UlinkBleProtocolConfig.fromEnvironmentValues(
      namePrefix: '  ',
      serviceUuid: '\t',
      commandCharacteristicUuid: ' ',
      responseCharacteristicUuid: '',
      ackTimeoutSeconds: '  ',
    );
    expect(config.namePrefix, UlinkBleProtocolConfig.productionNamePrefix);
    expect(config.serviceUuid, UlinkBleProtocolConfig.productionServiceUuid);
    expect(
      config.commandCharacteristicUuid,
      UlinkBleProtocolConfig.productionCommandCharacteristicUuid,
    );
    expect(
      config.responseCharacteristicUuid,
      UlinkBleProtocolConfig.productionResponseCharacteristicUuid,
    );
    expect(config.ackTimeout, UlinkBleProtocolConfig.productionAckTimeout);
    expect(config.isConfigured, isTrue);
  });

  test('valid dart-defines override Rev4 defaults', () {
    final config = UlinkBleProtocolConfig.fromEnvironmentValues(
      namePrefix: 'ULINK-R5',
      serviceUuid: '12345678-1234-1234-1234-1234567890ab',
      commandCharacteristicUuid: '12345678-1234-1234-1234-1234567890ac',
      responseCharacteristicUuid: '12345678-1234-1234-1234-1234567890ad',
      ackTimeoutSeconds: '20',
    );
    expect(config.namePrefix, 'ULINK-R5');
    expect(config.serviceUuid, '12345678-1234-1234-1234-1234567890ab');
    expect(
      config.commandCharacteristicUuid,
      '12345678-1234-1234-1234-1234567890ac',
    );
    expect(
      config.responseCharacteristicUuid,
      '12345678-1234-1234-1234-1234567890ad',
    );
    expect(config.ackTimeout, const Duration(seconds: 20));
    expect(config.isConfigured, isTrue);
  });

  test('invalid UUID configuration reports a clear error', () {
    const config = UlinkBleProtocolConfig(
      namePrefix: 'ULINK',
      serviceUuid: 'not-a-uuid',
      commandCharacteristicUuid:
          UlinkBleProtocolConfig.productionCommandCharacteristicUuid,
      responseCharacteristicUuid:
          UlinkBleProtocolConfig.productionResponseCharacteristicUuid,
      ackTimeout: Duration(seconds: 1),
    );
    expect(config.isConfigured, isFalse);
    expect(config.validationError, 'U-Link BLE service UUID is invalid.');
  });
}
