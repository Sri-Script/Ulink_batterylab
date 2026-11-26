import 'dart:async';
import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import '../services/device_connection.dart';

class VtmDemoConnection implements DeviceConnection {
  final _state = StreamController<ConnectionState>.broadcast();
  bool _connected = false;
  @override String get deviceId => 'VTM-TEST';
  @override String get gatewayId => deviceId;
  @override String? get meshNodeId => null;
  @override TransportType get transportType => TransportType.ble;
  @override Stream<ConnectionState> get state => _state.stream;
  @override Stream<Map<String, dynamic>> get liveReadings => const Stream.empty();
  @override Future<bool> connect() async { _connected = true; _state.add(ConnectionState.connected); return true; }
  @override Future<void> disconnect() async { _connected = false; _state.add(ConnectionState.disconnected); }
  void _check() { if (!_connected) throw StateError('VTM demo is disconnected'); }
  @override Future<CalibrationReading> read(String key) async { _check(); return CalibrationReading(key: key, value: key == 'voltage' ? 3.7 : 25.0, timestamp: DateTime.now(), direction: 'read', status: 'success'); }
  @override Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async { _check(); return true; }
  @override Future<String> command(String command) async { _check(); return '{"demo":true}'; }
  @override Future<int> getBatteryCount() async { _check(); return 4; }
  @override Future<Map<String, dynamic>> getLiveStatus() async { _check(); return {'demo': true}; }
}
