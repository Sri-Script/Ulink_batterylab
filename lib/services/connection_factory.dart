import '../config/app_config.dart';
import '../models/device_descriptor.dart';
import 'ble_device_connection.dart';
import 'device_connection.dart';
import 'fake_device_connection.dart';
import 'wifi_device_connection.dart';

class ConnectionFactory {
  const ConnectionFactory._();

  static DeviceConnection create(DeviceDescriptor descriptor) {
    if (AppConfig.demoMode) return FakeDeviceConnection(descriptor);
    return switch (descriptor.mode) {
      TransportType.ble => BleDeviceConnection(descriptor),
      TransportType.wifi => WifiDeviceConnection(descriptor),
    };
  }
}
