import 'package:mobile_scanner/mobile_scanner.dart';

enum WifiDiscoveryMode { mdns, softAp, broadcast }

/// Temporary firmware/label contract. Replace values in this file only when
/// the production ESP32 contract is finalized.
class DeviceContract {
  const DeviceContract._();

  static const WifiDiscoveryMode kWifiDiscoveryMode =
      WifiDiscoveryMode.broadcast;
  static const String mdnsServiceName = '_ulink._tcp.local';
  static const String wifiSsidPrefix = 'ULINK-';
  static const String defaultBleServiceUuid =
      '0000181a-0000-1000-8000-00805f9b34fb';

  // Broadcast discovery — placeholder port/message until firmware confirms.
  static const int broadcastDiscoveryPort = 47890;
  static const String broadcastDiscoveryMessage = 'ULINK_DISCOVER';

  static const List<BarcodeFormat> qrFormats = [BarcodeFormat.qrCode];
  static const List<BarcodeFormat> barcodeFormats = [BarcodeFormat.code128];

  // TODO: confirm serial format with hardware team.
  static final RegExp serialPattern = RegExp(r'^ULINK-[A-Z0-9]{4,10}$');
  static final RegExp deviceIdPattern = RegExp(
    r'^(?:ULINK-[A-Z0-9]{4,10}|ULINK-GW-[A-Z0-9]{4,10})$',
  );

  /// BLE advertising-name prefixes observed in real deployments.
  ///
  /// `UBM-Node1` is one confirmed real device name. It is not evidence that
  /// every UBM device will use the `UBM-` prefix; confirm the enduring naming
  /// contract with the firmware team before treating this list as final.
  static const List<String> advertisingNamePrefixes = [
    'ULINK-GW-',
    'UBM-',
  ];

  /// Retained for callers that need the canonical Ulink gateway label.
  //static const String advertisingNamePrefix = advertisingNamePrefixes.first;
  static final String advertisingNamePrefix = advertisingNamePrefixes.first;

  /// Matches BLE results in Dart instead of relying on Android's native
  /// service filter, which can miss UUIDs placed in the scan response.
  static bool matchesBleAdvertisement({
    required String advertisedName,
    required Iterable<String> serviceUuids,
    String? expectedAdvertisingName,
    String? advertisedBleDeviceId,
    String? expectedBleDeviceId,
  }) {
    final matchesService = serviceUuids.any(
      (uuid) => uuid.toLowerCase() == defaultBleServiceUuid.toLowerCase(),
    );
    final matchesName = matchesAdvertisingName(
      advertisedName,
      expectedAdvertisingName: expectedAdvertisingName,
    );
    final matchesBleDeviceId = expectedBleDeviceId != null &&
        advertisedBleDeviceId != null &&
        _normalizeBleDeviceId(expectedBleDeviceId) ==
            _normalizeBleDeviceId(advertisedBleDeviceId);

    // Keep service-UUID matching unchanged while allowing a known BLE device
    // ID (a MAC address on Android) to identify a QR-targeted peripheral.
    return matchesService || matchesName || matchesBleDeviceId;
  }

  /// Name-only identity check for passive discovery, where no specific
  /// peripheral identity is known yet.
  static bool matchesAdvertisingName(
    String advertisedName, {
    String? expectedAdvertisingName,
  }) {
    final normalizedName = advertisedName.toLowerCase();
    return expectedAdvertisingName == null
        ? advertisingNamePrefixes.any(
            (prefix) => normalizedName.startsWith(prefix.toLowerCase()),
          )
        : normalizedName == expectedAdvertisingName.toLowerCase();
  }

  static String _normalizeBleDeviceId(String value) =>
      value.trim().replaceAll('-', ':').toUpperCase();

  /// Example: ULINK-GW1234 -> ULINK-GW-GW1234.
  static String advertisingNameFor(String deviceId) {
    final serial = deviceId.startsWith('ULINK-')
        ? deviceId.substring('ULINK-'.length)
        : deviceId;
    return '$advertisingNamePrefix$serial';
  }

  static const Map<String, Object> testStatusPayload = {
    'deviceId': 'ULINK-GW-TEST01',
    'batteryCount': 3,
    'bleMac': 'AA:BB:CC:DD:EE:FF',
    'firmwareVersion': '0.0.0-test',
  };

  /// Toggle this in demo builds to exercise mesh and point-to-point UI flows.
  static const bool fakeGatewayIsMesh = true;
}
