/// Immutable U-Link provisioning values supplied at build/run time.
///
/// UUID defaults are deliberately blank: the U-Link provisioning path must
/// never fall back to the Battery Monitor's legacy UART service.
class UlinkBleProtocolConfig {
  const UlinkBleProtocolConfig({
    required this.namePrefix,
    required this.serviceUuid,
    required this.commandCharacteristicUuid,
    required this.responseCharacteristicUuid,
    required this.ackTimeout,
  });

  static const UlinkBleProtocolConfig environment = UlinkBleProtocolConfig(
    namePrefix: String.fromEnvironment(
      'ULINK_BLE_NAME_PREFIX',
      defaultValue: 'ULINK',
    ),
    serviceUuid: String.fromEnvironment('ULINK_BLE_SERVICE_UUID'),
    commandCharacteristicUuid: String.fromEnvironment(
      'ULINK_BLE_COMMAND_CHARACTERISTIC_UUID',
    ),
    responseCharacteristicUuid: String.fromEnvironment(
      'ULINK_BLE_RESPONSE_CHARACTERISTIC_UUID',
    ),
    ackTimeout: Duration(
      seconds: int.fromEnvironment('ULINK_ACK_TIMEOUT_SECONDS', defaultValue: 15),
    ),
  );

  final String namePrefix;
  final String serviceUuid;
  final String commandCharacteristicUuid;
  final String responseCharacteristicUuid;
  final Duration ackTimeout;

  bool get isConfigured =>
      serviceUuid.trim().isNotEmpty &&
      commandCharacteristicUuid.trim().isNotEmpty &&
      responseCharacteristicUuid.trim().isNotEmpty;

  String get normalizedNamePrefix => namePrefix.trim().toUpperCase();
}
