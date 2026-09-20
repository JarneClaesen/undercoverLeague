import 'package:flutter/material.dart';

/// The host's lobby settings, mirrored from the server's `Settings` (the
/// word-pool `Filter` flattened together with the rules). The server
/// normalizes what it sends back (concrete season bounds, explicit tier
/// list), so a [GameSettings] parsed from a view is always complete; one
/// built locally may still carry unbounded (0) seasons.
class GameSettings {
  // --- Filter ---------------------------------------------------------------

  /// Enabled word packs, see [WordPack]. Never empty when sent.
  final Set<String> packs;

  /// Inclusive release-season range for champions, e.g. (1, 16). 0 = unbounded.
  /// Also filters the abilities pack through each ability's champion.
  final (int, int) champSeasons;

  /// Inclusive range of seasons an item must have existed in.
  final (int, int) itemSeasons;

  /// Item tiers that stay in the pool; empty means no items at all.
  final Set<String> itemTiers;

  /// Champion classes (Data Dragon tags) to keep; empty means every class.
  final Set<String> champClasses;

  /// Runeterra regions to keep; empty means every region.
  final Set<String> champRegions;

  /// Fixed buckets the server derives from Data Dragon, see [ChampionRange],
  /// [ChampionResource], [ChampionDamage] and [ChampionDifficulty]; empty
  /// means every value.
  final Set<String> champRanges;
  final Set<String> champResources;
  final Set<String> champDamage;
  final Set<String> champDifficulty;

  // --- Rules ----------------------------------------------------------------

  /// Players who get a decoy word (or nothing); at least 1.
  final int undercovers;

  /// "Mixed mode": players who get no word at all. Needs [decoyWord].
  final int mrWhites;

  /// Undercovers get a related word instead of nothing.
  final bool decoyWord;

  /// Reshuffle the speaking order every round; off keeps the order and
  /// rotates the first speaker.
  final bool randomOrder;

  /// Seconds per describing turn; 0 = no timer, else 10..300.
  final int turnSeconds;

  /// Turns end by submitting a typed clue that stays in a public log.
  final bool clueLog;

  /// "Play again" passes the host seat to the next player.
  final bool rotateHost;

  const GameSettings({
    this.packs = WordPack.defaults,
    this.champSeasons = (0, 0),
    this.itemSeasons = (0, 0),
    this.itemTiers = const {...ItemTier.all},
    this.champClasses = const {},
    this.champRegions = const {},
    this.champRanges = const {},
    this.champResources = const {},
    this.champDamage = const {},
    this.champDifficulty = const {},
    this.undercovers = 1,
    this.mrWhites = 0,
    this.decoyWord = false,
    this.randomOrder = false,
    this.turnSeconds = 0,
    this.clueLog = false,
    this.rotateHost = false,
  });

  /// Reads the wire shape. Every key is optional so settings saved by an
  /// older build (which only knew `useChampions`/`useItems` and no rules)
  /// still load with the defaults filled in.
  factory GameSettings.fromJson(Map<String, dynamic> json) {
    final tiers = json['itemTiers'];
    final undercovers = (json['undercovers'] as num?)?.toInt() ?? 1;
    return GameSettings(
      packs: _packs(json),
      champSeasons: _range(json['champSeasons']),
      itemSeasons: _range(json['itemSeasons']),
      // null = every tier, [] = none; the wire distinguishes the two.
      itemTiers: tiers == null ? {...ItemTier.all} : _stringSet(tiers),
      champClasses: _stringSet(json['champClasses']),
      champRegions: _stringSet(json['champRegions']),
      champRanges: _stringSet(json['champRanges']),
      champResources: _stringSet(json['champResources']),
      champDamage: _stringSet(json['champDamage']),
      champDifficulty: _stringSet(json['champDifficulty']),
      undercovers: undercovers < 1 ? 1 : undercovers,
      mrWhites: (json['mrWhites'] as num?)?.toInt() ?? 0,
      decoyWord: json['decoyWord'] as bool? ?? false,
      randomOrder: json['randomOrder'] as bool? ?? false,
      turnSeconds: (json['turnSeconds'] as num?)?.toInt() ?? 0,
      clueLog: json['clueLog'] as bool? ?? false,
      rotateHost: json['rotateHost'] as bool? ?? false,
    );
  }

  static Set<String> _packs(Map<String, dynamic> json) {
    final packs = json['packs'];
    if (packs is List) return _stringSet(packs);
    // Legacy booleans from before packs existed; absent means on.
    return {
      if (json['useChampions'] as bool? ?? true) WordPack.champions,
      if (json['useItems'] as bool? ?? true) WordPack.items,
    };
  }

  static Set<String> _stringSet(Object? v) => (v as List?)?.cast<String>().toSet() ?? const {};

  Map<String, dynamic> toJson() => {
        'packs': WordPack.all.where(packs.contains).toList(),
        'champSeasons': [champSeasons.$1, champSeasons.$2],
        'itemSeasons': [itemSeasons.$1, itemSeasons.$2],
        'itemTiers': ItemTier.all.where(itemTiers.contains).toList(),
        'champClasses': champClasses.toList()..sort(),
        'champRegions': champRegions.toList()..sort(),
        'champRanges': ChampionRange.all.where(champRanges.contains).toList(),
        'champResources': ChampionResource.all.where(champResources.contains).toList(),
        'champDamage': ChampionDamage.all.where(champDamage.contains).toList(),
        'champDifficulty': ChampionDifficulty.all.where(champDifficulty.contains).toList(),
        'undercovers': undercovers,
        'mrWhites': mrWhites,
        'decoyWord': decoyWord,
        'randomOrder': randomOrder,
        'turnSeconds': turnSeconds,
        'clueLog': clueLog,
        'rotateHost': rotateHost,
      };

  bool get useChampions => packs.contains(WordPack.champions);
  bool get useItems => packs.contains(WordPack.items);
  bool get useAbilities => packs.contains(WordPack.abilities);

  /// Whether the champion-only filters (seasons, classes, regions and the
  /// four buckets) matter.
  bool get filtersChampions => useChampions || useAbilities;

  /// How many of the champion chip filters are narrowing the pool.
  int get activeChampionFilters =>
      champClasses.length + champRegions.length + champRanges.length + champResources.length + champDamage.length + champDifficulty.length;

  /// Impostors per game: the Undercovers plus Mr. Whites.
  int get impostors => undercovers + mrWhites;

  GameSettings copyWith({
    Set<String>? packs,
    (int, int)? champSeasons,
    (int, int)? itemSeasons,
    Set<String>? itemTiers,
    Set<String>? champClasses,
    Set<String>? champRegions,
    Set<String>? champRanges,
    Set<String>? champResources,
    Set<String>? champDamage,
    Set<String>? champDifficulty,
    int? undercovers,
    int? mrWhites,
    bool? decoyWord,
    bool? randomOrder,
    int? turnSeconds,
    bool? clueLog,
    bool? rotateHost,
  }) =>
      GameSettings(
        packs: packs ?? this.packs,
        champSeasons: champSeasons ?? this.champSeasons,
        itemSeasons: itemSeasons ?? this.itemSeasons,
        itemTiers: itemTiers ?? this.itemTiers,
        champClasses: champClasses ?? this.champClasses,
        champRegions: champRegions ?? this.champRegions,
        champRanges: champRanges ?? this.champRanges,
        champResources: champResources ?? this.champResources,
        champDamage: champDamage ?? this.champDamage,
        champDifficulty: champDifficulty ?? this.champDifficulty,
        undercovers: undercovers ?? this.undercovers,
        mrWhites: mrWhites ?? this.mrWhites,
        decoyWord: decoyWord ?? this.decoyWord,
        randomOrder: randomOrder ?? this.randomOrder,
        turnSeconds: turnSeconds ?? this.turnSeconds,
        clueLog: clueLog ?? this.clueLog,
        rotateHost: rotateHost ?? this.rotateHost,
      );

  /// These settings with the word-pool half replaced by [filter]'s (packs,
  /// seasons, tiers, classes, regions, buckets); the rules stay. Used to apply the
  /// daily theme, which only describes a pool.
  GameSettings withFilterOf(GameSettings filter) => copyWith(
        packs: filter.packs,
        champSeasons: filter.champSeasons,
        itemSeasons: filter.itemSeasons,
        itemTiers: filter.itemTiers,
        champClasses: filter.champClasses,
        champRegions: filter.champRegions,
        champRanges: filter.champRanges,
        champResources: filter.champResources,
        champDamage: filter.champDamage,
        champDifficulty: filter.champDifficulty,
      );

  /// Clamps both ranges into what the catalog offers, so defaults saved
  /// last season still make sense after a new one starts.
  GameSettings clampedTo(SeasonRange range) => copyWith(
        champSeasons: _clamp(champSeasons, range.champions),
        itemSeasons: _clamp(itemSeasons, range.items),
      );

  /// The inverse of [clampedTo], for saving: a bound sitting on the edge of
  /// the catalog becomes 0 ("oldest" / "newest"), so a host who chose
  /// everything up to the current season still gets next season's
  /// champions and items once they exist.
  GameSettings unboundedWithin(SeasonRange range) => copyWith(
        champSeasons: _unbound(champSeasons, range.champions),
        itemSeasons: _unbound(itemSeasons, range.items),
      );

  static (int, int) _unbound((int, int) r, (int, int) bounds) {
    final (lo, hi) = bounds;
    if (lo == 0 && hi == 0) return r;
    return (r.$1 <= lo ? 0 : r.$1, r.$2 >= hi ? 0 : r.$2);
  }

  static (int, int) _clamp((int, int) r, (int, int) bounds) {
    final (lo, hi) = bounds;
    if (lo == 0 && hi == 0) return r;
    var a = r.$1 == 0 ? lo : r.$1.clamp(lo, hi);
    var b = r.$2 == 0 ? hi : r.$2.clamp(lo, hi);
    if (a > b) a = b;
    return (a, b);
  }

  static (int, int) _range(Object? v) {
    final list = (v as List?)?.cast<num>();
    if (list == null || list.length != 2) return (0, 0);
    return (list[0].toInt(), list[1].toInt());
  }

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  @override
  bool operator ==(Object other) =>
      other is GameSettings &&
      _sameSet(other.packs, packs) &&
      other.champSeasons == champSeasons &&
      other.itemSeasons == itemSeasons &&
      _sameSet(other.itemTiers, itemTiers) &&
      _sameSet(other.champClasses, champClasses) &&
      _sameSet(other.champRegions, champRegions) &&
      _sameSet(other.champRanges, champRanges) &&
      _sameSet(other.champResources, champResources) &&
      _sameSet(other.champDamage, champDamage) &&
      _sameSet(other.champDifficulty, champDifficulty) &&
      other.undercovers == undercovers &&
      other.mrWhites == mrWhites &&
      other.decoyWord == decoyWord &&
      other.randomOrder == randomOrder &&
      other.turnSeconds == turnSeconds &&
      other.clueLog == clueLog &&
      other.rotateHost == rotateHost;

  @override
  int get hashCode => Object.hash(
        packs.length,
        champSeasons,
        itemSeasons,
        itemTiers.length,
        champClasses.length,
        champRegions.length,
        champRanges.length,
        champResources.length,
        champDamage.length,
        champDifficulty.length,
        undercovers,
        mrWhites,
        decoyWord,
        randomOrder,
        turnSeconds,
        clueLog,
        rotateHost,
      );

  @override
  String toString() => 'GameSettings(${toJson()})';
}

/// Word packs as the server names them, in its order.
class WordPack {
  static const champions = 'champions';
  static const items = 'items';
  static const spells = 'spells';
  static const runes = 'runes';
  static const abilities = 'abilities';
  static const skinLines = 'skinlines';
  static const monsters = 'monsters';

  static const all = [champions, items, spells, runes, abilities, skinLines, monsters];

  /// What a fresh lobby draws from.
  static const Set<String> defaults = {champions, items};

  static String label(String pack) => switch (pack) {
        champions => 'Champions',
        items => 'Items',
        spells => 'Summoner spells',
        runes => 'Runes',
        abilities => 'Abilities',
        skinLines => 'Skin lines',
        monsters => 'Monsters',
        _ => pack,
      };

  /// Singular noun for counts ("1 champion", "2 champions").
  static String noun(String pack, int n) {
    final one = switch (pack) {
      champions => 'champion',
      items => 'item',
      spells => 'summoner spell',
      runes => 'rune',
      abilities => 'ability',
      skinLines => 'skin line',
      monsters => 'monster',
      _ => pack,
    };
    if (n == 1) return one;
    return one == 'ability' ? 'abilities' : '${one}s';
  }

  static IconData icon(String pack) => switch (pack) {
        champions => Icons.shield_outlined,
        items => Icons.inventory_2_outlined,
        spells => Icons.auto_fix_high_outlined,
        runes => Icons.hexagon_outlined,
        abilities => Icons.bolt_outlined,
        skinLines => Icons.checkroom_outlined,
        monsters => Icons.pets_outlined,
        _ => Icons.category_outlined,
      };
}

/// Item tiers as the server names them, in shop order.
class ItemTier {
  static const starter = 'starter';
  static const consumable = 'consumable';
  static const boots = 'boots';
  static const component = 'component';
  static const legendary = 'legendary';

  static const all = [starter, consumable, boots, component, legendary];

  static String label(String tier) => switch (tier) {
        starter => 'Starter',
        consumable => 'Consumables & Trinkets',
        boots => 'Boots',
        component => 'Components',
        legendary => 'Legendary',
        _ => tier,
      };
}

/// Champion classes (Data Dragon tags) and regions the server knows; the
/// live lists come with the lobby view, these are for tests.
class ChampionClass {
  static const assassin = 'Assassin';
  static const fighter = 'Fighter';
  static const mage = 'Mage';
  static const marksman = 'Marksman';
  static const support = 'Support';
  static const tank = 'Tank';

  static const all = [assassin, fighter, mage, marksman, support, tank];
}

/// Melee or ranged, from the base attack range (300+ is ranged).
class ChampionRange {
  static const melee = 'melee';
  static const ranged = 'ranged';

  static const all = [melee, ranged];

  static String label(String v) => switch (v) {
        melee => 'Melee',
        ranged => 'Ranged',
        _ => v,
      };
}

/// The resource bar, bucketed by the server; the buckets actually present
/// in the catalog come with the lobby view (`resources`), since a catalog
/// can lack energy champions.
class ChampionResource {
  static const mana = 'mana';
  static const energy = 'energy';
  static const none = 'none';
  static const other = 'other';

  static const all = [mana, energy, none, other];

  static String label(String v) => switch (v) {
        mana => 'Mana',
        energy => 'Energy',
        none => 'Manaless',
        other => 'Fury & other',
        _ => v,
      };
}

/// Main damage type, from Riot's attack vs. magic ratings.
class ChampionDamage {
  static const physical = 'physical';
  static const magic = 'magic';
  static const mixed = 'mixed';

  static const all = [physical, magic, mixed];

  static String label(String v) => switch (v) {
        physical => 'Physical',
        magic => 'Magic',
        mixed => 'Mixed',
        _ => v,
      };
}

/// Riot's 1-10 difficulty rating in three steps.
class ChampionDifficulty {
  static const easy = 'easy';
  static const medium = 'medium';
  static const hard = 'hard';

  static const all = [easy, medium, hard];

  static String label(String v) => switch (v) {
        easy => 'Easy',
        medium => 'Medium',
        hard => 'Hard',
        _ => v,
      };
}

/// The turn-timer lengths the lobby offers, in seconds; 0 = off.
const List<int> turnTimerChoices = [0, 30, 60, 90, 120];

/// How many words the current settings can draw from, one entry per
/// enabled pack; sent while in the lobby.
class PoolSize {
  final Map<String, int> perPack;

  const PoolSize(this.perPack);

  factory PoolSize.fromJson(Map<String, dynamic> json) =>
      PoolSize({for (final e in json.entries) e.key: (e.value as num?)?.toInt() ?? 0});

  int operator [](String pack) => perPack[pack] ?? 0;

  int get champions => this[WordPack.champions];
  int get items => this[WordPack.items];

  int get total => perPack.values.fold(0, (a, b) => a + b);

  /// Enabled packs, in [WordPack.all] order, that the filters left empty.
  List<String> get emptyPacks => WordPack.all.where((p) => perPack.containsKey(p) && perPack[p] == 0).toList();
}

/// The seasons the catalog covers, i.e. the bounds of the sliders.
class SeasonRange {
  final (int, int) champions;
  final (int, int) items;

  const SeasonRange({required this.champions, required this.items});

  factory SeasonRange.fromJson(Map<String, dynamic> json) => SeasonRange(
        champions: GameSettings._range(json['champions']),
        items: GameSettings._range(json['items']),
      );

  /// The newest season the catalog has, 0 when unknown.
  int get current => champions.$2 > items.$2 ? champions.$2 : items.$2;
}
