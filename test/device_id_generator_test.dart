import 'package:flutter_test/flutter_test.dart';
import 'package:ulink_batterylab/services/device_id_generator.dart';

void main() {
  test('formats UTC DateTimes with zero-padded time components', () {
    expect(
      generateDeviceId(DateTime.utc(2026, 11, 7, 3, 4, 5, 6)),
      'DID-030405006',
    );
  });

  test('converts non-UTC input to UTC before formatting', () {
    final localOffsetInput = DateTime.parse('2026-11-07T08:34:05.006+05:30');

    expect(generateDeviceId(localOffsetInput), 'DID-030405006');
  });
}
