import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulink_batterylab/config/app_config.dart';
import 'package:ulink_batterylab/config/device_contract.dart';
import 'package:ulink_batterylab/models/device_descriptor.dart';
import 'package:ulink_batterylab/main.dart';

void main() {
  testWidgets('shows scanner-first connection options', (tester) async {
    // This test verifies the post-startup landing screen. Bypass the one-time
    // acknowledgement rather than asserting against the first-install flow.
    SharedPreferences.setMockInitialValues({
      'disclaimer_acknowledged': true,
    });
    await tester.pumpWidget(const BatteryLabApp());
    // Don't use pumpAndSettle here — the splash screen's loading indicator
    // animates indefinitely, so pumpAndSettle would wait forever (that's the
    // timeout you saw). Instead, pump forward in fixed steps to give the
    // splash's async init + navigation a chance to complete without needing
    // every animation to fully stop.
    await tester.pump(); // first frame — splash appears
    const step = Duration(milliseconds: 500);
    final maxStartup = AppConfig.splashMaxWait + const Duration(seconds: 2);
    for (var elapsed = Duration.zero; elapsed < maxStartup; elapsed += step) {
      await tester.pump(step);
    }
    expect(find.text('Connect Ulink Gateway'), findsOneWidget);
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Scan Barcode'), findsOneWidget);
    expect(find.text('Discover via Wi-Fi instead'), findsOneWidget);
    expect(find.text('Use demo gateway'), findsOneWidget);
  });

  test('plain QR device ID resolves without surfacing a JSON error', () {
    final result = DeviceDescriptor.fromScannedPayload(
      'ULINK-GW-TEST01',
      barcode: false,
    );
    expect(result.deviceId, 'ULINK-GW-TEST01');
    expect(result.advertisingName, 'ULINK-GW-GW-TEST01');
  });

  test('BLE advertisement matching is case-insensitive and unfiltered', () {
    expect(
      DeviceContract.matchesBleAdvertisement(
        advertisedName: 'other-device',
        serviceUuids: ['0000181A-0000-1000-8000-00805F9B34FB'],
      ),
      isTrue,
    );
    expect(
      DeviceContract.matchesBleAdvertisement(
        advertisedName: 'ulink-gw-test01',
        serviceUuids: const [],
      ),
      isTrue,
    );
    expect(
      DeviceContract.matchesBleAdvertisement(
        advertisedName: 'UBM-Node1',
        serviceUuids: const [],
      ),
      isTrue,
    );
    expect(
      DeviceContract.matchesBleAdvertisement(
        advertisedName: 'ULINK-GW-TEST02',
        serviceUuids: const [],
        expectedAdvertisingName: 'ULINK-GW-TEST01',
      ),
      isFalse,
    );
    expect(
      DeviceContract.matchesBleAdvertisement(
        advertisedName: 'different-device',
        serviceUuids: const [],
        expectedAdvertisingName: 'ULINK-GW-TEST01',
        advertisedBleDeviceId: '30:c6:f7:14:f9:0a',
        expectedBleDeviceId: '30-C6-F7-14-F9-0A',
      ),
      isTrue,
    );
  });

  test('BLE QR payload accepts a MAC address as the BLE identity', () {
    final descriptor = DeviceDescriptor.fromScannedPayload(
      '{"mode":"ble","deviceId":"UBM-Node1",'
      '"serviceUuid":"0000181a-0000-1000-8000-00805f9b34fb",'
      '"bleMac":"30:C6:F7:14:F9:0A"}',
      barcode: false,
    );
    expect(descriptor.bleDeviceId, '30:C6:F7:14:F9:0A');
  });

  test('Code 128 payload uses placeholder serial validation', () {
    expect(
      DeviceDescriptor.fromScannedPayload(
        'ULINK-GW1234',
        barcode: true,
      ).deviceId,
      'ULINK-GW1234',
    );
    expect(
          () => DeviceDescriptor.fromScannedPayload('not-a-serial', barcode: true),
      throwsFormatException,
    );
  });
}
