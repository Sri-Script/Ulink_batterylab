class UlinkUrlResponse {
  const UlinkUrlResponse({
    required this.result,
    required this.message,
    required this.urlApiHttp,
    required this.urlApiHttps,
    required this.urlApplication,
  });

  factory UlinkUrlResponse.fromJson(Map<String, dynamic> json) =>
      UlinkUrlResponse(
        result: _asInt(json['Result']),
        message: json['Message']?.toString() ?? '',
        urlApiHttp: json['URL_API_HTTP']?.toString() ?? '',
        urlApiHttps: json['URL_API_HTTPS']?.toString() ?? '',
        urlApplication: json['URL_Application']?.toString() ?? '',
      );

  final int result;
  final String message;
  final String urlApiHttp;
  final String urlApiHttps;
  final String urlApplication;
}

class UlinkSettingsResponse {
  const UlinkSettingsResponse({
    required this.result,
    required this.message,
    required this.isActive,
    required this.appType,
    required this.callbackInterval,
    required this.sendMessageInterval,
    required this.serverDateTime,
    required this.token,
    required this.deviceCount,
    required this.devices,
  });

  factory UlinkSettingsResponse.fromJson(Map<String, dynamic> json) =>
      UlinkSettingsResponse(
        result: _asInt(json['Result']),
        message: json['Message']?.toString() ?? '',
        isActive: _asInt(json['IsActive']),
        appType: json['AppType']?.toString() ?? '',
        callbackInterval: _asInt(json['CallbackInterval']),
        sendMessageInterval: _asInt(json['SendMessageInterval']),
        serverDateTime: json['ServerDateTime']?.toString() ?? '',
        token: json['Token']?.toString() ?? '',
        deviceCount: _asInt(json['DeviceCount']),
        devices: _asMapList(json['Devices'])
            .map(UlinkSettingsDevice.fromJson)
            .toList(growable: false),
      );

  final int result;
  final String message;
  final int isActive;
  final String appType;
  final int callbackInterval;
  final int sendMessageInterval;
  final String serverDateTime;
  final String token;
  final int deviceCount;
  final List<UlinkSettingsDevice> devices;
}

class UlinkSettingsDevice {
  const UlinkSettingsDevice({
    required this.id,
    required this.code,
    required this.byteSequence,
    required this.addressMode,
    required this.parameterCount,
    required this.deviceParameters,
  });

  factory UlinkSettingsDevice.fromJson(Map<String, dynamic> json) =>
      UlinkSettingsDevice(
        id: _asInt(json['ID']),
        code: json['Code']?.toString() ?? '',
        byteSequence: json['ByteSequence']?.toString() ?? '',
        addressMode: json['AddressMode']?.toString() ?? '',
        parameterCount: _asInt(json['ParameterCount']),
        deviceParameters: _asMapList(json['DeviceParameters'])
            .map(UlinkDeviceParameter.fromJson)
            .toList(growable: false),
      );

  final int id;
  final String code;
  final String byteSequence;
  final String addressMode;
  final int parameterCount;
  final List<UlinkDeviceParameter> deviceParameters;
}

class UlinkDeviceParameter {
  const UlinkDeviceParameter({
    required this.serial,
    required this.dataType,
    required this.address,
    required this.register,
  });

  factory UlinkDeviceParameter.fromJson(Map<String, dynamic> json) =>
      UlinkDeviceParameter(
        serial: _asInt(json['Serial']),
        dataType: json['DataType']?.toString() ?? '',
        address: json['Address']?.toString() ?? '',
        register: json['Register']?.toString() ?? '',
      );

  final int serial;
  final String dataType;
  final String address;
  final String register;
}

class UlinkPostRecordResponse {
  const UlinkPostRecordResponse({
    required this.result,
    required this.message,
    required this.isSendMessage,
    required this.sendMessageTo,
    required this.messageContent,
    required this.userCommand1,
    required this.userCommand2,
    required this.relayCommand1,
    required this.relayCommand2,
    required this.token,
    required this.deviceCount,
    required this.rawJson,
  });

  factory UlinkPostRecordResponse.fromJson(Map<String, dynamic> json) {
    final userCommands = _asMap(json['UserCommands']);
    final relayCommands = _asMap(json['RelayCommands']);
    return UlinkPostRecordResponse(
      result: _asInt(json['Result']),
      message: json['Message']?.toString() ?? '',
      isSendMessage: _asInt(json['IsSendMessage']),
      sendMessageTo: json['SendMessageTo']?.toString() ?? '',
      messageContent: json['MessageContent']?.toString() ?? '',
      userCommand1: _asInt(userCommands['UserCommand1']),
      userCommand2: _asInt(userCommands['UserCommand2']),
      relayCommand1: _asInt(relayCommands['RelayCommand1']),
      relayCommand2: _asInt(relayCommands['RelayCommand2']),
      token: json['Token']?.toString() ?? '',
      deviceCount: _asInt(json['DeviceCount']),
      rawJson: json,
    );
  }

  final int result;
  final String message;
  final int isSendMessage;
  final String sendMessageTo;
  final String messageContent;
  final int userCommand1;
  final int userCommand2;
  final int relayCommand1;
  final int relayCommand2;
  final String token;
  final int deviceCount;
  final Map<String, dynamic> rawJson;
}

int _asInt(dynamic value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? 0;

Map<String, dynamic> _asMap(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

List<Map<String, dynamic>> _asMapList(dynamic value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
    : <Map<String, dynamic>>[];
