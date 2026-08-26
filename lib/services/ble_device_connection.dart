import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config/app_config.dart';
import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import 'device_connection.dart' as app;

class BleDeviceConnection implements app.DeviceConnection {
  BleDeviceConnection(this.descriptor);

  final DeviceDescriptor descriptor;
  final _stateController = StreamController<app.ConnectionState>.broadcast();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _readCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  String get deviceId => descriptor.deviceId;
  @override
  String get gatewayId => descriptor.gatewayId ?? descriptor.deviceId;
  @override
  String? get meshNodeId => descriptor.meshNodeId;
  @override
  TransportType get transportType => TransportType.ble;
  @override
  Stream<app.ConnectionState> get state => _stateController.stream;

  @override
  Future<bool> connect() async {
    _stateController.add(app.ConnectionState.connecting);
    try {
      // A BLE peripheral in deep sleep only listens during its own periodic
      // advertising bursts — the phone cannot push a wake signal to it.
      // The best available option is to keep re-scanning until the device's
      // next advertising window is caught, or the retry budget runs out.
      final deadline = DateTime.now().add(AppConfig.bleWakeRetryWindow);
      ScanResult? result;
      while (result == null && DateTime.now().isBefore(deadline)) {
        await FlutterBluePlus.stopScan();
        await FlutterBluePlus.startScan(
          withServices: [Guid(descriptor.serviceUuid!)],
          timeout: AppConfig.connectionTimeout,
        );
        try {
          result = await FlutterBluePlus.scanResults
              .expand((results) => results)
              .firstWhere((r) {
            final advertisedName = r.advertisementData.advName;
            final expectedName = descriptor.advertisingName;
            return expectedName != null && advertisedName == expectedName;
          })
              .timeout(AppConfig.connectionTimeout);
        } on TimeoutException {
          // No advertisement seen this pass — loop again if time remains.
        }
      }
      await FlutterBluePlus.stopScan();
      if (result == null) {
        throw TimeoutException(
          'Device did not advertise within '
              '${AppConfig.bleWakeRetryWindow.inSeconds}s. It may be asleep — '
              'try again shortly.',
        );
      }
      _device = result.device;
      await _device!.connect(timeout: AppConfig.connectionTimeout);
      _connectionSubscription = _device!.connectionState.listen((state) {
        _stateController.add(
          state == BluetoothConnectionState.connected
              ? app.ConnectionState.connected
              : app.ConnectionState.disconnected,
        );
      });
      final services = await _device!.discoverServices();
      final service = services.firstWhere(
            (item) => item.uuid == Guid(descriptor.serviceUuid!),
      );
      for (final characteristic in service.characteristics) {
        if (_readCharacteristic == null &&
            (characteristic.properties.read ||
                characteristic.properties.notify)) {
          _readCharacteristic = characteristic;
        }
        if (_writeCharacteristic == null &&
            (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse)) {
          _writeCharacteristic = characteristic;
        }
      }
      if (_readCharacteristic == null || _writeCharacteristic == null) {
        throw StateError(
          'Calibration read/write characteristics were not found.',
        );
      }
      _stateController.add(app.ConnectionState.connected);
      return true;
    } catch (_) {
      await FlutterBluePlus.stopScan();
      _stateController.add(app.ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    await _device?.disconnect();
    _stateController.add(app.ConnectionState.disconnected);
  }

  @override
  Future<CalibrationReading> read(String key) async {
    _ensureReady();
    await _writeCharacteristic!.write(
      utf8.encode(jsonEncode({'key': key})),
      withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
    );
    final bytes = await _readCharacteristic!.read();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return CalibrationReading.fromJson(json, key: key);
  }

  @override
  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    _ensureReady();
    final payload = utf8.encode(
      jsonEncode({
        'key': key,
        'value': value,
        'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      }),
    );
    await _writeCharacteristic!.write(
      payload,
      withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
    );
    return true;
  }

  @override
  Future<int> getBatteryCount() async {
    _ensureReady();
    // TODO: BLE mesh routing to sibling nodes using gatewayId/meshNodeId.
    await _writeCharacteristic!.write(
      utf8.encode(jsonEncode({'key': 'status', 'gatewayId': gatewayId})),
      withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
    );
    final payload =
    jsonDecode(utf8.decode(await _readCharacteristic!.read()))
    as Map<String, dynamic>;
    final count = payload['batteryCount'] ?? payload['value'];
    if (count is! num || count < 0) {
      throw const FormatException('Invalid battery count response.');
    }
    return count.toInt();
  }

  @override
  Future<Map<String, dynamic>> getLiveStatus() async {
    _ensureReady();
    await _writeCharacteristic!.write(
      utf8.encode(jsonEncode({'key': 'liveStatus', 'gatewayId': gatewayId})),
      withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse,
    );
    final payload = jsonDecode(utf8.decode(await _readCharacteristic!.read()));
    if (payload is! Map<String, dynamic> || payload['devices'] is! List) {
      throw const FormatException('Invalid live status response.');
    }
    return payload;
  }

  void _ensureReady() {
    if (_device == null ||
        _readCharacteristic == null ||
        _writeCharacteristic == null) {
      throw StateError('Device connection was dropped.');
    }
  }
}
