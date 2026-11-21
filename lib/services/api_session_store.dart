import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ulink_api_models.dart';

abstract class ApiSessionStore {
  Future<ApiSession?> read();
  Future<void> save(ApiSession session);
  Future<void> clear();
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
  Future<void> save(ApiSession session) => _storage.writeAll(<String, String>{
    _userId: session.userId,
    _role: session.userRole,
    _userName: session.userName,
    _access: session.accessToken,
    _accessExpiry: session.accessTokenExpiresAtUtc.toIso8601String(),
    _refresh: session.refreshToken,
    _refreshExpiry: session.refreshTokenExpiresAtUtc.toIso8601String(),
  });

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
  }
}

class MemoryApiSessionStore implements ApiSessionStore {
  ApiSession? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<ApiSession?> read() async => value;
  @override
  Future<void> save(ApiSession session) async => value = session;
}
