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
  bool _isDeviceConnected = false;
  bool _notificationsEnabled = false;
  bool _notificationSetupInProgress = false;
  Future<bool>? _connectInFlight;
  Future<void> _gattTail = Future<void>.value();
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
  Future<bool> connect() {
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      _log('connect ignored: an attempt is already running');
      return inFlight;
    }
    final attempt = _connectInternal();
    _connectInFlight = attempt;
    return attempt.whenComplete(() => _connectInFlight = null);
  }

  Future<bool> _connectInternal() async {
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
      final connected = Completer<void>();
      _connectionSubscription = _device!.connectionState.listen((state) {
        _isDeviceConnected = state == BluetoothConnectionState.connected;
        _log('connection state: $state');
        _stateController.add(
          _isDeviceConnected
              ? app.ConnectionState.connected
              : app.ConnectionState.disconnected,
        );
        if (_isDeviceConnected && !connected.isCompleted) {
          connected.complete();
        }
        if (!_isDeviceConnected) {
          _notificationsEnabled = false;
          final notifications = _notificationSubscription;
          _notificationSubscription = null;
          notifications?.cancel();
        }
      });
      // flutter_blue_plus otherwise requests MTU 512 automatically on Android.
      // The UART protocol does not require an MTU change, and avoiding that
      // extra GATT request keeps service discovery and CCCD writes serialized.
      await _connectWithAndroidRecovery(_device!);
      await connected.future.timeout(AppConfig.connectionTimeout);
      _log('connect success; waiting before GATT service discovery');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _ensureConnectedForSetup('service discovery');
      _log('beginning GATT service discovery');
      final services = await _runGatt(
        'discoverServices',
            () => _device!.discoverServices(),
      );
      _log('discoverServices success: ${services.length} service(s)');
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
      _log('service found: ${service.uuid}');
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
      _log('characteristics found: RX=${_rxCharacteristic!.uuid}, TX=${_txCharacteristic!.uuid}');
      if (!_rxCharacteristic!.properties.write && !_rxCharacteristic!.properties.writeWithoutResponse) {
        throw StateError('Nordic UART RX is not writable.');
      }
      if (!_txCharacteristic!.properties.notify && !_txCharacteristic!.properties.indicate) {
        throw StateError('Nordic UART TX does not support notifications or indications.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _ensureConnectedForSetup('notification subscription');
      await _startNotificationStream(_txCharacteristic!);
      await _subscribeToNotifications(_txCharacteristic!);
      _stateController.add(app.ConnectionState.connected);
      _log('Nordic UART ready: RX=${_rxCharacteristic!.uuid}, TX=${_txCharacteristic!.uuid}');
      return true;
    } catch (error) {
      _log('connect/GATT failure: $error');
      await FlutterBluePlus.stopScan();
      await _connectionSubscription?.cancel();
      await _notificationSubscription?.cancel();
      _connectionSubscription = null;
      _isDeviceConnected = false;
      _notificationsEnabled = false;
      _notificationSetupInProgress = false;
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

  /// Android status 133 is a generic GATT-link failure. Release the partial
  /// native link before retrying; do not retry service discovery or CCCD
  /// writes here, because those are separately serialized by [_runGatt].
  Future<void> _connectWithAndroidRecovery(BluetoothDevice device) async {
    const maxAttempts = 3;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _log('connect attempt $attempt of $maxAttempts');
        await device.connect(
          timeout: AppConfig.connectionTimeout,
          // Avoid flutter_blue_plus's automatic Android MTU request. The
          // Nordic UART protocol works at the default MTU and this prevents
          // an extra GATT request from racing service discovery/CCCD setup.
          mtu: null,
        );
        _log('connect attempt $attempt succeeded');
        return;
      } catch (error) {
        lastError = error;
        _log('connect attempt $attempt failed: $error');

        // Even a failed Android connect may leave a stale GATT client.
        try {
          await device.disconnect();
        } catch (disconnectError) {
          _log('cleanup after failed connect: $disconnectError');
        }

        if (!_isAndroidGatt133(error) || attempt == maxAttempts) break;
        final delay = Duration(milliseconds: 500 * attempt);
        _log('Android GATT 133; retrying in ${delay.inMilliseconds}ms');
        await Future<void>.delayed(delay);
      }
    }
    throw lastError ?? StateError('Bluetooth connection failed.');
  }

  bool _isAndroidGatt133(Object error) {
    final message = error.toString();
    return message.contains('android-code: 133') ||
        message.contains('android-code:133');
  }

  @override
  Future<void> disconnect() async {
    _log('disconnect requested');
    try {
      await _connectionSubscription?.cancel();
      await _notificationSubscription?.cancel();
      await _gattTail;
      await _device?.disconnect();
    } catch (error) {
      _log('disconnect failure: $error');
      rethrow;
    } finally {
      _connectionSubscription = null;
      _notificationSubscription = null;
    }
    _device = null;
    _isDeviceConnected = false;
    _notificationsEnabled = false;
    _notificationSetupInProgress = false;
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

  void _ensureConnectedForSetup(String step) {
    if (!_isDeviceConnected) {
      throw StateError('Device disconnected before $step. Reconnect and try again.');
    }
  }

  Future<void> _startNotificationStream(
      BluetoothCharacteristic characteristic,
      ) async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = characteristic.onValueReceived.listen(_onNotification);
    _log('live-data stream subscribed: ${characteristic.uuid}');
  }

  Future<void> _subscribeToNotifications(
      BluetoothCharacteristic characteristic,
      ) async {
    if (_notificationsEnabled || characteristic.isNotifying) {
      _notificationsEnabled = true;
      _log('notifications already enabled: ${characteristic.uuid}');
      return;
    }
    if (_notificationSetupInProgress) {
      throw StateError('Notification setup is already in progress.');
    }
    _notificationSetupInProgress = true;
    try {
      await _enableNotificationsWithRetry(characteristic);
      _notificationsEnabled = true;
    } finally {
      _notificationSetupInProgress = false;
    }
  }

  Future<void> _enableNotificationsWithRetry(
      BluetoothCharacteristic characteristic,
      ) async {
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _ensureConnectedForSetup('notification subscription');
      _log('notify attempt $attempt of $maxAttempts: ${characteristic.uuid}');
      try {
        final enabled = await _runGatt(
          'setNotifyValue attempt $attempt for ${characteristic.uuid}',
              () => characteristic.setNotifyValue(
            true,
            timeout: 15,
            forceIndications: !characteristic.properties.notify &&
                characteristic.properties.indicate,
          ),
        );
        if (!enabled) {
          throw StateError('Device does not expose a CCCD for ${characteristic.uuid}.');
        }
        _log('notify success on attempt $attempt');
        return;
      } catch (error) {
        lastError = error;
        _log('notify attempt $attempt failed: $error');
        if (!_isAndroidGattBusy(error) || attempt == maxAttempts) break;
        _ensureConnectedForSetup('notification retry');
        final retryDelay = Duration(seconds: 1 << (attempt - 1));
        _log('Android GATT busy; retrying notification setup in ${retryDelay.inMilliseconds}ms');
        await Future<void>.delayed(retryDelay);
      }
    }
    if (_isAndroidGattBusy(lastError ?? StateError('unknown error'))) {
      throw StateError(
        'Failed to subscribe to device notifications after 3 attempts. '
            'Android Bluetooth is busy; disconnect, wait briefly, then reconnect.',
      );
    }
    throw StateError(
      'Failed to subscribe to device notifications. '
          'The device did not accept its notification subscription; reconnect and try again.',
    );
  }

  bool _isAndroidGattBusy(Object error) {
    final message = error.toString();
    return message.contains('ERROR_GATT_WRITE_REQUEST_BUSY') ||
        message.contains('gatt.writeDescriptor() returned 201');
  }

  Future<T> _runGatt<T>(String operation, Future<T> Function() action) async {
    final previous = _gattTail;
    final completed = Completer<void>();
    _gattTail = completed.future;
    await previous;
    try {
      _ensureConnectedForSetup(operation);
      _log('GATT begin: $operation');
      final result = await action();
      _log('GATT success: $operation');
      return result;
    } catch (error) {
      _log('GATT failure: $operation: $error');
      rethrow;
    } finally {
      completed.complete();
    }
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
      final withoutResponse =
          !characteristic.properties.write &&
              characteristic.properties.writeWithoutResponse;
      // Nordic UART firmware commonly uses the default 20-byte ATT payload.
      // Commands are plain byte streams, so it is safe to split a long SET_TIME
      // or SET_SN command while preserving its terminating newline. Prefer
      // write-with-response whenever the peripheral supports it so Android can
      // complete one GATT request before the next chunk is sent.
      for (var offset = 0; offset < payload.length; offset += 20) {
        final end = (offset + 20 < payload.length) ? offset + 20 : payload.length;
        await _runGatt(
          'write command chunk ${offset ~/ 20 + 1} for $command',
              () => characteristic.write(
            payload.sublist(offset, end),
            withoutResponse: withoutResponse,
            timeout: 15,
          ),
        );
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
    if (!kDebugMode) return;
    final bleId = _device?.remoteId.str ?? descriptor.bleDeviceId ?? 'unknown';
    debugPrint('Ulink BLE ${DateTime.now().toIso8601String()} [$bleId]: $message');
  }
}
