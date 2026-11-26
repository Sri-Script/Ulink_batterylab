/// BLE contract for the Battery Mobile ESP UART terminal.
///
/// This is deliberately separate from DeviceContract: Ulink's BLE matching
/// rules must not be broadened by VTM devices.
class VtmNusContract {
  const VtmNusContract._();

  static const String namePrefix = 'VTM-';
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String rxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String txUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  static bool matchesName(String name) => name.startsWith(namePrefix);

  static bool sameUuid(Object uuid, String expected) =>
      uuid.toString().toLowerCase() == expected.toLowerCase();

  /// Cached platform IDs may never be used to connect VTM. The selected
  /// peripheral must be observed again in a new scan.
  static bool matchesFreshAdvertisement({
    required String advertisedName,
    required String remoteId,
    required String selectedName,
    required String selectedRemoteId,
  }) =>
      advertisedName == selectedName &&
      _normalizeRemoteId(remoteId) == _normalizeRemoteId(selectedRemoteId);

  static String _normalizeRemoteId(String value) =>
      value.trim().replaceAll('-', ':').toUpperCase();
}
