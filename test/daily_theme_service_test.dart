import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/services/daily_theme_service.dart';
import 'package:undercoverleague/services/settings_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the daily URL sits on the socket origin', () {
    // Tests run natively without a define, so the default wss host applies.
    expect(DailyThemeService.dailyUrl.toString(), 'https://undercover.jarneclaesen.be/daily');
  });

  test('fetch parses a theme and swallows failures', () async {
    final ok = MockClient((request) async {
      expect(request.url.path, '/daily');
      return http.Response(
        jsonEncode({
          'id': 'boots',
          'title': 'Boots only',
          'description': 'Every pair of boots ever sold.',
          'filter': {
            'packs': ['items'],
            'itemTiers': ['boots'],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final theme = await DailyThemeService.fetch(client: ok);
    expect(theme!.title, 'Boots only');
    expect(theme.filter.packs, {'items'});
    expect(theme.filter.itemTiers, {'boots'});

    final empty = MockClient((_) async => http.Response(jsonEncode({'id': '', 'filter': {}}), 200));
    expect(await DailyThemeService.fetch(client: empty), isNull);

    final down = MockClient((_) async => http.Response('nope', 503));
    expect(await DailyThemeService.fetch(client: down), isNull);

    final broken = MockClient((_) async => throw Exception('offline'));
    expect(await DailyThemeService.fetch(client: broken), isNull);
  });

  test('SettingsPrefs loads what an older build saved', () async {
    SharedPreferences.setMockInitialValues({
      'hostSettings': jsonEncode({
        'useChampions': false,
        'useItems': true,
        'champSeasons': [0, 0],
        'itemSeasons': [0, 12],
        'itemTiers': ['boots', 'legendary'],
      }),
    });
    final saved = await SettingsPrefs.loadHostDefaults();
    expect(saved!.packs, {WordPack.items});
    expect(saved.itemSeasons, (0, 12));
    expect(saved.itemTiers, {'boots', 'legendary'});
    expect(saved.undercovers, 1);
    expect(saved.randomOrder, isFalse);

    const next = GameSettings(packs: {WordPack.runes, WordPack.monsters}, mrWhites: 1, decoyWord: true);
    await SettingsPrefs.saveHostDefaults(next);
    expect(await SettingsPrefs.loadHostDefaults(), next);
  });
}
