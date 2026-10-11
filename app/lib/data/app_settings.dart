import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small on-device preferences (appearance).
class AppSettings {
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static const _key = 'theme_mode';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
