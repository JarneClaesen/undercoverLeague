/// The host's word-pool filter, mirrored from the server's `Filter`. The
/// server normalizes what it sends back (concrete season bounds, explicit
/// tier list), so a [GameSettings] parsed from a view is always complete;
/// one built locally may still carry unbounded (0) seasons.
class GameSettings {
  final bool useChampions;
  final bool useItems;

  /// Inclusive release-season range for champions, e.g. (1, 16). 0 = unbounded.
  final (int, int) champSeasons;

  /// Inclusive range of seasons an item must have existed in.
  final (int, int) itemSeasons;

  /// Item tiers that stay in the pool; empty means no items at all.
  final Set<String> itemTiers;

  const GameSettings({
    this.useChampions = true,
    this.useItems = true,
    this.champSeasons = (0, 0),
    this.itemSeasons = (0, 0),
    this.itemTiers = const {...ItemTier.all},
  });

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    final tiers = json['itemTiers'];
    return GameSettings(
      useChampions: json['useChampions'] as bool? ?? true,
      useItems: json['useItems'] as bool? ?? true,
      champSeasons: _range(json['champSeasons']),
      itemSeasons: _range(json['itemSeasons']),
      // null = every tier, [] = none; the wire distinguishes the two.
      itemTiers: tiers == null ? {...ItemTier.all} : (tiers as List).cast<String>().toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
        'useChampions': useChampions,
        'useItems': useItems,
        'champSeasons': [champSeasons.$1, champSeasons.$2],
        'itemSeasons': [itemSeasons.$1, itemSeasons.$2],
        'itemTiers': ItemTier.all.where(itemTiers.contains).toList(),
      };

  GameSettings copyWith({
    bool? useChampions,
    bool? useItems,
    (int, int)? champSeasons,
    (int, int)? itemSeasons,
    Set<String>? itemTiers,
  }) =>
      GameSettings(
        useChampions: useChampions ?? this.useChampions,
        useItems: useItems ?? this.useItems,
        champSeasons: champSeasons ?? this.champSeasons,
        itemSeasons: itemSeasons ?? this.itemSeasons,
        itemTiers: itemTiers ?? this.itemTiers,
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

  @override
  bool operator ==(Object other) =>
      other is GameSettings &&
      other.useChampions == useChampions &&
      other.useItems == useItems &&
      other.champSeasons == champSeasons &&
      other.itemSeasons == itemSeasons &&
      other.itemTiers.length == itemTiers.length &&
      other.itemTiers.containsAll(itemTiers);

  @override
  int get hashCode => Object.hash(useChampions, useItems, champSeasons, itemSeasons, itemTiers.length);
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

/// How many words the current settings can draw from; sent while in the lobby.
class PoolSize {
  final int champions;
  final int items;

  const PoolSize({required this.champions, required this.items});

  factory PoolSize.fromJson(Map<String, dynamic> json) => PoolSize(
        champions: json['champions'] as int? ?? 0,
        items: json['items'] as int? ?? 0,
      );

  int get total => champions + items;
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
}
