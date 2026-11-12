import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/screens/ulink_wifi_provisioning_screen.dart';
import 'package:ulink_batterylab/services/acknowledgement_sound_service.dart';
import 'package:ulink_batterylab/services/ulink_ble_provisioning_client.dart';

const initialSettings = UlinkSettings(
  ssid: 'PlantWiFi',
  password: 'private-password',
  apn: 'internet',
  mode: 'WIFI',
);

void main() {
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

  testWidgets('Cancel closes Set confirmation without sending a command', (
    tester,
  ) async {
    final client = _FakeSettingsClient();
    final sound = _RecordingAcknowledgementSoundService();
    await tester.pumpWidget(
      MaterialApp(
        home: UlinkWifiProvisioningScreen(
          client: client,
          acknowledgementSound: sound,
        ),
      ),
    );
    client.emit(UlinkSettingsEvent(initialSettings));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'NewNetwork');
    await tester.tap(find.widgetWithText(FilledButton, 'Set').first);
    await tester.pumpAndSettle();

    expect(find.text('CONFIRM?'), findsOneWidget);
    expect(
      find.text(
        'Send this updated Wi-Fi SSID to the connected U-Link?\n\nNew value: NewNetwork',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.commands, isEmpty);
    expect(sound.playCalls, isZero);
  });

  testWidgets(
    'plays one acknowledgement only after a matching saved response',
    (tester) async {
      final client = _ResponseGateSettingsClient();
      final sound = _RecordingAcknowledgementSoundService();
      await _pumpReadyScreen(tester, client, sound);

      await _startSsidSave(tester);
      expect(sound.playCalls, isZero); // A GATT write alone is not a save.

      client.receive(
        const UlinkSetReplyEvent(ok: true, key: 'ssid', saved: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved on U-Link'), findsWidgets);
      expect(sound.playCalls, 1);

      client.receive(
        const UlinkSetReplyEvent(ok: true, key: 'ssid', saved: true),
      );
      await tester.pump();
      expect(sound.playCalls, 1);
    },
  );

  testWidgets(
    'does not acknowledge failed, wrong-key, timed-out, or disconnected saves',
    (tester) async {
      final client = _ResponseGateSettingsClient();
      final sound = _RecordingAcknowledgementSoundService();
      await _pumpReadyScreen(tester, client, sound);

      await _startSsidSave(tester);
      client.receive(const UlinkSetReplyEvent(ok: false));
      await tester.pumpAndSettle();

      await _startSsidSave(tester);
      client.receive(
        const UlinkSetReplyEvent(ok: true, key: 'apn', saved: true),
      );
      await tester.pumpAndSettle();

      await _startSsidSave(tester);
      client.timeout();
      await tester.pumpAndSettle();

      await _startSsidSave(tester);
      await client.disconnect();
      await tester.pumpAndSettle();

      expect(sound.playCalls, isZero);
    },
  );

  testWidgets(
    'Refresh sends GET_SETTINGS and confirmed Set sends exact command',
    (tester) async {
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
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Set'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        client.commands,
        contains('{"cmd":"SET","key":"ssid","value":"NewNetwork"}\n'),
      );
    },
  );
}

Future<void> _pumpReadyScreen(
  WidgetTester tester,
  _FakeSettingsClient client,
  AcknowledgementSoundService sound,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UlinkWifiProvisioningScreen(
        client: client,
        acknowledgementSound: sound,
      ),
    ),
  );
  client.emit(initialSettingsEvent);
  await tester.pump();
}

Future<void> _startSsidSave(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'NewNetwork');
  await tester.tap(find.widgetWithText(FilledButton, 'Set').first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Set'),
    ),
  );
  await tester.pump();
}

const initialSettingsEvent = UlinkSettingsEvent(initialSettings);

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

class _ResponseGateSettingsClient extends _FakeSettingsClient {
  UlinkSetResponseGate? _saveGate;

  @override
  Future<void> saveSetting(UlinkSettingsKey key, String value) {
    commands.add(UlinkSettingsProtocol.encodeSet(key, value));
    final gate = UlinkSetResponseGate(key);
    _saveGate = gate;
    return gate.wait(const Duration(minutes: 1));
  }

  void receive(UlinkProtocolEvent event) => _saveGate?.accept(event);

  void timeout() => _saveGate?.fail('Timed out waiting for a save response.');

  @override
  Future<void> disconnect() async {
    _saveGate?.fail('U-Link disconnected before it responded.');
  }
}

class _RecordingAcknowledgementSoundService
    extends AcknowledgementSoundService {
  int playCalls = 0;

  @override
  Future<void> play() async {
    playCalls += 1;
  }
}
