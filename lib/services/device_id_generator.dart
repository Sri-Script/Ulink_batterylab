/// Generates the requested time-only DID format. This can repeat on different
/// UTC days, so it is not globally unique across dates.
String generateDeviceId(DateTime value) {
  final utc = value.toUtc();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final milliseconds = utc.millisecond.toString().padLeft(3, '0');
  return 'DID-${twoDigits(utc.hour)}${twoDigits(utc.minute)}${twoDigits(utc.second)}$milliseconds';
}
