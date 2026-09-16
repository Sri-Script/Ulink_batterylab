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
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  final _liveReadingsController = StreamController<Map<String, dynamic>>.broadcast();
  Completer<String>? _pendingResponse;
  String _receiveBuffer = '';

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
  Stream<Map<String, dynamic>> get liveReadings => _liveReadingsController.stream;

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
      _log('connecting to peripheral id=${_device!.remoteId.str}');
      await _device!.connect(timeout: AppConfig.connectionTimeout);
      _connectionSubscription = _device!.connectionState.listen((state) {
        _log('connection state: $state');
        _stateController.add(
          state == BluetoothConnectionState.connected
              ? app.ConnectionState.connected
              : app.ConnectionState.disconnected,
        );
      });
      _log('connected; beginning GATT service discovery');
      final services = await _device!.discoverServices();
      _log('GATT discovery completed: ${services.length} service(s)');
      _logGatt(services);
      final expectedServiceUuid =
          descriptor.serviceUuid ?? DeviceContract.defaultBleServiceUuid;
      final service = services.cast<BluetoothService?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid, expectedServiceUuid),
        orElse: () => null,
      );
      if (service == null) {
        throw StateError(
          'Required Nordic UART service $expectedServiceUuid was not found. '
          'See the logged GATT services and configure the ESP BLE firmware to expose it.',
        );
      }
      _rxCharacteristic = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid, DeviceContract.nordicUartRxUuid),
        orElse: () => null,
      );
      _txCharacteristic = service.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
        (item) => item != null && _sameUuid(item.uuid, DeviceContract.nordicUartTxUuid),
        orElse: () => null,
      );
      if (_rxCharacteristic == null || _txCharacteristic == null) {
        throw StateError('Nordic UART RX/TX characteristics were not found.');
      }
      if (!_rxCharacteristic!.properties.write && !_rxCharacteristic!.properties.writeWithoutResponse) {
        throw StateError('Nordic UART RX is not writable.');
      }
      if (!_txCharacteristic!.properties.notify) throw StateError('Nordic UART TX does not support notifications.');
      _log('subscribing to TX notifications: ${_txCharacteristic!.uuid}');
      await _txCharacteristic!.setNotifyValue(true);
      _notificationSubscription = _txCharacteristic!.lastValueStream.listen(_onNotification);
      _stateController.add(app.ConnectionState.connected);
      _log('Nordic UART ready: RX=${_rxCharacteristic!.uuid}, TX=${_txCharacteristic!.uuid}');
      return true;
    } catch (error) {
      _log('connect/GATT failure: $error');
      await FlutterBluePlus.stopScan();
      await _connectionSubscription?.cancel();
      await _notificationSubscription?.cancel();
      _connectionSubscription = null;
      try {
        await _device?.disconnect();
      } catch (disconnectError) {
        _log('disconnect after connection failure also failed: $disconnectError');
      }
      _device = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _stateController.add(app.ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _log('disconnect requested');
    try {
      await _connectionSubscription?.cancel();
      await _notificationSubscription?.cancel();
      await _device?.disconnect();
    } catch (error) {
      _log('disconnect failure: $error');
      rethrow;
    } finally {
      _connectionSubscription = null;
      _notificationSubscription = null;
    }
    _device = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    final pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Device disconnected.'));
    }
    _pendingResponse = null;
    _stateController.add(app.ConnectionState.disconnected);
    _log('disconnect complete');
  }

  @override
  Future<CalibrationReading> read(String key) async {
    final response = await command(_readCommand(key));
    return CalibrationReading(key: key, value: _decodeResponse(response), timestamp: DateTime.now(), direction: 'read', status: 'success');
  }

  @override
  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    await command(_writeCommand(key, value, timestamp));
    return true;
  }

  @override
  Future<int> getBatteryCount() async {
    final status = await getLiveStatus();
    final count = status['batteryCount'];
    if (count is num && count >= 0) return count.toInt();
    final devices = status['devices'];
    if (devices is List) return devices.length;
    throw const FormatException(
      'GET_STATUS response does not include batteryCount or devices.',
    );
  }

  @override
  Future<Map<String, dynamic>> getLiveStatus() async {
    final response = await command('GET_STATUS');
    final decoded = jsonDecode(response);
    if (decoded is! Map) {
      throw const FormatException('GET_STATUS response must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<String> command(String command) async {
    _ensureReady();
    if (_pendingResponse != null) throw StateError('Another device command is already awaiting a response.');
    final completer = Completer<String>();
    _pendingResponse = completer;
    try {
      _log('writing command: $command');
      final payload = utf8.encode(command.endsWith('\n') ? command : '$command\n');
      final characteristic = _rxCharacteristic!;
      // Nordic UART firmware commonly uses the default 20-byte ATT payload.
      // Commands are plain byte streams, so it is safe to split a long SET_TIME
      // or SET_SN command while preserving its terminating newline.
      for (var offset = 0; offset < payload.length; offset += 20) {
        final end = (offset + 20 < payload.length) ? offset + 20 : payload.length;
        await characteristic.write(payload.sublist(offset, end), withoutResponse: characteristic.properties.writeWithoutResponse);
      }
      final response = await completer.future.timeout(AppConfig.connectionTimeout);
      _log('command response: $response');
      return response;
    } catch (error) {
      _log('command failure for "$command": $error');
      rethrow;
    } finally {
      if (identical(_pendingResponse, completer)) _pendingResponse = null;
    }
  }

  void _ensureReady() {
    if (_device == null ||
        _txCharacteristic == null ||
        _rxCharacteristic == null) {
      throw StateError('Device connection was dropped.');
    }
  }

  void _onNotification(List<int> bytes) {
    _receiveBuffer += utf8.decode(bytes, allowMalformed: true);
    var newline = _receiveBuffer.indexOf('\n');
    while (newline >= 0) {
      final line = _receiveBuffer.substring(0, newline).trim();
      _receiveBuffer = _receiveBuffer.substring(newline + 1);
      if (line.isNotEmpty) _handleLine(line);
      newline = _receiveBuffer.indexOf('\n');
    }
  }

  void _handleLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded.containsKey('node') && decoded.containsKey('serial')) {
        _liveReadingsController.add(Map<String, dynamic>.from(decoded));
        return;
      }
    } on FormatException {
      // Text responses such as SN:... and TIME:... are expected.
    }
    final pending = _pendingResponse;
    if (pending != null && !pending.isCompleted) {
      pending.complete(line);
    } else {
      _log('unsolicited non-reading line ignored: $line');
    }
  }

  String _readCommand(String key) => switch (key) {
    'serial' => 'GET_SN', 'calibration' => 'GET_CAL', 'role' => 'GET_ROLE', 'clock' => 'GET_TIME', _ => throw ArgumentError('Unknown read key: $key'),
  };
  String _writeCommand(String key, dynamic value, DateTime? _) => switch (key) {
    'serial' => 'SET_SN:$value', 'temperature' => 'CAL_TEMP:$value', 'voltage' => 'CAL_VOLT:$value',
    'resetTemp' => 'RESET_TEMP_CAL', 'resetVolt' => 'RESET_VOLT_CAL', 'resetAll' => 'RESET_CAL',
    'master' => 'MAKE_MASTER', 'available' => 'MAKE_AVAILABLE', 'clock' => 'SET_TIME:$value',
    _ => throw ArgumentError('Unknown write key: $key'),
  };
  dynamic _decodeResponse(String response) {
    if (response.startsWith('SN:')) return response.substring(3);
    if (response.startsWith('TIME:')) return response.substring(5);
    try { return jsonDecode(response); } on FormatException { return response; }
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
