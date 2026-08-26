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

  static const String advertisingNamePrefix = 'ULINK-GW-';

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
