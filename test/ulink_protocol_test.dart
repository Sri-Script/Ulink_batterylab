import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/services/ulink_ble_protocol_config.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';

void main() {
  test('validates Wi-Fi credentials by UTF-8 byte length', () {
    expect(UlinkProvisioningProtocol.validateCredentials('', ''), isNotNull);
    expect(UlinkProvisioningProtocol.validateCredentials('ssid', 'short'), isNotNull);
    expect(UlinkProvisioningProtocol.validateCredentials('ssid', ''), isNull);
    expect(UlinkProvisioningProtocol.validateCredentials('ssid', 'password8'), isNull);
  });

  test('parses fragmented and multiple acknowledgements', () {
    final parser = UlinkAckParser();
    final bytes = utf8.encode('{"op":"ack","requestId":"a","status":"ok"}\n{"op":"ack","requestId":"b","status":"error"}\n');
    expect(parser.add(bytes.sublist(0, 8)), isEmpty);
    final events = parser.add(bytes.sublist(8));
    expect(events, hasLength(2));
    expect((events[0] as UlinkAckEvent).requestId, 'a');
    expect((events[1] as UlinkAckEvent).status, 'error');
  });

  test('malformed input and mismatched acknowledgements fail the gate', () async {
    final gate = UlinkAcknowledgementGate('expected', safeMessage: (_) => 'rejected');
    gate.accept(const UlinkMalformedEvent());
    expect(gate.wait(const Duration(milliseconds: 1)), throwsA(isA<UlinkProvisioningException>()));
    final mismatch = UlinkAcknowledgementGate('expected', safeMessage: (_) => 'rejected');
    mismatch.accept(const UlinkAckEvent(requestId: 'other', status: 'ok'));
    expect(mismatch.wait(const Duration(milliseconds: 1)), throwsA(isA<UlinkProvisioningException>()));
  });

  test('a GATT write alone cannot acknowledge a request', () async {
    final gate = UlinkAcknowledgementGate('request', safeMessage: (_) => 'rejected');
    expect(gate.wait(const Duration(milliseconds: 1)), throwsA(isA<UlinkProvisioningException>()));
  });

  test('UUID config defaults stay unconfigured', () {
    const config = UlinkBleProtocolConfig(namePrefix: 'ULINK', serviceUuid: '', commandCharacteristicUuid: '', responseCharacteristicUuid: '', ackTimeout: Duration(seconds: 1));
    expect(config.isConfigured, isFalse);
  });
}
