import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ulink_batterylab/main.dart';
import 'package:ulink_batterylab/models/device_descriptor.dart';
import 'package:ulink_batterylab/providers/connection_controller.dart';
import 'package:ulink_batterylab/screens/calibration_screen.dart';
import 'package:ulink_batterylab/services/device_connection.dart' as device;

void main() {
  testWidgets('shows architecture choices at startup', (tester) async {
    await tester.pumpWidget(const BatteryLabApp());
    expect(find.text('Continue with U-Link'), findsOneWidget);
    expect(find.text('Continue with Battery Monitor'), findsOneWidget);
  });

  testWidgets('routes to the existing scanner flow', (tester) async {
    await tester.pumpWidget(const BatteryLabApp());
    await tester.tap(find.text('Continue with Battery Monitor'));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryLabApp), findsOneWidget);
  });

  testWidgets('shows DID controls with send disabled until generation', (
    tester,
  ) async {
    final controller = ConnectionController()
      ..descriptor = const DeviceDescriptor(
        mode: TransportType.ble,
        deviceId: 'U-LINK-001',
      )
      ..connectionState = device.ConnectionState.connected;

    await tester.pumpWidget(
      ChangeNotifierProvider<ConnectionController>.value(
        value: controller,
        child: const MaterialApp(home: CalibrationScreen()),
      ),
    );
    await tester.tap(find.text('Calibration'));
    await tester.pumpAndSettle();

    expect(find.text('Device ID (DID)'), findsOneWidget);
    expect(find.text('Generate DID'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send DID to U-Link'),
    );
    expect(sendButton.onPressed, isNull);

    await tester.tap(find.text('Generate DID'));
    await tester.pump();

    expect(find.textContaining('DID-'), findsOneWidget);
    final enabledSendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send DID to U-Link'),
    );
    expect(enabledSendButton.onPressed, isNotNull);
  });
}
