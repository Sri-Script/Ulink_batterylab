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
    // On Android 12+ these are the runtime "Nearby devices" permissions.
    // On Android 11 and earlier permission_handler reports the manifest's
    // normal Bluetooth permissions as granted; location remains required for
    // scan result visibility and is requested above.
    final bluetoothGranted =
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;
    final legacyGranted =
        statuses[Permission.locationWhenInUse]?.isGranted == true;
    // Location is declared only through API 30 in AndroidManifest.xml. On
    // Android 12+ it therefore cannot authorize a scan; the Bluetooth grants
    // above do. On Android 11 and older the normal Bluetooth manifest grants
    // plus location authorize scanning.
    return bluetoothGranted || legacyGranted;
  }

  Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.notification.request()).isGranted;
  }
}
