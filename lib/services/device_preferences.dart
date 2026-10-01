import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_descriptor.dart';

class DevicePreferences {
  static const _lastDeviceKey = 'last_connected_device';
  static const _connectionModeKey = 'connection_mode';
  static const _expectedBatteryCountPrefix = 'expected_battery_count_';
  static const _deviceNamesKey = 'device_names';

  Future<void> save(DeviceDescriptor descriptor) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _lastDeviceKey,
      jsonEncode(descriptor.toJson()),
    );
    await preferences.setString(_connectionModeKey, descriptor.mode.name);
  }

  Future<DeviceDescriptor?> loadLast() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_lastDeviceKey);
    if (raw == null) return null;
    try {
      return DeviceDescriptor.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await preferences.remove(_lastDeviceKey);
      return null;
    }
  }

  Future<int?> loadExpectedBatteryCount(String gatewayId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt('$_expectedBatteryCountPrefix$gatewayId');
  }

  Future<void> saveExpectedBatteryCount(String gatewayId, int? count) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '$_expectedBatteryCountPrefix$gatewayId';
    if (count == null) {
      await preferences.remove(key);
    } else {
      await preferences.setInt(key, count);
    }
  }

  Future<Map<String, String>> loadDeviceNames() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_deviceNamesKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on FormatException {
      await preferences.remove(_deviceNamesKey);
      return {};
    }
  }

  Future<void> saveDeviceName(String deviceId, String name) async {
    final names = await loadDeviceNames();
    names[deviceId] = name;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceNamesKey, jsonEncode(names));
  }
}
