import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/services/game_connection.dart';

/// Fetches today's theme from `GET /daily` on the game server, for screens
/// that want it before a lobby exists (the lobby view carries it too).
class DailyThemeService {
  static const _timeout = Duration(seconds: 8);

  /// `/daily` on the origin the socket connects to, so a `UNDERCOVER_WS_URL`
  /// override, a web build served by the server and a native build all
  /// reach the same server.
  static Uri get dailyUrl {
    final ws = Uri.parse(GameConnection.wsUrl);
    // Built from parts rather than `replace`, which keeps the query (and a
    // web build's socket URL carries the page's `?lobby=` with it).
    return Uri(
      scheme: ws.scheme == 'wss' ? 'https' : 'http',
      userInfo: ws.userInfo,
      host: ws.host,
      port: ws.hasPort ? ws.port : null,
      path: '/daily',
    );
  }

  /// Today's theme, or null when the server is unreachable, answers with an
  /// error or has no catalog yet. Never throws.
  static Future<DailyTheme?> fetch({http.Client? client}) async {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.get(dailyUrl).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) return null;
      final theme = DailyTheme.fromJson(json.cast<String, dynamic>());
      return theme.isEmpty ? null : theme;
    } catch (e) {
      debugPrint('DailyThemeService: $e');
      return null;
    } finally {
      if (own) c.close();
    }
  }
}
