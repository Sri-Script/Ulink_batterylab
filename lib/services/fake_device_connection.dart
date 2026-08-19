import 'dart:async';

import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import '../config/device_contract.dart';
import 'device_connection.dart';

class FakeDeviceConnection implements DeviceConnection {
  FakeDeviceConnection(this.descriptor);

  final DeviceDescriptor descriptor;
  final _stateController = StreamController<ConnectionState>.broadcast();
  final Map<String, dynamic> _values = {
    'zero': 0,
    'reference': 12.5,
    'timestamped': 10.0,
  };
  bool _connected = false;

  @override
  String get deviceId => descriptor.deviceId;
  @override
  String get gatewayId => descriptor.gatewayId ?? descriptor.deviceId;
  @override
  String? get meshNodeId => descriptor.meshNodeId;
  @override
  TransportType get transportType => descriptor.mode;
  @override
  Stream<ConnectionState> get state => _stateController.stream;

  @override
  Future<bool> connect() async {
    _stateController.add(ConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    _connected = true;
    _stateController.add(ConnectionState.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _stateController.add(ConnectionState.disconnected);
  }

  void _ensureConnected() {
    if (!_connected) throw StateError('Device connection was dropped.');
  }

  @override
  Future<CalibrationReading> read(String key) async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return CalibrationReading(
      key: key,
      value: _values[key] ?? 0,
      timestamp: DateTime.now(),
      direction: 'read',
      status: 'success',
    );
  }

  @override
  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _values[key] = value;
    return true;
  }

  @override
  Future<int> getBatteryCount() async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return DeviceContract.testStatusPayload['batteryCount']! as int;
  }
}
