import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/config/device_contract.dart';

void main() {
  test('formats the supplied DateTime rather than a fixed timestamp', () {
    final january = DeviceContract.deviceTimestamp(
      DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    final july = DeviceContract.deviceTimestamp(
      DateTime.utc(2026, 7, 8, 9, 10, 11),
    );

    expect(january, isNot(july));
    expect(january, '2026-01-02T03:04:05+00:00');
    expect(july, '2026-07-08T09:10:11+00:00');
  });

  test('uses a numeric offset, never Z, for a UTC DateTime', () {
    final timestamp = DeviceContract.deviceTimestamp(
      DateTime.utc(2026, 9, 3, 12, 30),
    );

    expect(timestamp, '2026-09-03T12:30:00+00:00');
  });
}
