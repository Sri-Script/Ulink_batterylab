import 'package:shared_preferences/shared_preferences.dart';

/// Stores the one non-sensitive value remembered for U-Link sign-in.
///
/// Passwords are intentionally not accepted or stored by this API.
abstract class UlinkLoginPreferences {
  Future<String?> readEmail();
  Future<void> saveEmail(String email);
  Future<void> clearEmail();
}

class SharedPreferencesUlinkLoginPreferences implements UlinkLoginPreferences {
  static const emailKey = 'ulink_saved_email';

  @override
  Future<String?> readEmail() async {
    final preferences = await SharedPreferences.getInstance();
    return _normalize(preferences.getString(emailKey));
  }

  @override
  Future<void> saveEmail(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final normalized = _normalize(email);
    if (normalized == null) {
      await preferences.remove(emailKey);
    } else {
      await preferences.setString(emailKey, normalized);
    }
  }

  @override
  Future<void> clearEmail() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(emailKey);
  }

  static String? _normalize(String? email) {
    final normalized = email?.trim().toLowerCase() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
