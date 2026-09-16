import 'dart:async';

import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import '../config/device_contract.dart';
import 'device_connection.dart';

class FakeDeviceConnection implements DeviceConnection {
  FakeDeviceConnection(this.descriptor);

  final DeviceDescriptor descriptor;
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _liveReadingsController = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _liveTimer;
  final Map<String, dynamic> _values = {
    'zero': 0,
    'reference': 12.5,
    'timestamped': 10.0,
    'clock': DateTime.now().toIso8601String(),
    'voltage': 3.7,
    'telemetry': 12.0,
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
  Stream<Map<String, dynamic>> get liveReadings => _liveReadingsController.stream;

  @override
  Future<bool> connect() async {
    _stateController.add(ConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    _connected = true;
    _emitReading();
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _emitReading());
    _stateController.add(ConnectionState.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _liveTimer?.cancel();
    _stateController.add(ConnectionState.disconnected);
  }

  void _ensureConnected() {
    if (!_connected) throw StateError('Device connection was dropped.');
  }

  @override
  Future<CalibrationReading> read(String key) async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (key == 'telemetry') {
      // Small jitter so polling looks alive in demo mode.
      final jitter = (DateTime.now().millisecondsSinceEpoch % 200 - 100) / 100;
      _values['telemetry'] = (_values['telemetry'] as double) + jitter;
    }
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
  Future<String> command(String command) async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final input = command.trim();
    if (input == 'GET_SN') return 'SN:BATTERY-001';
    if (input.startsWith('SET_SN:')) return 'SN UPDATED';
    if (input == 'GET_CAL') return '{"serial":"BATTERY-001","temp_factor":1.0,"temp_true_ref":25.0,"temp_calibrated":true,"volt_factor":1.0,"volt_true_ref":3.7,"volt_calibrated":true}';
    if (input == 'GET_ROLE') return '{"serial":"BATTERY-001","role":"AVAILABLE"}';
    if (input == 'GET_TIME') return 'TIME:${DateTime.now().toIso8601String()}';
    if (input.startsWith('SET_TIME:')) return 'TIME UPDATED';
    if (input.startsWith('CAL_TEMP:') || input.startsWith('CAL_VOLT:')) return '{"serial":"BATTERY-001","detected_temp":24.8,"true_temp":25.0,"temp_factor":1.008,"calibrated_temp":25.0}';
    return '{"serial":"BATTERY-001","ok":true}';
  }

  void _emitReading() {
    if (!_connected) return;
    final jitter = (DateTime.now().millisecond - 500) / 1000;
    _liveReadingsController.add({
      'node': 1,
      'serial': 'BATTERY-001',
      'datetime': DateTime.now().toIso8601String(),
      'temperature': 25.0 + jitter,
      'voltage': 3.70 + jitter / 20,
    });
  }

  @override
  Future<int> getBatteryCount() async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return DeviceContract.testStatusPayload['batteryCount']! as int;
  }

  @override
  Future<Map<String, dynamic>> getLiveStatus() async {
    _ensureConnected();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return {
      'mesh': DeviceContract.fakeGatewayIsMesh,
      'gatewayId': gatewayId,
      'devices': [
        {'id': 'batt-1', 'live': true, 'voltage': 3.71},
        {'id': 'batt-2', 'live': false, 'voltage': null},
        {'id': 'batt-3', 'live': true, 'voltage': 3.68},
      ],
    };
  }
}
