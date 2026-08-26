import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';

enum ConnectionState { disconnected, connecting, connected, reconnecting }

abstract class DeviceConnection {
  String get deviceId;
  String get gatewayId;
  String? get meshNodeId;
  TransportType get transportType;
  Future<bool> connect();
  Future<void> disconnect();
  Stream<ConnectionState> get state;
  Future<CalibrationReading> read(String key);
  Future<bool> write(String key, dynamic value, {DateTime? timestamp});
  Future<int> getBatteryCount();
  Future<Map<String, dynamic>> getLiveStatus();
}
