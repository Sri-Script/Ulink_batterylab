import 'dart:async';
import 'dart:convert';

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

  Future<ApiLoginResult> login({
    required String username,
    required String password,
  }) async {
    final json = await _postJson('/api/v1/auth/Login', <String, String>{
      'UserName': username,
      'Password': password,
    });
    _requireSuccess(json);
    final session = ApiSession.fromLoginJson(json);
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
  }) => _readList('/api/v1/ulinks/GetUlinks', <String, String>{
    'UserId': userId,
    'CompanyID': companyId,
  }, ApiUlink.fromJson);

  Future<List<ApiDevice>> getDevices({
    required String userId,
    required String companyId,
    required String ulinkId,
  }) => _readList('/api/v1/devices/GetDevices', <String, String>{
    'UserId': userId,
    'CompanyID': companyId,
    'UlinkID': ulinkId,
  }, ApiDevice.fromJson);

  Future<void> logout() async {
    final session = await restoreSession();
    try {
      if (session != null) {
        await _client.post(
          _uri('/api/v1/auth/Logout'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
        );
      }
    } catch (_) {
      // Local sign-out is still authoritative for this device.
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    _session = null;
    await _store.clear();
  }

  Future<List<T>> _readList<T>(
    String path,
    Map<String, String> query,
    T Function(JsonMap) convert,
  ) async {
    final response = await _authenticatedGet(path, query);
    final json = _decode(response);
    _requireSuccess(json, statusCode: response.statusCode);
    final data = json['Data'];
    final list = data is List
        ? data
        : (json['Result'] is List ? json['Result'] : const <dynamic>[]);
    return list
        .whereType<Map>()
        .map((item) => convert(Map<String, dynamic>.from(item)))
        .toList();
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
    if (session == null)
      throw const UlinkApiException('Your session has ended. Sign in again.');
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
      if (response.statusCode != 200)
        throw const UlinkApiException(
          'Your session has ended. Sign in again.',
          statusCode: response.statusCode,
        );
      final json = _decode(response);
      _requireSuccess(json, statusCode: response.statusCode);
      final tokens = json['Tokens'];
      if (tokens is! Map)
        throw const FormatException('Refresh response did not contain tokens.');
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

/// Public client name used by integrations that do not need repository
/// terminology. It deliberately exposes the same read-only API surface.
class UlinkApiClient extends UlinkApiRepository {
  UlinkApiClient({
    super.client,
    super.sessionStore,
    super.baseUrl,
    super.now,
  });
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
  if (value is! List) return const <T>[];
  return value
      .whereType<Map>()
      .map((item) => convert(Map<String, dynamic>.from(item)))
      .toList();
}

JsonMap _payload(JsonMap json) {
  final data = json['Data'];
  return data is Map ? Map<String, dynamic>.from(data) : json;
}
