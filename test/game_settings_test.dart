import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/widgets/lobby_filters.dart';

void main() {
  test('GameSettings round-trips the wire shape', () {
    const s = GameSettings(
      useChampions: true,
      useItems: false,
      champSeasons: (15, 16),
      itemSeasons: (3, 10),
      itemTiers: {ItemTier.legendary, ItemTier.boots},
    );
    final json = s.toJson();
    expect(json, {
      'useChampions': true,
      'useItems': false,
      'champSeasons': [15, 16],
      'itemSeasons': [3, 10],
      // Tiers are sent in shop order regardless of set order.
      'itemTiers': ['boots', 'legendary'],
    });
    expect(GameSettings.fromJson(json), s);
  });

  test('missing tiers mean all, an empty list means none', () {
    expect(GameSettings.fromJson({}).itemTiers, ItemTier.all.toSet());
    expect(GameSettings.fromJson({'itemTiers': <String>[]}).itemTiers, isEmpty);
  });

  test('clampedTo keeps saved defaults inside the catalog', () {
    const range = SeasonRange(champions: (1, 16), items: (3, 16));
    const saved = GameSettings(champSeasons: (0, 40), itemSeasons: (1, 2));
    final c = saved.clampedTo(range);
    expect(c.champSeasons, (1, 16));
    expect(c.itemSeasons, (3, 3));
    // Unknown bounds leave the settings alone.
    expect(saved.clampedTo(const SeasonRange(champions: (0, 0), items: (0, 0))), saved);
  });

  test('Lobby tolerates views with and without pool info', () {
    final old = Lobby.fromJson({'id': 'x', 'host': 'A'});
    expect(old.settings, const GameSettings());
    expect(old.poolSize, isNull);
    expect(old.seasonRange, isNull);

    final lobby = Lobby.fromJson({
      'id': 'x',
      'host': 'A',
      'settings': {
        'useChampions': true,
        'useItems': true,
        'champSeasons': [1, 16],
        'itemSeasons': [3, 16],
        'itemTiers': ['starter'],
      },
      'poolSize': {'champions': 173, 'items': 42},
      'seasonRange': {
        'champions': [1, 16],
        'items': [3, 16],
      },
      'myIcon': 'https://ddragon.leagueoflegends.com/cdn/img/champion/loading/Ahri_0.jpg',
    });
    expect(lobby.settings.itemTiers, {'starter'});
    expect(lobby.poolSize!.total, 215);
    expect(lobby.seasonRange!.items, (3, 16));
    expect(lobby.myIcon, startsWith('https://'));
  });

  test('summary line reads naturally', () {
    expect(
      LobbyFiltersSummary.describe(const GameSettings(champSeasons: (1, 16), itemSeasons: (16, 16))),
      'Champions S1–S16 · Items S16',
    );
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(useChampions: false, itemSeasons: (3, 10), itemTiers: {ItemTier.legendary}),
      ),
      'Items S3–S10 (1 of 5 tiers)',
    );
  });
}
