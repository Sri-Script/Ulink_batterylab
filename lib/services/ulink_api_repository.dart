import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/ulink_api_models.dart';
import 'api_session_store.dart';

const ulinkApiBaseUrl = String.fromEnvironment(
  'ULINK_API_BASE_URL',
  defaultValue: 'https://ulinkappapi.ultratech.ind.in',
);

class UlinkApiException implements Exception {
  const UlinkApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

enum ApiLogoutResult { serverConfirmed, localOnly, noSession }

class ApiLoginResult {
  const ApiLoginResult({
    required this.session,
    required this.companies,
    required this.ulinks,
    required this.ulinksInStock,
  });
  final ApiSession session;
  final List<ApiCompany> companies;
  final List<ApiUlink> ulinks;
  final List<ApiUlink> ulinksInStock;
}

/// API client intentionally exposes only the documented read paths.
class UlinkApiRepository {
  UlinkApiRepository({
    http.Client? client,
    ApiSessionStore? sessionStore,
    String baseUrl = ulinkApiBaseUrl,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _store = sessionStore ?? SecureApiSessionStore(),
       _baseUri = Uri.parse(baseUrl),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final ApiSessionStore _store;
  final Uri _baseUri;
  final DateTime Function() _now;
  Future<ApiSession>? _refreshing;
  ApiSession? _session;

  Future<ApiSession?> restoreSession() async =>
      _session ??= await _store.read();

  /// Resolves (and, when necessary, refreshes) the current authenticated
  /// session without exposing tokens to workflow UI code.
  Future<ApiSession> requireActiveSession() => _validSession();

  /// A safe authenticated read used before an irreversible U-Link firmware
  /// action. A successful response proves both session validity and API reachability.
  Future<void> verifyUlinkApiReachability({
    required String userId,
    required String companyId,
  }) async {
    try {
      // A valid but empty list still proves that the selected company's
      // authenticated GetUlinks endpoint is reachable.
      await getCompanyUlinks(userId: userId, companyId: companyId);
    } on UlinkApiException {
      rethrow;
    } catch (_) {
      throw const UlinkApiException(
        'The API preflight returned an unexpected response.',
      );
    }
  }

  Future<ApiLoginResult> login({
    required String username,
    required String password,
  }) async {
    final json = await _postJson('/api/v1/auth/Login', <String, String>{
      'UserName': username,
      'Password': password,
    });
    _requireSuccess(json);
    final session = ApiSession.fromLoginJson(
      json,
    ).withAuthenticationId(_newUuid());
    await _store.save(session);
    _session = session;
    final payload = _payload(json);
    return ApiLoginResult(
      session: session,
      companies: _list(payload, 'Companies', ApiCompany.fromJson),
      ulinks: _list(payload, 'Ulinks', ApiUlink.fromJson),
      // The documented SI Login field is plural: UlinksInStock.
      ulinksInStock: _list(payload, 'UlinksInStock', ApiUlink.fromJson),
    );
  }

  Future<List<ApiUlink>> getCompanyUlinks({
    required String userId,
    required String companyId,
  }) => _readList(
    '/api/v1/ulinks/GetUlinks',
    <String, String>{'UserId': userId, 'CompanyID': companyId},
    'Ulinks',
    ApiUlink.fromJson,
  );

  Future<List<ApiDevice>> getDevices({
    required String userId,
    required String companyId,
    required String ulinkId,
  }) => _readList(
    '/api/v1/devices/GetDevices',
    <String, String>{
      'UserId': userId,
      'CompanyID': companyId,
      'UlinkID': ulinkId,
    },
    'Devices',
    ApiDevice.fromJson,
  );

  Future<ApiLogoutResult> logout() async {
    final session = await restoreSession();
    if (session == null) return ApiLogoutResult.noSession;
    var confirmed = false;
    try {
      final response = await _client.post(
        _uri('/api/v1/auth/Logout'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      confirmed = response.statusCode == 200;
    } catch (_) {
      confirmed = false;
    } finally {
      await clearSession();
    }
    return confirmed
        ? ApiLogoutResult.serverConfirmed
        : ApiLogoutResult.localOnly;
  }

  Future<void> clearSession() async {
    _session = null;
    await _store.clear();
  }

  Future<List<ApiUlink>> updateUlinkProvisioning({
    required String companyId,
    required String ulinkId,
    required bool flashed,
    UlinkAppType? appType,
    String? idempotencyKey,
    bool requireFreshAuthentication = false,
  }) async {
    if (flashed && appType == null) {
      throw ArgumentError.value(
        appType,
        'appType',
        'A flashed U-Link provisioning request requires Demo or Live.',
      );
    }
    if (!flashed && appType != null) {
      throw ArgumentError.value(
        appType,
        'appType',
        'An unflash request must use an empty AppType.',
      );
    }
    final session = await _validSession();
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.ulink,
      userId: session.userId,
      companyId: companyId,
      ulinkId: ulinkId,
      isFlashed: flashed ? 1 : 0,
      appType: appType,
    );
    // Keep the exact operation persisted until the required post-write list
    // refresh succeeds. If that response is lost, the same PUT can still be
    // retried idempotently rather than risking a second operation.
    await _sendProvisioning(
      session,
      request,
      idempotencyKey: idempotencyKey,
      clearPendingOnSuccess: false,
      requireFreshAuthentication: requireFreshAuthentication,
    );
    final ulinks = await getCompanyUlinks(
      userId: session.userId,
      companyId: companyId,
    );
    await _store.clearPending();
    return ulinks;
  }

  Future<void> updateDeviceProvisioning({
    required String ulinkId,
    required String deviceId,
    required bool flashed,
    String? idempotencyKey,
  }) async {
    final session = await _validSession();
    if (session.userRole != 'CA') {
      throw const UlinkApiException(
        'Only Company Admin users can provision devices.',
      );
    }
    final request = ApiProvisioningRequest(
      kind: ApiProvisioningKind.device,
      userId: session.userId,
      ulinkId: ulinkId,
      deviceId: deviceId,
      isFlashed: flashed ? 1 : 0,
    );
    await _sendProvisioning(session, request, idempotencyKey: idempotencyKey);
  }

  /// Retries only the exact operation previously persisted by this session.
  /// The caller must make this an explicit recovery choice after an unknown
  /// network result; no automatic reset or retry is performed.
  Future<bool> retryPendingProvisioning() async {
    final pending = await _store.readPending();
    final session = await restoreSession();
    if (pending == null ||
        session == null ||
        pending.userId != session.userId ||
        pending.userRole != session.userRole) {
      return false;
    }
    // A password re-login creates a different local authentication identity.
    // Never replay a pending destructive request in that new login.
    if (pending.requiresFreshAuthentication &&
        (pending.authenticationId == null ||
            pending.authenticationId != session.authenticationId)) {
      return false;
    }
    final validSession = await _validSession();
    final response = await _client.put(
      _uri(pending.endpoint),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer ${validSession.accessToken}',
        'Idempotency-Key': pending.idempotencyKey,
      },
      body: jsonEncode(pending.body),
    );
    final json = _decode(response);
    if (response.statusCode != 200) _throwServer(json, response.statusCode);
    _requireSuccess(json, statusCode: response.statusCode);
    await _store.clearPending();
    return true;
  }

  /// Use only after a definitive server rejection. Unknown results remain
  /// persisted so the identical request can be retried idempotently.
  Future<void> discardPendingProvisioning() => _store.clearPending();

  Future<void> _sendProvisioning(
    ApiSession session,
    ApiProvisioningRequest request, {
    String? idempotencyKey,
    bool clearPendingOnSuccess = true,
    bool requireFreshAuthentication = false,
  }) async {
    final key = idempotencyKey ?? _newUuid();
    final body = request.toJson();
    final endpoint = request.kind == ApiProvisioningKind.ulink
        ? '/api/v1/ulinks/UpdateUlinkProvisioning'
        : '/api/v1/devices/UpdateDeviceProvisioning';
    final pending = PendingApiOperation(
      endpoint: endpoint,
      body: body,
      idempotencyKey: key,
      userId: session.userId,
      userRole: session.userRole,
      createdAtUtc: _now().toUtc(),
      kind: request.kind,
      authenticationId: session.authenticationId,
      requiresFreshAuthentication: requireFreshAuthentication,
    );
    await _store.savePending(pending);
    try {
      final response = await _client.put(
        _uri(endpoint),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'Idempotency-Key': key,
        },
        body: jsonEncode(body),
      );
      final json = _decode(response);
      if (response.statusCode != 200) _throwServer(json, response.statusCode);
      _requireSuccess(json, statusCode: response.statusCode);
      if (clearPendingOnSuccess) {
        await _store.clearPending();
      }
    } on UlinkApiException {
      // Keep the exact pending body/key so the caller can explicitly retry an
      // unknown result with the same operation identity and session.
      rethrow;
    } on Exception {
      // Keep the exact pending body/key so a lost response can be retried with
      // the same idempotency key instead of creating a second assignment.
      throw const UlinkApiException(
        'The server response was lost. Retrying the same assignment.',
      );
    }
  }

  Future<List<T>> _readList<T>(
    String path,
    Map<String, String> query,
    String listKey,
    T Function(JsonMap) convert,
  ) async {
    int? statusCode;
    try {
      final response = await _authenticatedGet(path, query);
      statusCode = response.statusCode;
      final json = _decode(response);
      if (response.statusCode != 200) {
        _throwServer(json, response.statusCode);
      }
      _requireSuccess(json, statusCode: response.statusCode);
      final list = _responseList(json, listKey);
      return list
          .map((item) => convert(Map<String, dynamic>.from(item)))
          .toList();
    } on UlinkApiException {
      rethrow;
    } on http.ClientException {
      throw UlinkApiException(
        'The API network request failed.',
        statusCode: statusCode,
      );
    } on Object {
      throw UlinkApiException(
        'The API returned an invalid $listKey response.',
        statusCode: statusCode,
      );
    }
  }

  Future<http.Response> _authenticatedGet(
    String path,
    Map<String, String> query,
  ) async {
    var session = await _validSession();
    var response = await _client.get(
      _uri(path, query),
      headers: _headers(session),
    );
    if (response.statusCode == 401) {
      session = await _refresh();
      response = await _client.get(
        _uri(path, query),
        headers: _headers(session),
      );
    }
    return response;
  }

  Future<ApiSession> _validSession() async {
    final session = await restoreSession();
    if (session == null) {
      throw const UlinkApiException('Your session has ended. Sign in again.');
    }
    if (session.accessTokenExpiresAtUtc.isBefore(
      _now().toUtc().add(const Duration(seconds: 30)),
    )) {
      return _refresh();
    }
    return session;
  }

  Future<ApiSession> _refresh() {
    final current = _refreshing;
    if (current != null) return current;
    final operation = _doRefresh();
    _refreshing = operation;
    return operation.whenComplete(() => _refreshing = null);
  }

  Future<ApiSession> _doRefresh() async {
    final old = await restoreSession();
    if (old == null || old.refreshTokenExpiresAtUtc.isBefore(_now().toUtc())) {
      await clearSession();
      throw const UlinkApiException('Your session has ended. Sign in again.');
    }
    try {
      final response = await _client.post(
        _uri('/api/v1/auth/Refresh'),
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(<String, String>{'RefreshToken': old.refreshToken}),
      );
      if (response.statusCode != 200) {
        throw UlinkApiException(
          'Your session has ended. Sign in again.',
          statusCode: response.statusCode,
        );
      }
      final json = _decode(response);
      _requireSuccess(json, statusCode: response.statusCode);
      final tokens = json['Tokens'];
      if (tokens is! Map) {
        throw const FormatException('Refresh response did not contain tokens.');
      }
      final refreshed = old.withTokens(Map<String, dynamic>.from(tokens));
      await _store.save(refreshed); // write the replacement tokens together.
      _session = refreshed;
      return refreshed;
    } catch (_) {
      // A refresh can rotate the token server-side even if its response is lost.
      // Never retry this old token: force a password login instead.
      await clearSession();
      throw const UlinkApiException('Your session has ended. Sign in again.');
    }
  }

  Future<JsonMap> _postJson(String path, JsonMap body) async {
    http.Response response;
    try {
      response = await _client.post(
        _uri(path),
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );
    } on Exception {
      throw const UlinkApiException(
        'The service is unavailable. Please try again.',
      );
    }
    final json = _decode(response);
    if (response.statusCode != 200) _throwServer(json, response.statusCode);
    return json;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      _baseUri.replace(path: path, queryParameters: query);
  Map<String, String> _headers(ApiSession session) => <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer ${session.accessToken}',
  };
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Public client name used by integrations that do not need repository
/// terminology. It deliberately exposes the same read-only API surface.
class UlinkApiClient extends UlinkApiRepository {
  UlinkApiClient({super.client, super.sessionStore, super.baseUrl, super.now});
}

JsonMap _decode(http.Response response) {
  try {
    final value = jsonDecode(response.body);
    if (value is Map) return Map<String, dynamic>.from(value);
  } catch (_) {}
  throw UlinkApiException(
    'The service returned an invalid response.',
    statusCode: response.statusCode,
  );
}

void _requireSuccess(JsonMap json, {int? statusCode}) {
  if (json['Result'] == 1 || json['Result'] == true) return;
  _throwServer(json, statusCode);
}

Never _throwServer(JsonMap json, int? statusCode) {
  final message = json['Message'];
  final safe = message is String && message.trim().isNotEmpty
      ? message.trim()
      : (statusCode == 429
            ? 'Too many attempts. Please wait and try again.'
            : 'The request could not be completed.');
  throw UlinkApiException(safe, statusCode: statusCode);
}

List<T> _list<T>(JsonMap json, String key, T Function(JsonMap) convert) {
  final value = json[key];
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((item) => convert(Map<String, dynamic>.from(item)))
      .toList();
}

JsonMap _payload(JsonMap json) {
  final data = json['Data'];
  return data is Map ? Map<String, dynamic>.from(data) : json;
}

/// GetUlinks and GetDevices return their documented lists at the response
/// root. Some deployed API versions wrap the same named list in Data.
List<JsonMap> _responseList(JsonMap json, String listKey) {
  final rootValue = json[listKey];
  final data = json['Data'];
  final nestedValue = data is Map ? data[listKey] : null;
  final value = rootValue is List ? rootValue : nestedValue;
  if (value is! List) {
    throw const FormatException('The API response did not contain a list.');
  }
  return value.map((item) {
    if (item is! Map) {
      throw const FormatException('The API list contained an invalid item.');
    }
    return Map<String, dynamic>.from(item);
  }).toList();
}
