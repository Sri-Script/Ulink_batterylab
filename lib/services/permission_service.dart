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
      // Android 11 and earlier uses location for BLE discovery. It is capped
      // in the manifest, so Android 12+ ignores this legacy request.
      Permission.locationWhenInUse,
    ].request();
    final modernGranted =
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;
    final legacyGranted =
        statuses[Permission.locationWhenInUse]?.isGranted == true;
    return modernGranted || legacyGranted;
  }

  Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.notification.request()).isGranted;
  }
}
