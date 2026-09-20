import 'package:undercoverleague/models/game_settings.dart';

/// A one-tap word pool for the lobby's presets row. Only the filter half of
/// the settings changes; the rules the host set stay as they are.
class FilterPreset {
  final String id;
  final String label;
  final String description;

  /// Builds the pool from the current settings and the catalog's season
  /// range (null before the first view; presets that need it then leave the
  /// seasons alone).
  final GameSettings Function(GameSettings current, SeasonRange? range) build;

  const FilterPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.build,
  });

  GameSettings apply(GameSettings current, SeasonRange? range) => current.withFilterOf(build(current, range));

  /// A filter that draws from [packs] with every other knob open.
  static GameSettings _pool(
    Set<String> packs, {
    (int, int) champSeasons = (0, 0),
    (int, int) itemSeasons = (0, 0),
    Set<String> itemTiers = const {...ItemTier.all},
    Set<String> champClasses = const {},
  }) =>
      GameSettings(
        packs: packs,
        champSeasons: champSeasons,
        itemSeasons: itemSeasons,
        itemTiers: itemTiers,
        champClasses: champClasses,
        champRegions: const {},
      );

  static final List<FilterPreset> all = [
    FilterPreset(
      id: 'veteran',
      label: 'Veteran',
      description: 'Champions from Seasons 1–5 and the items of Seasons 3–5.',
      build: (_, _) => _pool({WordPack.champions, WordPack.items}, champSeasons: (1, 5), itemSeasons: (3, 5)),
    ),
    FilterPreset(
      id: 'fresh',
      label: 'Fresh meta',
      description: 'Only this season\'s champions and items.',
      build: (current, range) {
        final champ = range?.champions.$2 ?? 0;
        final item = range?.items.$2 ?? 0;
        return _pool(
          {WordPack.champions, WordPack.items},
          champSeasons: champ == 0 ? current.champSeasons : (champ, champ),
          itemSeasons: item == 0 ? current.itemSeasons : (item, item),
        );
      },
    ),
    FilterPreset(
      id: 'legendary',
      label: 'Legendary only',
      description: 'Completed items, nothing else.',
      build: (_, _) => _pool({WordPack.items}, itemTiers: {ItemTier.legendary}),
    ),
    FilterPreset(
      id: 'components',
      label: 'Components only',
      description: 'The items you build other items from.',
      build: (_, _) => _pool({WordPack.items}, itemTiers: {ItemTier.component}),
    ),
    FilterPreset(
      id: 'boots',
      label: 'Boots only',
      description: 'Every pair of boots ever sold.',
      build: (_, _) => _pool({WordPack.items}, itemTiers: {ItemTier.boots}),
    ),
    FilterPreset(
      id: 'mages',
      label: 'Mages only',
      description: 'Mage champions and their abilities.',
      build: (_, _) => _pool({WordPack.champions, WordPack.abilities}, champClasses: {ChampionClass.mage}),
    ),
    FilterPreset(
      id: 'everything',
      label: 'Everything',
      description: 'Every pack, every season, every tier.',
      build: (_, _) => _pool(WordPack.all.toSet()),
    ),
  ];
}
