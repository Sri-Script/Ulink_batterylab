import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/screens/ulink_wifi_provisioning_screen.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';

void main() {
  const initialSettings = UlinkSettings(
    ssid: 'PlantWiFi',
    password: 'private-password',
    apn: 'internet',
    mode: 'WIFI',
  );

  testWidgets('automatic settings payload populates all U-Link fields', (
    tester,
  ) async {
    final client = _FakeSettingsClient();
    await tester.pumpWidget(
      MaterialApp(home: UlinkWifiProvisioningScreen(client: client)),
    );

    expect(find.text('Loading settings from U-Link...'), findsOneWidget);
    client.emit(UlinkSettingsEvent(initialSettings));
    await tester.pump();

    expect(find.text('Connected to ULINK-REV4'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(4));
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller!.text, 'PlantWiFi');
    expect(fields[1].controller!.text, 'private-password');
    expect(fields[1].obscureText, isTrue);
    expect(fields[2].controller!.text, 'internet');
    expect(find.text('WIFI'), findsWidgets);
  });

  testWidgets('Refresh sends GET_SETTINGS and a Set sends its exact command', (
    tester,
  ) async {
    final client = _FakeSettingsClient();
    await tester.pumpWidget(
      MaterialApp(home: UlinkWifiProvisioningScreen(client: client)),
    );
    client.emit(UlinkSettingsEvent(initialSettings));
    await tester.pump();

    await tester.tap(find.text('Refresh / Get All'));
    await tester.pump();
    expect(client.commands, contains('GET_SETTINGS\n'));

    final ssidField = tester.widget<TextField>(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'NewNetwork');
    await tester.pump();
    expect(ssidField.controller!.text, 'NewNetwork');
    await tester.tap(find.widgetWithText(FilledButton, 'Set').first);
    await tester.pump();
    expect(
      client.commands,
      contains('{"cmd":"SET","key":"ssid","value":"NewNetwork"}\n'),
    );
  });
}

class _FakeSettingsClient implements UlinkSettingsClient {
  final StreamController<UlinkProtocolEvent> _events =
      StreamController<UlinkProtocolEvent>.broadcast();
  final List<String> commands = <String>[];
  UlinkSettings? _latestSettings;

  @override
  String get deviceName => 'ULINK-REV4';

  @override
  Stream<UlinkProtocolEvent> get events => _events.stream;

  @override
  UlinkSettings? get latestSettings => _latestSettings;

  void emit(UlinkProtocolEvent event) {
    if (event is UlinkSettingsEvent) _latestSettings = event.settings;
    _events.add(event);
  }

  @override
  Future<UlinkSettings> refreshSettings() async {
    commands.add(UlinkSettingsProtocol.getSettingsCommand);
    return _latestSettings ??
        const UlinkSettings(
          ssid: 'PlantWiFi',
          password: 'private-password',
          apn: 'internet',
          mode: 'WIFI',
        );
  }

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) async {
    commands.add(UlinkSettingsProtocol.encodeSet(key, value));
  }

  @override
  Future<void> disconnect() async {}
}
