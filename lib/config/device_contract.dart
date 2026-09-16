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
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nordicUartRxUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nordicUartTxUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  // Broadcast discovery — placeholder port/message until firmware confirms.
  static const int broadcastDiscoveryPort = 47890;
  static const String broadcastDiscoveryMessage = 'ULINK_DISCOVER';

  static const List<BarcodeFormat> qrFormats = [BarcodeFormat.qrCode];
  static const List<BarcodeFormat> barcodeFormats = [BarcodeFormat.code128];

  /// Production firmware serials, e.g. `BATTERY-001`.
  /// Demo gateway IDs are deliberately not validated by this production regex.
  static final RegExp serialPattern = RegExp(r'^BATTERY-[A-Z0-9]{3,}$');
  static final RegExp deviceIdPattern = RegExp(r'^BATTERY-[A-Z0-9]{3,}$');

  /// BLE advertising-name prefixes observed in real deployments.
  static const List<String> advertisingNamePrefixes = [
    'ULINK-GW-',
  ];

  /// Confirmed ESP BLE labels that are not part of the gateway prefix.
  /// Keep these exact rather than accepting all `UBM-*` devices, which could
  /// expose unrelated nearby peripherals in this device-specific workflow.
  static const List<String> recognizedBleNames = ['UBM-Node1'];

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
    if (expectedAdvertisingName != null) {
      return normalizedName == expectedAdvertisingName.toLowerCase();
    }
    return advertisingNamePrefixes.any(
          (prefix) => normalizedName.startsWith(prefix.toLowerCase()),
        ) ||
        recognizedBleNames.any(
          (name) => normalizedName == name.toLowerCase(),
        );
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
