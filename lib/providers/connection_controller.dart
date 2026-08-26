import 'dart:async';

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

  DeviceDescriptor? lastDevice;
  DeviceDescriptor? descriptor;
  device.ConnectionState connectionState = device.ConnectionState.disconnected;
  String? errorMessage;
  bool connecting = false;
  int? batteryCount;
  Map<String, dynamic>? _liveStatus;

  device.DeviceConnection? get connection => _connection;
  Map<String, dynamic>? get liveStatus => _liveStatus;

  Future<bool> requestCameraPermission() => _permissions.requestCamera();

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
    _liveStatus = null;
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
      descriptor = target;
      lastDevice = target;
      try {
        _liveStatus = await candidate.getLiveStatus();
      } catch (_) {
        _liveStatus = null;
      }
      try {
        batteryCount = await candidate.getBatteryCount();
      } catch (_) {
        batteryCount = null;
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
    await _connection?.disconnect();
    _connection = null;
    descriptor = null;
    batteryCount = null;
    _liveStatus = null;
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

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _connection?.disconnect();
    super.dispose();
  }
}
