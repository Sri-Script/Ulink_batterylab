/// Immutable U-Link provisioning values supplied at build/run time.
///
/// Rev4 values are deployed production defaults. Dart defines may override
/// them for later hardware revisions, but blank values never disable Rev4.
class UlinkBleProtocolConfig {
  const UlinkBleProtocolConfig({
    required this.namePrefix,
    required this.serviceUuid,
    required this.commandCharacteristicUuid,
    required this.responseCharacteristicUuid,
    required this.ackTimeout,
  });

  static const productionNamePrefix = 'ULINK';
  static const productionServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const productionCommandCharacteristicUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const productionResponseCharacteristicUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const productionAckTimeout = Duration(seconds: 15);

  static final UlinkBleProtocolConfig environment =
      UlinkBleProtocolConfig.fromEnvironmentValues(
        namePrefix: const String.fromEnvironment('ULINK_BLE_NAME_PREFIX'),
        serviceUuid: const String.fromEnvironment('ULINK_BLE_SERVICE_UUID'),
        commandCharacteristicUuid: const String.fromEnvironment(
          'ULINK_BLE_COMMAND_CHARACTERISTIC_UUID',
        ),
        responseCharacteristicUuid: const String.fromEnvironment(
          'ULINK_BLE_RESPONSE_CHARACTERISTIC_UUID',
        ),
        ackTimeoutSeconds: const String.fromEnvironment(
          'ULINK_ACK_TIMEOUT_SECONDS',
        ),
      );

  /// Resolves optional build-time override values, falling back when a value
  /// is absent, blank, or (for timeouts) not a positive integer.
  factory UlinkBleProtocolConfig.fromEnvironmentValues({
    String? namePrefix,
    String? serviceUuid,
    String? commandCharacteristicUuid,
    String? responseCharacteristicUuid,
    String? ackTimeoutSeconds,
  }) => UlinkBleProtocolConfig(
    namePrefix: _valueOrDefault(namePrefix, productionNamePrefix),
    serviceUuid: _valueOrDefault(serviceUuid, productionServiceUuid),
    commandCharacteristicUuid: _valueOrDefault(
      commandCharacteristicUuid,
      productionCommandCharacteristicUuid,
    ),
    responseCharacteristicUuid: _valueOrDefault(
      responseCharacteristicUuid,
      productionResponseCharacteristicUuid,
    ),
    ackTimeout: Duration(seconds: _timeoutSeconds(ackTimeoutSeconds)),
  );

  final String namePrefix;
  final String serviceUuid;
  final String commandCharacteristicUuid;
  final String responseCharacteristicUuid;
  final Duration ackTimeout;

  String? get validationError {
    if (normalizedNamePrefix.isEmpty) {
      return 'U-Link BLE name prefix is invalid.';
    }
    if (!_isUuid(serviceUuid)) {
      return 'U-Link BLE service UUID is invalid.';
    }
    if (!_isUuid(commandCharacteristicUuid)) {
      return 'U-Link BLE command characteristic UUID is invalid.';
    }
    if (!_isUuid(responseCharacteristicUuid)) {
      return 'U-Link BLE response characteristic UUID is invalid.';
    }
    if (ackTimeout <= Duration.zero) {
      return 'U-Link BLE acknowledgement timeout is invalid.';
    }
    return null;
  }

  bool get isConfigured => validationError == null;

  String get normalizedNamePrefix => namePrefix.trim().toUpperCase();

  static String _valueOrDefault(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static int _timeoutSeconds(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    return seconds == null || seconds <= 0
        ? productionAckTimeout.inSeconds
        : seconds;
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value.trim());
}
