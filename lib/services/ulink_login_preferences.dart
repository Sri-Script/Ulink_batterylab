import 'package:shared_preferences/shared_preferences.dart';

/// Stores the one non-sensitive value remembered for U-Link sign-in.
///
/// Passwords are intentionally not accepted or stored by this API.
abstract class UlinkLoginPreferences {
  Future<String?> readUsername();
  Future<void> saveUsername(String username);
  Future<void> clearUsername();
}

class SharedPreferencesUlinkLoginPreferences implements UlinkLoginPreferences {
  static const usernameKey = 'ulink_saved_username';

  @override
  Future<String?> readUsername() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalize(preferences.getString(usernameKey));
  }

  @override
  Future<void> saveUsername(String username) async {
    final preferences = await SharedPreferences.getInstance();
    final normalized = _normalize(username);
    if (normalized == null) {
      await preferences.remove(usernameKey);
    } else {
      await preferences.setString(usernameKey, normalized);
    }
  }

  @override
  Future<void> clearUsername() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(usernameKey);
  }

  static String? _normalize(String? username) {
    final normalized = username?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
