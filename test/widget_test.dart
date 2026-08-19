import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/models/device_descriptor.dart';
import 'package:ulink_batterylab/main.dart';

void main() {
  testWidgets('shows scanner-first connection options', (tester) async {
    await tester.pumpWidget(const BatteryLabApp());
    await tester.pump();
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
