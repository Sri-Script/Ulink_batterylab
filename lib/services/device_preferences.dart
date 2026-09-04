import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_descriptor.dart';

class DevicePreferences {
  static const _lastDeviceKey = 'last_connected_device';
  static const _connectionModeKey = 'connection_mode';
  static const _expectedBatteryCountPrefix = 'expected_battery_count_';

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
}
