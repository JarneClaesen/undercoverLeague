import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/widgets/lobby_filters.dart';
import 'package:undercoverleague/widgets/lobby_rules.dart';

void main() {
  test('GameSettings round-trips the full wire shape', () {
    const s = GameSettings(
      packs: {WordPack.items, WordPack.champions, WordPack.monsters},
      champSeasons: (15, 16),
      itemSeasons: (3, 10),
      itemTiers: {ItemTier.legendary, ItemTier.boots},
      champClasses: {'Tank', 'Mage'},
      champRegions: {'Shurima'},
      champLanes: {ChampionLane.support, ChampionLane.top},
      champRanges: {ChampionRange.ranged, ChampionRange.melee},
      champResources: {ChampionResource.other, ChampionResource.energy},
      champDamage: {ChampionDamage.mixed},
      champDifficulty: {ChampionDifficulty.hard, ChampionDifficulty.easy},
      undercovers: 2,
      mrWhites: 1,
      decoyWord: true,
      randomOrder: false,
      turnSeconds: 60,
      clueLog: true,
      rotateHost: true,
    );
    final json = s.toJson();
    expect(json, {
      // Packs and tiers are sent in the server's order regardless of set order.
      'packs': ['champions', 'items', 'monsters'],
      'champSeasons': [15, 16],
      'itemSeasons': [3, 10],
      'itemTiers': ['boots', 'legendary'],
      'champClasses': ['Mage', 'Tank'],
      'champRegions': ['Shurima'],
      'champLanes': ['top', 'support'],
      'champRanges': ['melee', 'ranged'],
      'champResources': ['energy', 'other'],
      'champDamage': ['mixed'],
      'champDifficulty': ['easy', 'hard'],
      'undercovers': 2,
      'mrWhites': 1,
      'decoyWord': true,
      'randomOrder': false,
      'turnSeconds': 60,
      'clueLog': true,
      'rotateHost': true,
    });
    expect(GameSettings.fromJson(json), s);
    expect(GameSettings.fromJson(json).hashCode, s.hashCode);
  });

  test('defaults match the server', () {
    const d = GameSettings();
    expect(d.packs, {'champions', 'items'});
    expect(d.undercovers, 1);
    expect(d.mrWhites, 0);
    expect(d.decoyWord, isFalse);
    expect(d.randomOrder, isFalse);
    expect(d.turnSeconds, 0);
    expect(d.clueLog, isFalse);
    expect(d.rotateHost, isFalse);
    expect(d.champClasses, isEmpty);
    expect(d.champRegions, isEmpty);
    expect(d.champLanes, isEmpty);
    expect(d.champRanges, isEmpty);
    expect(d.champResources, isEmpty);
    expect(d.champDamage, isEmpty);
    expect(d.champDifficulty, isEmpty);
    expect(d.activeChampionFilters, 0);
    expect(ChampionLane.all, ['top', 'jungle', 'mid', 'bot', 'support']);
    expect(ChampionLane.label('bot'), 'Bot');
    expect(ChampionLane.label('support'), 'Support');
    expect(ChampionRange.all, ['melee', 'ranged']);
    expect(ChampionResource.all, ['mana', 'energy', 'none', 'other']);
    expect(ChampionDamage.all, ['physical', 'magic', 'mixed']);
    expect(ChampionDifficulty.all, ['easy', 'medium', 'hard']);
    expect(ChampionResource.label('none'), 'Manaless');
    expect(ChampionResource.label('other'), 'Fury & other');
    // A row saved before the bucket filters existed loads with them open.
    final old = GameSettings.fromJson({'packs': ['champions'], 'champClasses': ['Mage']});
    expect(old.champClasses, {'Mage'});
    expect(old.champLanes, isEmpty);
    expect(old.champRanges, isEmpty);
    expect(old.champDifficulty, isEmpty);
    expect(WordPack.all, ['champions', 'items', 'spells', 'runes', 'abilities', 'skinlines', 'monsters']);
  });

  test('legacy prefs without packs or rules still load', () {
    final legacy = GameSettings.fromJson({
      'useChampions': true,
      'useItems': false,
      'champSeasons': [1, 5],
      'itemSeasons': [0, 0],
      'itemTiers': ['starter'],
    });
    expect(legacy.packs, {'champions'});
    expect(legacy.useChampions, isTrue);
    expect(legacy.useItems, isFalse);
    expect(legacy.champSeasons, (1, 5));
    expect(legacy.itemTiers, {'starter'});
    expect(legacy.undercovers, 1);
    expect(legacy.randomOrder, isFalse);
    expect(legacy.decoyWord, isFalse);

    // Booleans absent altogether mean both packs, like before packs existed.
    expect(GameSettings.fromJson({}).packs, {'champions', 'items'});
    // An explicit packs list wins over stale booleans.
    expect(GameSettings.fromJson({'packs': ['runes'], 'useChampions': true}).packs, {'runes'});
    // A zero undercover count from an old row normalizes to one.
    expect(GameSettings.fromJson({'undercovers': 0}).undercovers, 1);
  });

  test('missing tiers mean all, an empty list means none', () {
    expect(GameSettings.fromJson({}).itemTiers, ItemTier.all.toSet());
    expect(GameSettings.fromJson({'itemTiers': <String>[]}).itemTiers, isEmpty);
  });

  test('withFilterOf swaps the pool and keeps the rules', () {
    const rules = GameSettings(undercovers: 2, decoyWord: true, turnSeconds: 90, clueLog: true);
    const pool = GameSettings(packs: {WordPack.runes}, champClasses: {'Mage'}, undercovers: 5, turnSeconds: 0);
    final merged = rules.withFilterOf(pool);
    expect(merged.packs, {'runes'});
    expect(merged.champClasses, {'Mage'});
    expect(merged.undercovers, 2);
    expect(merged.turnSeconds, 90);
    expect(merged.clueLog, isTrue);
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

  test('unboundedWithin keeps "up to the newest season" open-ended', () {
    const range = SeasonRange(champions: (1, 16), items: (3, 16));
    const everything = GameSettings(champSeasons: (1, 16), itemSeasons: (3, 16));
    expect(everything.unboundedWithin(range), const GameSettings());
    // Next season the same saved value clamps to the new full range.
    const next = SeasonRange(champions: (1, 17), items: (3, 17));
    expect(everything.unboundedWithin(range).clampedTo(next).champSeasons, (1, 17));
    // Inner bounds stay put.
    const old = GameSettings(champSeasons: (2, 5), itemSeasons: (3, 10));
    expect(old.unboundedWithin(range).champSeasons, (2, 5));
    expect(old.unboundedWithin(range).itemSeasons, (0, 10));
  });

  test('validateSettings mirrors the server rules', () {
    expect(LobbyService.validateSettings(const GameSettings()), isNull);
    expect(LobbyService.validateSettings(const GameSettings(packs: {})), isNotNull);
    expect(LobbyService.validateSettings(const GameSettings(undercovers: 0)), isNotNull);
    expect(LobbyService.validateSettings(const GameSettings(mrWhites: 1)), contains('Mixed mode'));
    expect(LobbyService.validateSettings(const GameSettings(mrWhites: 1, decoyWord: true)), isNull);
    expect(LobbyService.validateSettings(const GameSettings(turnSeconds: 5)), isNotNull);
    expect(LobbyService.validateSettings(const GameSettings(turnSeconds: 301)), isNotNull);
    expect(LobbyService.validateSettings(const GameSettings(turnSeconds: 300)), isNull);
    expect(reactionEmoji.length, 8);
    expect(reactionEmoji.first, '\u{1F525}');
  });

  test('impostor limit follows 2 * impostors < players', () {
    expect(maxImpostorsFor(0), 1);
    expect(maxImpostorsFor(3), 1);
    expect(maxImpostorsFor(4), 1);
    expect(maxImpostorsFor(5), 2);
    expect(maxImpostorsFor(7), 3);
  });

  test('Lobby tolerates views with and without pool info', () {
    final old = Lobby.fromJson({'id': 'x', 'host': 'A'});
    expect(old.settings, const GameSettings());
    expect(old.poolSize, isNull);
    expect(old.seasonRange, isNull);
    expect(old.dailyTheme, isNull);
    expect(old.lastGuess, isNull);
    expect(old.winReason, isNull);
    expect(old.selectedPack, '');
    expect(old.round, 0);

    final lobby = Lobby.fromJson({
      'id': 'x',
      'host': 'A',
      'settings': {
        'packs': ['champions', 'items'],
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
    expect(lobby.poolSize!.champions, 173);
    expect(lobby.poolSize!['runes'], 0);
    expect(lobby.poolSize!.emptyPacks, isEmpty);
    expect(lobby.seasonRange!.items, (3, 16));
    expect(lobby.myIcon, startsWith('https://'));
  });

  test('Lobby reads every new view key', () {
    final lobby = Lobby.fromJson({
      'id': 'ABCDE',
      'host': 'Ashe',
      'players': ['Ashe', 'Braum', 'Caitlyn', 'Draven'],
      'spectators': ['Draven'],
      'gameStarted': true,
      'gamePhase': 'lastGuess',
      'alivePlayers': ['Ashe', 'Caitlyn'],
      'roundOrder': ['Caitlyn', 'Ashe'],
      'currentPlayerIndex': 1,
      'roundFinished': false,
      'round': 2,
      'deadline': 1700000000000,
      'votes': {'Ashe': 'Braum'},
      'lastVotes': {'Ashe': 'Braum', 'Caitlyn': 'Braum', 'Braum': 'skip'},
      'ballots': [
        {'Ashe': 'skip', 'Braum': 'skip', 'Caitlyn': 'skip'},
        {'Ashe': 'Braum', 'Caitlyn': 'Braum', 'Braum': 'skip'},
      ],
      'rolesAcknowledged': {'Ashe': true},
      'clues': [
        {'round': 1, 'player': 'Ashe', 'text': 'fox'},
        {'round': 1, 'player': 'Braum', 'text': 'tails'},
      ],
      'guesser': 'Braum',
      'lastGuess': {'player': 'Braum', 'word': 'Ahri', 'correct': false},
      'winner': 'Civilians',
      'winReason': 'eliminated',
      'lastEliminated': 'Braum',
      'selectedPack': 'abilities',
      'myRole': 'Undercover',
      'myWord': 'Orb of Deception (Ahri)',
      'myIcon': 'https://example/ahri.png',
      'myDecoy': true,
      'roles': {'Ashe': 'Civilian', 'Braum': 'MrWhite', 'Caitlyn': 'Undercover', 'Draven': 'Spectator'},
      'selectedWord': 'Charm (Ahri)',
      'decoyWord': 'Orb of Deception (Ahri)',
      'settings': {'packs': ['abilities'], 'undercovers': 1, 'mrWhites': 1, 'decoyWord': true},
      'poolSize': {'abilities': 700},
      'classes': ['Assassin', 'Mage'],
      'regions': ['Ionia', 'Shurima'],
      'resources': ['mana', 'none'],
      'lanes': ['top', 'mid', 'support'],
      'dailyTheme': {
        'id': 'shurima',
        'title': 'Shurima Day',
        'description': 'Only champions from Shurima and their abilities.',
        'filter': {
          'packs': ['champions', 'abilities'],
          'champRegions': ['Shurima'],
        },
      },
      'scores': {'Ashe': 3, 'Braum': 1},
      'gamesPlayed': 4,
      'achievements': {
        'Ashe': ['sharp_eye', 'first_blood'],
      },
      'stats': {
        'Ashe': {'civilianSurvivals': 2, 'impostorGames': 1, 'games': 4},
      },
      'connected': {'Ashe': true},
      'version': 12,
    });

    expect(lobby.spectators, ['Draven']);
    expect(lobby.isSpectator('Draven'), isTrue);
    expect(lobby.activePlayers, ['Ashe', 'Braum', 'Caitlyn']);
    expect(lobby.isLastGuess, isTrue);
    expect(lobby.round, 2);
    expect(lobby.deadline, 1700000000000);
    expect(lobby.deadlineRemaining(DateTime.fromMillisecondsSinceEpoch(1699999999000)), const Duration(seconds: 1));
    expect(lobby.deadlineRemaining(DateTime.fromMillisecondsSinceEpoch(1700000005000)), Duration.zero);
    expect(Lobby.fromJson({}).deadlineRemaining(DateTime.now()), isNull);
    expect(lobby.ballots.length, 2);
    expect(lobby.ballots.last['Caitlyn'], 'Braum');
    expect(lobby.clues, const [
      Clue(round: 1, player: 'Ashe', text: 'fox'),
      Clue(round: 1, player: 'Braum', text: 'tails'),
    ]);
    expect(lobby.guesser, 'Braum');
    expect(lobby.lastGuess, const LastGuess(player: 'Braum', word: 'Ahri', correct: false));
    expect(lobby.winReason, 'eliminated');
    expect(lobby.selectedPack, 'abilities');
    expect(lobby.selectedIsChampion, isFalse);
    expect(lobby.myDecoy, isTrue);
    expect(lobby.decoyWord, 'Orb of Deception (Ahri)');
    expect(lobby.impostorNames, 'Braum, Caitlyn');
    expect(lobby.undercoverNames, 'Caitlyn');
    expect(lobby.settings.mrWhites, 1);
    expect(lobby.poolSize!.total, 700);
    expect(lobby.classes, ['Assassin', 'Mage']);
    expect(lobby.regions, ['Ionia', 'Shurima']);
    expect(lobby.resources, ['mana', 'none']);
    expect(lobby.lanes, ['top', 'mid', 'support']);
    expect(Lobby.fromJson({}).lanes, isEmpty);
    expect(Lobby.fromJson({}).resources, isEmpty);
    expect(lobby.dailyTheme!.title, 'Shurima Day');
    expect(lobby.dailyTheme!.filter.packs, {'champions', 'abilities'});
    expect(lobby.dailyTheme!.filter.champRegions, {'Shurima'});
    expect(lobby.scores, {'Ashe': 3, 'Braum': 1});
    expect(lobby.gamesPlayed, 4);
    expect(lobby.achievements['Ashe'], ['sharp_eye', 'first_blood']);
    expect(lobby.stats['Ashe'], const PlayerStats(civilianSurvivals: 2, impostorGames: 1, games: 4));
    expect(lobby.version, 12);

    // A pre-packs server still names the pack through the old boolean.
    expect(Lobby.fromJson({'selectedIsChampion': true}).selectedPack, 'champions');
    expect(Lobby.fromJson({'winReason': ''}).winReason, isNull);
  });

  test('summary lines read naturally', () {
    expect(
      LobbyFiltersSummary.describe(const GameSettings(champSeasons: (1, 16), itemSeasons: (16, 16))),
      'Champions S1–S16 · Items S16',
    );
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(packs: {WordPack.items}, itemSeasons: (3, 10), itemTiers: {ItemTier.legendary}),
      ),
      'Items S3–S10 (1 of 5 tiers)',
    );
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(
          packs: {WordPack.champions, WordPack.abilities, WordPack.monsters},
          champSeasons: (1, 16),
          champClasses: {'Mage'},
        ),
      ),
      'Champions S1–S16 (Mage) · Abilities · Monsters',
    );
    // Buckets follow classes and regions, in the server's order and
    // lower-cased, so the line reads as one phrase.
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(
          packs: {WordPack.champions},
          champSeasons: (1, 16),
          champClasses: {'Mage'},
          champRanges: {ChampionRange.melee},
          champDifficulty: {ChampionDifficulty.hard},
        ),
      ),
      'Champions S1–S16 (Mage, melee, hard)',
    );
    // Lanes sit between regions and the buckets, in the server's order.
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(
          packs: {WordPack.champions},
          champSeasons: (1, 16),
          champClasses: {'Mage'},
          champLanes: {ChampionLane.jungle, ChampionLane.top},
        ),
      ),
      'Champions S1–S16 (Mage, top/jungle)',
    );
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(
          packs: {WordPack.champions},
          champSeasons: (1, 16),
          champRegions: {'Ionia'},
          champLanes: {ChampionLane.support},
          champRanges: {ChampionRange.ranged},
        ),
      ),
      'Champions S1–S16 (Ionia, support, ranged)',
    );
    expect(
      LobbyFiltersSummary.describe(
        const GameSettings(
          packs: {WordPack.abilities},
          champSeasons: (3, 16),
          champResources: {ChampionResource.other, ChampionResource.none},
          champDamage: {ChampionDamage.magic, ChampionDamage.physical},
        ),
      ),
      'Abilities S3–S16 (manaless/fury & other, physical/magic)',
    );
    expect(
      LobbyRulesSummary.describe(const GameSettings(undercovers: 2, mrWhites: 1, decoyWord: true, randomOrder: true, turnSeconds: 60)),
      '2 Undercovers · 1 Mr. White · decoy words · random turn order · 60 s per turn',
    );
  });
}
