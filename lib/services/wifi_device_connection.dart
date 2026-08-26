import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import '../config/app_config.dart';
import '../models/calibration_reading.dart';
import '../models/device_descriptor.dart';
import 'device_connection.dart';

class WifiDeviceConnection implements DeviceConnection {
  WifiDeviceConnection(this.descriptor, {http.Client? client})
    : _client = client ?? http.Client();

  final DeviceDescriptor descriptor;
  final http.Client _client;
  final _stateController = StreamController<ConnectionState>.broadcast();
  Map<String, dynamic>? _status;

  Uri _uri(String path) =>
      Uri.parse('http://${descriptor.ip}:${descriptor.port ?? 80}$path');
  @override
  String get deviceId => descriptor.deviceId;
  @override
  String get gatewayId => descriptor.gatewayId ?? descriptor.deviceId;
  @override
  String? get meshNodeId => descriptor.meshNodeId;
  @override
  TransportType get transportType => TransportType.wifi;
  @override
  Stream<ConnectionState> get state => _stateController.stream;

  @override
  Future<bool> connect() async {
    _stateController.add(ConnectionState.connecting);
    try {
      final phoneIp = await NetworkInfo().getWifiIP();
      if (phoneIp == null || !_sameIpv4Subnet(phoneIp, descriptor.ip!)) {
        throw StateError(
          'Phone is not on the ESP32 network (${descriptor.ip}).',
        );
      }
      final response = await _client
          .get(_uri('/status'))
          .timeout(AppConfig.connectionTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('ESP32 status check returned ${response.statusCode}.');
      }
      final status = jsonDecode(response.body);
      if (status is! Map<String, dynamic> ||
          status['deviceId']?.toString() != descriptor.deviceId) {
        throw StateError(
          'The discovered gateway does not match the scanned device.',
        );
      }
      _status = status;
      _stateController.add(ConnectionState.connected);
      return true;
    } catch (_) {
      _stateController.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  bool _sameIpv4Subnet(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    return left.length == 4 &&
        right.length == 4 &&
        left.take(3).join('.') == right.take(3).join('.');
  }

  @override
  Future<void> disconnect() async {
    _client.close();
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Future<CalibrationReading> read(String key) async {
    try {
      final response = await _client
          .get(_uri('/calibrate/${Uri.encodeComponent(key)}'))
          .timeout(AppConfig.connectionTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Read failed (${response.statusCode}).');
      }
      return CalibrationReading.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        key: key,
      );
    } catch (_) {
      _stateController.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<bool> write(String key, dynamic value, {DateTime? timestamp}) async {
    try {
      final response = await _client
          .post(
            _uri('/calibrate/${Uri.encodeComponent(key)}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'value': value,
              'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
            }),
          )
          .timeout(AppConfig.connectionTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Write failed (${response.statusCode}).');
      }
      return true;
    } catch (_) {
      _stateController.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<int> getBatteryCount() async {
    var status = _status;
    if (status == null) {
      final response = await _client
          .get(_uri('/status'))
          .timeout(AppConfig.connectionTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Gateway status is unavailable.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['deviceId']?.toString() != descriptor.deviceId) {
        throw StateError('Gateway identity could not be verified.');
      }
      status = decoded;
      _status = decoded;
    }
    final count = status['batteryCount'];
    if (count is! num || count < 0) {
      throw const FormatException('Invalid battery count response.');
    }
    return count.toInt();
  }

  @override
  Future<Map<String, dynamic>> getLiveStatus() async {
    try {
      final response = await _client
          .get(_uri('/status'))
          .timeout(AppConfig.connectionTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Gateway live status is unavailable.');
      }
      final status = jsonDecode(response.body);
      if (status is! Map<String, dynamic> ||
          status['deviceId']?.toString() != descriptor.deviceId ||
          status['devices'] is! List) {
        throw const FormatException('Invalid live status response.');
      }
      _status = status;
      return status;
    } catch (_) {
      _stateController.add(ConnectionState.disconnected);
      rethrow;
    }
  }
}
