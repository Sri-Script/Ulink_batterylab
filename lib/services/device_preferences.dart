import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_descriptor.dart';

class DevicePreferences {
  static const _lastDeviceKey = 'last_connected_device';
  static const _connectionModeKey = 'connection_mode';

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
}
