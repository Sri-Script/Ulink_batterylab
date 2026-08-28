import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';

class PermissionService {
  Future<bool> requestCamera() async {
    if (AppConfig.demoMode) return true;
    return (await Permission.camera.request()).isGranted;
  }

  Future<bool> requestBle() async {
    if (AppConfig.demoMode || !Platform.isAndroid) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    // Android 11 and earlier require location at runtime for BLE discovery.
    // The manifest caps this permission at API 30, so newer Android versions
    // do not receive an unnecessary location grant.
    await Permission.locationWhenInUse.request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.notification.request()).isGranted;
  }
}
