/// Models for the documented UlinkAppAPI v1 read-only hierarchy.
library;

typedef JsonMap = Map<String, dynamic>;

class ApiSession {
  const ApiSession({
    required this.userId,
    required this.userRole,
    required this.userName,
    required this.accessToken,
    required this.accessTokenExpiresAtUtc,
    required this.refreshToken,
    required this.refreshTokenExpiresAtUtc,
  });

  factory ApiSession.fromLoginJson(JsonMap json) {
    final tokens = _map(json['Tokens']);
    final user = _map(json['User']);
    final role = _string(json, 'UserRole') ?? _string(user, 'UserRole');
    final userId = _id(json, 'UserId') ?? _id(user, 'UserId');
    final userName = _string(json, 'UserName') ?? _string(user, 'UserName');
    if (tokens == null || role == null || userId == null || userName == null) {
      throw const FormatException(
        'The login response did not contain a session.',
      );
    }
    return ApiSession.fromTokens(
      userId: userId,
      userRole: role,
      userName: userName,
      tokens: tokens,
    );
  }

  factory ApiSession.fromTokens({
    required String userId,
    required String userRole,
    required String userName,
    required JsonMap tokens,
  }) {
    final access = _string(tokens, 'AccessToken');
    final refresh = _string(tokens, 'RefreshToken');
    final accessExpiry = _date(tokens, 'AccessTokenExpiresAtUtc');
    final refreshExpiry = _date(tokens, 'RefreshTokenExpiresAtUtc');
    if (access == null ||
        refresh == null ||
        accessExpiry == null ||
        refreshExpiry == null) {
      throw const FormatException(
        'The login response contained invalid tokens.',
      );
    }
    final normalizedRole = userRole.trim().toUpperCase();
    if (normalizedRole != 'SI' && normalizedRole != 'CA') {
      throw const FormatException(
        'The login response contained an unsupported role.',
      );
    }
    return ApiSession(
      userId: userId,
      userRole: normalizedRole,
      userName: userName,
      accessToken: access,
      accessTokenExpiresAtUtc: accessExpiry,
      refreshToken: refresh,
      refreshTokenExpiresAtUtc: refreshExpiry,
    );
  }

  final String userId;
  final String userRole;
  final String userName;
  final String accessToken;
  final DateTime accessTokenExpiresAtUtc;
  final String refreshToken;
  final DateTime refreshTokenExpiresAtUtc;

  ApiSession withTokens(JsonMap tokens) => ApiSession.fromTokens(
    userId: userId,
    userRole: userRole,
    userName: userName,
    tokens: tokens,
  );
}

class ApiCompany {
  const ApiCompany({
    required this.cid,
    required this.cName,
    this.cia,
    this.uCount,
  });
  factory ApiCompany.fromJson(JsonMap json) => ApiCompany(
    cid: _requiredId(json, 'CID'),
    cName: _string(json, 'CName') ?? _requiredId(json, 'CID'),
    cia: _boolish(json, 'CIA'),
    uCount: _int(json, 'UCount'),
  );
  final String cid;
  final String cName;
  final bool? cia;
  final int? uCount;
}

class ApiUlink {
  const ApiUlink({
    required this.uid,
    required this.uCode,
    this.udimI,
    this.udimC,
    this.uif,
    this.uia,
    this.umd,
    this.dCount,
  });
  factory ApiUlink.fromJson(JsonMap json) => ApiUlink(
    uid: _requiredId(json, 'UID'),
    uCode: _string(json, 'UCode') ?? _requiredId(json, 'UID'),
    udimI: _string(json, 'UDimI'),
    udimC: _string(json, 'UDimC'),
    uif: _boolish(json, 'UIF'),
    uia: _boolish(json, 'UIA'),
    umd: _int(json, 'UMD'),
    dCount: _int(json, 'DCount'),
  );
  final String uid;
  final String uCode;
  final String? udimI;
  final String? udimC;
  final bool? uif;
  final bool? uia;
  final int? umd;
  final int? dCount;
}

class ApiDevice {
  const ApiDevice({
    required this.did,
    required this.dCode,
    this.dif,
    this.dia,
    this.deviceName,
    this.deviceType,
    this.displayFields = const <String, String>{},
  });
  factory ApiDevice.fromJson(JsonMap json) {
    final display = <String, String>{};
    for (final entry in json.entries) {
      if (entry.value != null && entry.value is! Map && entry.value is! List) {
        display[entry.key] = '${entry.value}';
      }
    }
    return ApiDevice(
      did: _requiredId(json, 'DID'),
      dCode: _string(json, 'DCode') ?? _requiredId(json, 'DID'),
      dif: _boolish(json, 'DIF'),
      dia: _boolish(json, 'DIA'),
      deviceName: _string(json, 'DName'),
      deviceType: _string(json, 'DTName') ?? _string(json, 'DType'),
      displayFields: display,
    );
  }
  final String did;
  final String dCode;
  final bool? dif;
  final bool? dia;
  final String? deviceName;
  final String? deviceType;
  final Map<String, String> displayFields;
}

class ApiDevIntMode {
  const ApiDevIntMode({required this.id, required this.name});
  factory ApiDevIntMode.fromJson(JsonMap json) => ApiDevIntMode(
    id: _requiredId(json, 'DIMID'),
    name: _string(json, 'DIMName') ?? _requiredId(json, 'DIMID'),
  );
  final String id;
  final String name;
}

class ApiDeviceType {
  const ApiDeviceType({required this.id, required this.name, this.code});
  factory ApiDeviceType.fromJson(JsonMap json) => ApiDeviceType(
    id: _requiredId(json, 'DTID'),
    name: _string(json, 'DTName') ?? _requiredId(json, 'DTID'),
    code: _string(json, 'DTCode'),
  );
  final String id;
  final String name;
  final String? code;
}

class ApiParamTemplate {
  const ApiParamTemplate({required this.id, required this.name, this.code});
  factory ApiParamTemplate.fromJson(JsonMap json) => ApiParamTemplate(
    id: _requiredId(json, 'PTID'),
    name: _string(json, 'PTName') ?? _requiredId(json, 'PTID'),
    code: _string(json, 'PTCode'),
  );
  final String id;
  final String name;
  final String? code;
}

JsonMap? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
String? _string(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

String? _id(JsonMap json, String key) => _string(json, key);
String _requiredId(JsonMap json, String key) =>
    _id(json, key) ?? (throw FormatException('Missing $key.'));
int? _int(JsonMap json, String key) => switch (json[key]) {
  int value => value,
  num value => value.toInt(),
  String value => int.tryParse(value),
  _ => null,
};
bool? _boolish(JsonMap json, String key) => switch (json[key]) {
  bool value => value,
  num value => value != 0,
  String value when value == '1' || value.toLowerCase() == 'true' => true,
  String value when value == '0' || value.toLowerCase() == 'false' => false,
  _ => null,
};
DateTime? _date(JsonMap json, String key) => _string(json, key) == null
    ? null
    : DateTime.tryParse(_string(json, key)!)?.toUtc();
