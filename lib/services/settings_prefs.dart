import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undercoverleague/models/game_settings.dart';

/// Remembers the host's last word-pool settings on this device so the next
/// lobby starts from them. Purely a convenience: the server never reads it.
class SettingsPrefs {
  static const _key = 'hostSettings';

  static Future<GameSettings?> loadHostDefaults() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      return GameSettings.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('SettingsPrefs: could not load defaults: $e');
      return null;
    }
  }

  static Future<void> saveHostDefaults(GameSettings settings) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('SettingsPrefs: could not save defaults: $e');
    }
  }
}
