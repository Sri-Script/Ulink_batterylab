import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import '../models/ulink_api_models.dart';

abstract class ApiSessionStore {
  Future<ApiSession?> read();
  Future<void> save(ApiSession session);
  Future<void> clear();
  Future<void> savePending(PendingApiOperation operation);
  Future<PendingApiOperation?> readPending();
  Future<void> clearPending();
}

/// Stores only API session values in platform-secured storage.
class SecureApiSessionStore implements ApiSessionStore {
  SecureApiSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _userId = 'ulink_api_user_id';
  static const _role = 'ulink_api_user_role';
  static const _userName = 'ulink_api_user_name';
  static const _access = 'ulink_api_access_token';
  static const _accessExpiry = 'ulink_api_access_expiry_utc';
  static const _refresh = 'ulink_api_refresh_token';
  static const _refreshExpiry = 'ulink_api_refresh_expiry_utc';
  static const _pending = 'ulink_api_pending_operation';
  final FlutterSecureStorage _storage;

  @override
  Future<ApiSession?> read() async {
    final values = await _storage.readAll();
    try {
      return ApiSession.fromTokens(
        userId: values[_userId]!,
        userRole: values[_role]!,
        userName: values[_userName]!,
        tokens: <String, dynamic>{
          'AccessToken': values[_access],
          'AccessTokenExpiresAtUtc': values[_accessExpiry],
          'RefreshToken': values[_refresh],
          'RefreshTokenExpiresAtUtc': values[_refreshExpiry],
        },
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(ApiSession session) async {
    final values = <String, String>{
      _userId: session.userId,
      _role: session.userRole,
      _userName: session.userName,
      _access: session.accessToken,
      _accessExpiry: session.accessTokenExpiresAtUtc.toIso8601String(),
      _refresh: session.refreshToken,
      _refreshExpiry: session.refreshTokenExpiresAtUtc.toIso8601String(),
    };
    for (final entry in values.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }

  @override
  Future<void> clear() async {
    for (final key in const <String>[
      _userId,
      _role,
      _userName,
      _access,
      _accessExpiry,
      _refresh,
      _refreshExpiry,
    ]) {
      await _storage.delete(key: key);
    }
    await clearPending();
  }

  @override
  Future<void> savePending(PendingApiOperation operation) => _storage.write(
    key: _pending,
    value: jsonEncode(<String, dynamic>{
      'endpoint': operation.endpoint,
      'body': operation.body,
      'idempotencyKey': operation.idempotencyKey,
      'userId': operation.userId,
      'userRole': operation.userRole,
      'createdAtUtc': operation.createdAtUtc.toIso8601String(),
      'kind': operation.kind.name,
    }),
  );

  @override
  Future<PendingApiOperation?> readPending() async {
    final raw = await _storage.read(key: _pending);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PendingApiOperation(
        endpoint: json['endpoint'] as String,
        body: Map<String, dynamic>.from(json['body'] as Map),
        idempotencyKey: json['idempotencyKey'] as String,
        userId: json['userId'] as String,
        userRole: json['userRole'] as String,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
        kind: ApiProvisioningKind.values.byName(json['kind'] as String),
      );
    } catch (_) {
      await clearPending();
      return null;
    }
  }

  @override
  Future<void> clearPending() => _storage.delete(key: _pending);
}

class MemoryApiSessionStore implements ApiSessionStore {
  ApiSession? value;
  PendingApiOperation? pending;
  @override
  Future<void> clear() async {
    value = null;
    pending = null;
  }
  @override
  Future<ApiSession?> read() async => value;
  @override
  Future<void> save(ApiSession session) async => value = session;
  @override
  Future<void> savePending(PendingApiOperation operation) async => pending = operation;
  @override
  Future<PendingApiOperation?> readPending() async => pending;
  @override
  Future<void> clearPending() async => pending = null;
}
