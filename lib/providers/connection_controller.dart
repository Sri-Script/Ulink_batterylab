import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/calibration_log_entry.dart';
import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import '../services/calibration_database.dart';
import '../services/connection_factory.dart';
import '../services/device_connection.dart' as device;
import '../services/device_preferences.dart';
import '../services/permission_service.dart';

class ConnectionController extends ChangeNotifier {
  ConnectionController({
    DevicePreferences? preferences,
    CalibrationDatabase? database,
    PermissionService? permissions,
  }) : _preferences = preferences ?? DevicePreferences(),
       _database = database ?? CalibrationDatabase.instance,
       _permissions = permissions ?? PermissionService();

  final DevicePreferences _preferences;
  final CalibrationDatabase _database;
  final PermissionService _permissions;
  device.DeviceConnection? _connection;
  StreamSubscription<device.ConnectionState>? _stateSubscription;
  StreamSubscription<Map<String, dynamic>>? _liveReadingsSubscription;

  DeviceDescriptor? lastDevice;
  DeviceDescriptor? descriptor;
  device.ConnectionState connectionState = device.ConnectionState.disconnected;
  String? errorMessage;
  bool connecting = false;
  int? batteryCount;
  int? expectedBatteryCount;
  Map<String, dynamic>? _liveStatus;
  Map<String, dynamic>? calibrationStatus;
  final Map<String, Map<String, dynamic>> _liveDevicesBySerial = {};
  final Map<String, int> _liveUpdateSequences = {};

  device.DeviceConnection? get connection => _connection;
  Map<String, dynamic>? get liveStatus => _liveStatus;
  List<Map<String, dynamic>> get liveDevices => _liveDevicesBySerial.values.toList();
  int liveUpdateSequence(String serial) => _liveUpdateSequences[serial] ?? 0;

  /// The count reported by the status response. A mesh status is authoritative
  /// because it lists every battery, including offline ones.
  int? get reportedBatteryCount {
    final status = _liveStatus;
    final count = status?['batteryCount'];
    if (count is num) return count.toInt();
    final devices = status?['devices'];
    if (devices is List) return devices.length;
    return batteryCount;
  }

  bool get hasBatteryCountMismatch =>
      expectedBatteryCount != null &&
      reportedBatteryCount != null &&
      expectedBatteryCount != reportedBatteryCount;

  Future<bool> requestCameraPermission() => _permissions.requestCamera();

  Future<bool> requestBle() => _permissions.requestBle();

  Future<void> initialize() async {
    lastDevice = await _preferences.loadLast();
    notifyListeners();
  }

  Future<bool> connect(
    DeviceDescriptor target, {
    bool reconnect = false,
  }) async {
    errorMessage = null;
    batteryCount = null;
    expectedBatteryCount = null;
    _liveStatus = null;
    calibrationStatus = null;
    _liveDevicesBySerial.clear();
    _liveUpdateSequences.clear();
    connecting = true;
    connectionState = reconnect
        ? device.ConnectionState.reconnecting
        : device.ConnectionState.connecting;
    notifyListeners();
    try {
      if (target.mode == TransportType.ble &&
          !await _permissions.requestBle()) {
        throw StateError('Bluetooth scan/connect permission was denied.');
      }
      await _stateSubscription?.cancel();
      await _liveReadingsSubscription?.cancel();
      await _connection?.disconnect();
      final candidate = ConnectionFactory.create(target);
      _stateSubscription = candidate.state.listen((state) {
        connectionState = state;
        notifyListeners();
      });
      final success = await candidate.connect();
      if (!success) {
        throw StateError('Could not connect to ${target.deviceId}.');
      }
      _connection = candidate;
      _liveReadingsSubscription = candidate.liveReadings.listen((reading) {
        final serial = reading['serial']?.toString();
        if (serial == null || serial.isEmpty) return;
        _liveDevicesBySerial[serial] = reading;
        _liveUpdateSequences[serial] = (_liveUpdateSequences[serial] ?? 0) + 1;
        notifyListeners();
      });
      descriptor = target;
      lastDevice = target;
      expectedBatteryCount = await _preferences.loadExpectedBatteryCount(
        candidate.gatewayId,
      );
      try {
        calibrationStatus = _jsonMap(await candidate.command('GET_CAL'));
      } catch (_) {
        calibrationStatus = null;
      }
      if (target.mode == TransportType.ble) {
        try {
          // This synchronizes only the directly-connected BLE device, whatever
          // its role (MASTER or AVAILABLE). ESP-NOW-relayed SLAVE nodes have no
          // phone BLE link; syncing them needs a firmware relay capability.
          await candidate.command('SET_TIME:${DateTime.now().toIso8601String()}');
          debugPrint('Ulink: synced directly-connected device clock on connect.');
        } catch (error) {
          // Clock sync is additive; a device with an older firmware command set
          // must still remain connected and usable for calibration.
          debugPrint('Ulink: automatic clock sync failed: $error');
        }
      }
      await _preferences.save(target);
      return true;
    } catch (error) {
      errorMessage = _cleanError(error);
      connectionState = device.ConnectionState.disconnected;
      return false;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _stateSubscription?.cancel();
    await _liveReadingsSubscription?.cancel();
    await _connection?.disconnect();
    _connection = null;
    descriptor = null;
    batteryCount = null;
    expectedBatteryCount = null;
    _liveStatus = null;
    calibrationStatus = null;
    _liveDevicesBySerial.clear();
    _liveUpdateSequences.clear();
    connectionState = device.ConnectionState.disconnected;
    notifyListeners();
  }

  Future<CalibrationReading> read(String key) async {
    final active = _requireConnection();
    try {
      final reading = await active.read(key);
      await _database.insert(active.deviceId, reading);
      return reading;
    } catch (error) {
      await _recordFailure(active.deviceId, key, 'read', error);
      rethrow;
    }
  }

  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    final active = _requireConnection();
    final occurredAt = timestamp ?? DateTime.now();
    try {
      final success = await active.write(key, value, timestamp: occurredAt);
      final reading = CalibrationReading(
        key: key,
        value: value,
        timestamp: occurredAt,
        direction: 'write',
        status: success ? 'success' : 'error',
      );
      await _database.insert(active.deviceId, reading);
      return success;
    } catch (error) {
      await _recordFailure(active.deviceId, key, 'write', error);
      rethrow;
    }
  }

  Future<String> command(String command, {String logKey = 'command'}) async {
    final active = _requireConnection();
    try {
      final response = await active.command(command);
      await _database.insert(active.deviceId, CalibrationReading(key: logKey, value: response, timestamp: DateTime.now(), direction: 'command', status: 'success'));
      return response;
    } catch (error) {
      await _recordFailure(active.deviceId, logKey, 'command', error);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> refreshCalibrationStatus() async {
    calibrationStatus = _jsonMap(await command('GET_CAL', logKey: 'calibrationStatus'));
    notifyListeners();
    return calibrationStatus!;
  }

  Future<List<CalibrationLogEntry>> history() async {
    final id = descriptor?.deviceId ?? lastDevice?.deviceId;
    return id == null ? [] : _database.entriesFor(id);
  }

  Future<Map<String, dynamic>> refreshLiveStatus() async {
    final status = await _requireConnection().getLiveStatus();
    _liveStatus = status;
    notifyListeners();
    return status;
  }

  Future<void> setExpectedBatteryCount(int? count) async {
    if (count != null && count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least 1');
    }
    final gatewayId = _requireConnection().gatewayId;
    await _preferences.saveExpectedBatteryCount(gatewayId, count);
    expectedBatteryCount = count;
    notifyListeners();
  }

  device.DeviceConnection _requireConnection() {
    final active = _connection;
    if (active == null || connectionState != device.ConnectionState.connected) {
      throw StateError('Device is disconnected. Reconnect before calibrating.');
    }
    return active;
  }

  Future<void> _recordFailure(
    String deviceId,
    String key,
    String direction,
    Object error,
  ) => _database.insert(
    deviceId,
    CalibrationReading(
      key: key,
      value: _cleanError(error),
      timestamp: DateTime.now(),
      direction: direction,
      status: 'error',
    ),
  );

  String _cleanError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^(StateError|Exception):\s*'), '');

  Map<String, dynamic> _jsonMap(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('Expected a JSON object from the device.');
    return Map<String, dynamic>.from(decoded);
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _liveReadingsSubscription?.cancel();
    _connection?.disconnect();
    super.dispose();
  }
}
