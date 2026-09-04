import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config/app_config.dart';
import '../config/device_contract.dart';
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
      _log('connect requested: label=$deviceId id=${descriptor.bleDeviceId}');
      // A BLE peripheral in deep sleep only listens during its own periodic
      // advertising bursts — the phone cannot push a wake signal to it.
      // The best available option is to keep re-scanning until the device's
      // next advertising window is caught, or the retry budget runs out.
      ScanResult? result;
      if (descriptor.bleDeviceId != null) {
        // A user selected this exact result from the unfiltered diagnostic
        // list, so do not re-filter scans or depend on advertised UUIDs.
        _device = BluetoothDevice.fromId(descriptor.bleDeviceId!);
      }
      final deadline = DateTime.now().add(AppConfig.bleWakeRetryWindow);
      while (_device == null && result == null && DateTime.now().isBefore(deadline)) {
        await FlutterBluePlus.stopScan();
        _log('starting unfiltered retry scan');
        await FlutterBluePlus.startScan(timeout: AppConfig.connectionTimeout);
        try {
          result = await FlutterBluePlus.scanResults
              .expand((results) => results)
              .firstWhere((r) {
            final advertisedName = r.advertisementData.advName;
            final serviceUuids = r.advertisementData.serviceUuids
                .map((uuid) => uuid.toString());
            if (kDebugMode && AppConfig.bleScanDiagnostics) {
              debugPrint(
                'BLE advertisement: name="$advertisedName", '
                'services=$serviceUuids',
              );
            }
            return DeviceContract.matchesBleAdvertisement(
              advertisedName: advertisedName,
              serviceUuids: serviceUuids,
              expectedAdvertisingName: descriptor.advertisingName,
              advertisedBleDeviceId: r.device.remoteId.str,
              expectedBleDeviceId: descriptor.bleDeviceId,
            );
          })
              .timeout(AppConfig.connectionTimeout);
        } on TimeoutException {
          // No advertisement seen this pass — loop again if time remains.
        }
      }
      await FlutterBluePlus.stopScan();
      if (_device == null && result == null) {
        throw TimeoutException(
          'Device did not advertise within '
              '${AppConfig.bleWakeRetryWindow.inSeconds}s. It may be asleep — '
              'try again shortly.',
        );
      }
      _device ??= result!.device;
      _log('connecting to ${_device!.remoteId.str}');
      await _device!.connect(timeout: AppConfig.connectionTimeout);
      _connectionSubscription = _device!.connectionState.listen((state) {
        _log('connection state: $state');
        _stateController.add(
          state == BluetoothConnectionState.connected
              ? app.ConnectionState.connected
              : app.ConnectionState.disconnected,
        );
      });
      final services = await _device!.discoverServices();
      _logGatt(services);
      final expectedUuid = descriptor.serviceUuid;
      if (expectedUuid != null &&
          !services.any((service) => _sameUuid(service.uuid, expectedUuid))) {
        _log('CONTRACT MISMATCH: expected service $expectedUuid was not discovered.');
      } else if (expectedUuid == null) {
        _log('CONTRACT UNVERIFIED: no service UUID selected; using discovered writable characteristic.');
      }
      final orderedServices = expectedUuid == null
          ? services
          : [...services.where((s) => _sameUuid(s.uuid, expectedUuid)), ...services.where((s) => !_sameUuid(s.uuid, expectedUuid))];
      for (final service in orderedServices) {
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
      }
      if (_readCharacteristic == null || _writeCharacteristic == null) {
        throw StateError(
          'Calibration read/write characteristics were not found.',
        );
      }
      _stateController.add(app.ConnectionState.connected);
      _log('GATT ready: read=${_readCharacteristic!.uuid} write=${_writeCharacteristic!.uuid} withoutResponse=${_writeCharacteristic!.properties.writeWithoutResponse}');
      return true;
    } catch (error) {
      _log('connect/GATT failure: $error');
      await FlutterBluePlus.stopScan();
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _device?.disconnect();
      _device = null;
      _readCharacteristic = null;
      _writeCharacteristic = null;
      _stateController.add(app.ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    await _device?.disconnect();
    _device = null;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    _stateController.add(app.ConnectionState.disconnected);
  }

  @override
  Future<CalibrationReading> read(String key) async {
    _ensureReady();
    await _writePayload({'key': key});
    final bytes = await _readCharacteristic!.read();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return CalibrationReading.fromJson(json, key: key);
  }

  @override
  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    _ensureReady();
    await _writePayload({
      'key': key,
      'value': value,
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
    });
    return true;
  }

  @override
  Future<int> getBatteryCount() async {
    _ensureReady();
    // TODO: BLE mesh routing to sibling nodes using gatewayId/meshNodeId.
    await _writePayload({'key': 'status', 'gatewayId': gatewayId});
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
    await _writePayload({'key': 'liveStatus', 'gatewayId': gatewayId});
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

  Future<void> _writePayload(Map<String, dynamic> body) async {
    _ensureReady();
    final jsonPayload = jsonEncode(body);
    final bytes = utf8.encode(jsonPayload);
    final characteristic = _writeCharacteristic!;
    final withoutResponse = characteristic.properties.writeWithoutResponse;
    _log('write pending characteristic=${characteristic.uuid} '
        'mode=${withoutResponse ? 'without-response' : 'with-response'} '
        'utf8=$bytes json=$jsonPayload');
    try {
      await characteristic.write(bytes, withoutResponse: withoutResponse);
      _log('write succeeded characteristic=${characteristic.uuid}');
    } catch (error) {
      _log('write failed characteristic=${characteristic.uuid}: $error');
      rethrow;
    }
  }

  bool _sameUuid(Guid value, String expected) =>
      value.toString().toLowerCase() == expected.toLowerCase();

  void _logGatt(List<BluetoothService> services) {
    for (final service in services) {
      _log('GATT service ${service.uuid}');
      for (final characteristic in service.characteristics) {
        final p = characteristic.properties;
        _log('  characteristic ${characteristic.uuid}: '
            'read=${p.read} notify=${p.notify} indicate=${p.indicate} '
            'write=${p.write} writeWithoutResponse=${p.writeWithoutResponse}');
      }
    }
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('Ulink BLE: $message');
  }
}
