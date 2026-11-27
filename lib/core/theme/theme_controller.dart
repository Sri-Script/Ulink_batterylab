import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._(this._preferences, this._choice);

  static const preferenceKey = 'ulink_dashboard_theme_mode';
  final SharedPreferences _preferences;
  ThemeMode? _choice;

  ThemeMode? get choice => _choice;

  static Future<ThemeController> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(preferenceKey);
    final choice = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
    return ThemeController._(preferences, choice);
  }

  Brightness effectiveBrightness(Brightness systemBrightness) =>
      _choice == ThemeMode.light
          ? Brightness.light
          : _choice == ThemeMode.dark
          ? Brightness.dark
          : systemBrightness;

  Future<void> toggle(Brightness systemBrightness) async {
    final next = effectiveBrightness(systemBrightness) == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    _choice = next;
    notifyListeners();
    await _preferences.setString(preferenceKey, next.name);
  }
}
