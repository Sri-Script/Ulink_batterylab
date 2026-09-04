import 'dart:convert';

import '../config/device_contract.dart';

enum TransportType { ble, wifi }

class DeviceDescriptor {
  const DeviceDescriptor({
    required this.mode,
    required this.deviceId,
    this.serviceUuid,
    this.ip,
    this.port,
    this.gatewayId,
    this.meshNodeId,
    this.advertisingName,
    this.bleDeviceId,
  });

  final TransportType mode;
  final String deviceId;
  final String? serviceUuid;
  final String? ip;
  final int? port;
  final String? gatewayId;
  final String? meshNodeId;
  final String? advertisingName;
  /// Platform BLE identifier (MAC on Android when exposed). Kept separately
  /// from the display/device label so unnamed peripherals remain selectable.
  final String? bleDeviceId;

  factory DeviceDescriptor.fromScannedPayload(
    String raw, {
    required bool barcode,
  }) {
    final value = raw.trim().toUpperCase();
    if (value.isEmpty) {
      throw const FormatException('unrecognized');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DeviceDescriptor.fromJson(decoded);
      }
    } on FormatException {
      // Plain serial/device IDs are the expected fallback for etched labels.
    }
    final valid = barcode
        ? DeviceContract.serialPattern.hasMatch(value)
        : DeviceContract.deviceIdPattern.hasMatch(value);
    if (!valid) {
      throw const FormatException('unrecognized');
    }
    return DeviceDescriptor(
      mode: TransportType.ble,
      deviceId: value,
      gatewayId: value,
      serviceUuid: DeviceContract.defaultBleServiceUuid,
      advertisingName: DeviceContract.advertisingNameFor(value),
    );
  }

  factory DeviceDescriptor.fromQr(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR payload must be a JSON object.');
    }
    final modeText = decoded['mode']?.toString().toLowerCase();
    final deviceId = decoded['deviceId']?.toString().trim() ?? '';
    if (deviceId.isEmpty || (modeText != 'ble' && modeText != 'wifi')) {
      throw const FormatException('QR must include mode and deviceId.');
    }
    if (modeText == 'ble') {
      final uuid = decoded['serviceUuid']?.toString().trim() ?? '';
      if (uuid.isEmpty) {
        throw const FormatException('BLE QR is missing serviceUuid.');
      }
      return DeviceDescriptor(
        mode: TransportType.ble,
        deviceId: deviceId,
        serviceUuid: uuid,
        gatewayId: decoded['gatewayId']?.toString() ?? deviceId,
        meshNodeId: decoded['meshNodeId']?.toString(),
        advertisingName:
            decoded['advertisingName']?.toString() ??
            DeviceContract.advertisingNameFor(deviceId),
        // Android exposes the BLE device ID as its MAC address. Accept the
        // explicit `bleMac` QR field too, so a QR can target one unique device
        // without relying only on its advertised name.
        bleDeviceId: decoded['bleDeviceId']?.toString() ??
            decoded['bleMac']?.toString(),
      );
    }
    final ip = decoded['ip']?.toString().trim() ?? '';
    final port = int.tryParse(decoded['port']?.toString() ?? '80');
    if (!isValidIpv4(ip) || port == null || port < 1 || port > 65535) {
      throw const FormatException(
        'Wi-Fi QR has an invalid IP address or port.',
      );
    }
    return DeviceDescriptor(
      mode: TransportType.wifi,
      deviceId: deviceId,
      ip: ip,
      port: port,
      gatewayId: decoded['gatewayId']?.toString() ?? deviceId,
      meshNodeId: decoded['meshNodeId']?.toString(),
    );
  }

  factory DeviceDescriptor.fromJson(Map<String, dynamic> json) =>
      DeviceDescriptor.fromQr(jsonEncode(json));

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'deviceId': deviceId,
    if (serviceUuid != null) 'serviceUuid': serviceUuid,
    if (ip != null) 'ip': ip,
    if (port != null) 'port': port,
    if (gatewayId != null) 'gatewayId': gatewayId,
    if (meshNodeId != null) 'meshNodeId': meshNodeId,
    if (advertisingName != null) 'advertisingName': advertisingName,
    if (bleDeviceId != null) 'bleDeviceId': bleDeviceId,
  };

  static bool isValidIpv4(String value) {
    final parts = value.split('.');
    return parts.length == 4 &&
        parts.every((part) {
          final number = int.tryParse(part);
          return number != null && number >= 0 && number <= 255;
        });
  }
}
