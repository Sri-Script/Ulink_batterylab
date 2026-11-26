import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/screens/vtm_demo_calibration_screen.dart';
import 'package:ulink_batterylab/vtm/vtm_demo_connection.dart';

void main() {
  test('VTM demo is independent and in memory', () async {
    final connection = VtmDemoConnection();
    expect(connection.deviceId, 'VTM-TEST');
    await connection.connect();
    expect(await connection.getBatteryCount(), 4);
    await connection.disconnect();
  });

  test('demo reset clears only demo state', () {
    VtmDemoStore.values['voltage'] = '9';
    VtmDemoStore.instance.issueCertificate();
    VtmDemoStore.reset();
    expect(VtmDemoStore.values['voltage'], '3.70');
    expect(VtmDemoStore.instance.certificates, isEmpty);
  });
}
