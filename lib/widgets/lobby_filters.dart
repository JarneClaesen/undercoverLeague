import 'package:flutter/material.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/lobby_pool_toggles.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

/// The host's word-pool controls: which packs, which seasons, which item
/// tiers, which champion classes, regions, lanes, range, resource, damage
/// type and difficulty, plus the server's count of what that leaves to draw
/// from.
///
/// [settings] is whatever the server last broadcast (or the screen's
/// pending draft) and is the source of truth; while a slider is being
/// dragged a local draft is shown instead so the thumbs do not jump back on
/// every incoming view, and [onChanged] fires once on release. Chips and
/// toggles fire immediately.
class LobbyFilters extends StatefulWidget {
  final GameSettings settings;
  final SeasonRange? seasonRange;
  final PoolSize? poolSize;

  /// Classes, regions, resource buckets and lanes present in the catalog
  /// (from the lobby view); empty hides the matching chips. Range, damage
  /// and difficulty are fixed lists.
  final List<String> classes;
  final List<String> regions;
  final List<String> resources;
  final List<String> lanes;
  final ValueChanged<GameSettings> onChanged;

  const LobbyFilters({
    super.key,
    required this.settings,
    required this.seasonRange,
    required this.poolSize,
    this.classes = const [],
    this.regions = const [],
    this.resources = const [],
    this.lanes = const [],
    required this.onChanged,
  });

  @override
  State<LobbyFilters> createState() => _LobbyFiltersState();
}

class _LobbyFiltersState extends State<LobbyFilters> {
  GameSettings? _draft;
  bool _championFiltersOpen = false;

  GameSettings get _current => _draft ?? widget.settings;

  void _commit(GameSettings next) {
    setState(() => _draft = null);
    widget.onChanged(next);
  }

  Set<String> _toggled(Set<String> set, String value, bool on) {
    final next = {...set};
    if (on) {
      next.add(value);
    } else {
      next.remove(value);
    }
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final s = _current;
    final range = widget.seasonRange;
    final champFilters = s.filtersChampions;
    final activeChampionFilters = s.activeChampionFilters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LobbyPoolToggles(
          packs: s.packs,
          poolSize: widget.poolSize,
          onChanged: (packs) => _commit(s.copyWith(packs: packs)),
        ),
        if (range != null) ...[
          if (champFilters) ...[
            const SizedBox(height: 16),
            _SeasonSlider(
              title: s.useChampions ? 'Champions · released' : 'Abilities · champion released',
              bounds: range.champions,
              value: s.champSeasons,
              enabled: true,
              onChanged: (v) => setState(() => _draft = s.copyWith(champSeasons: v)),
              onChangeEnd: (v) => _commit(s.copyWith(champSeasons: v)),
            ),
          ],
          if (s.useItems) ...[
            const SizedBox(height: 12),
            _SeasonSlider(
              title: 'Items · in the shop',
              bounds: range.items,
              value: s.itemSeasons,
              enabled: true,
              onChanged: (v) => setState(() => _draft = s.copyWith(itemSeasons: v)),
              onChangeEnd: (v) => _commit(s.copyWith(itemSeasons: v)),
            ),
          ],
        ],
        if (s.useItems) ...[
          const SizedBox(height: 14),
          const HextechSectionLabel('Item tiers'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tier in ItemTier.all)
                HextechChip(
                  label: ItemTier.label(tier),
                  dense: true,
                  selected: s.itemTiers.contains(tier),
                  onSelected: (on) => _commit(s.copyWith(itemTiers: _toggled(s.itemTiers, tier, on))),
                ),
            ],
          ),
        ],
        // Range, damage and difficulty are fixed lists, so the section is
        // always there; a catalog too old to carry them just counts nothing
        // for those chips, which the pool size shows.
        if (champFilters) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => _championFiltersOpen = !_championFiltersOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(child: HextechSectionLabel('Champion filters')),
                  Text(
                    activeChampionFilters == 0 ? 'ALL' : '$activeChampionFilters ACTIVE',
                    style: textTheme.labelSmall?.copyWith(
                      color: activeChampionFilters == 0 ? hextech.textDisabled : hextech.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _championFiltersOpen ? 0.5 : 0,
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.enter,
                    child: Icon(Icons.expand_more, size: 18, color: hextech.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          MotionSize(
            alignment: Alignment.topLeft,
            child: _championFiltersOpen
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.classes.isNotEmpty)
                        _ChipRow(
                          hint: 'Classes · none selected means every class',
                          values: widget.classes,
                          selected: s.champClasses,
                          onToggled: (c, on) => _commit(s.copyWith(champClasses: _toggled(s.champClasses, c, on))),
                        ),
                      if (widget.regions.isNotEmpty)
                        _ChipRow(
                          hint: 'Regions · none selected means every region',
                          values: widget.regions,
                          selected: s.champRegions,
                          onToggled: (r, on) => _commit(s.copyWith(champRegions: _toggled(s.champRegions, r, on))),
                        ),
                      if (widget.lanes.isNotEmpty)
                        _ChipRow(
                          hint: 'Lane · where the champion is played',
                          values: widget.lanes,
                          label: ChampionLane.label,
                          selected: s.champLanes,
                          onToggled: (v, on) => _commit(s.copyWith(champLanes: _toggled(s.champLanes, v, on))),
                        ),
                      _ChipRow(
                        hint: 'Range · melee, ranged or both',
                        values: ChampionRange.all,
                        label: ChampionRange.label,
                        selected: s.champRanges,
                        onToggled: (v, on) => _commit(s.copyWith(champRanges: _toggled(s.champRanges, v, on))),
                      ),
                      if (widget.resources.isNotEmpty)
                        _ChipRow(
                          hint: 'Resource · what the champion runs on',
                          values: widget.resources,
                          label: ChampionResource.label,
                          selected: s.champResources,
                          onToggled: (v, on) => _commit(s.copyWith(champResources: _toggled(s.champResources, v, on))),
                        ),
                      _ChipRow(
                        hint: 'Damage · by Riot\'s attack and magic ratings',
                        values: ChampionDamage.all,
                        label: ChampionDamage.label,
                        selected: s.champDamage,
                        onToggled: (v, on) => _commit(s.copyWith(champDamage: _toggled(s.champDamage, v, on))),
                      ),
                      _ChipRow(
                        hint: 'Difficulty · Riot\'s rating in three steps',
                        values: ChampionDifficulty.all,
                        label: ChampionDifficulty.label,
                        selected: s.champDifficulty,
                        onToggled: (v, on) => _commit(s.copyWith(champDifficulty: _toggled(s.champDifficulty, v, on))),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        const SizedBox(height: 14),
        PoolSizeLine(settings: s, poolSize: widget.poolSize),
      ],
    );
  }
}

/// One labelled row of multi-select chips inside the champion filters:
/// a hint line, then a chip per value; none selected means every value.
class _ChipRow extends StatelessWidget {
  final String hint;
  final List<String> values;
  final String Function(String value)? label;
  final Set<String> selected;
  final void Function(String value, bool on) onToggled;

  const _ChipRow({
    required this.hint,
    required this.values,
    this.label,
    required this.selected,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Text(hint, style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              HextechChip(
                label: label?.call(v) ?? v,
                dense: true,
                selected: selected.contains(v),
                onSelected: (on) => onToggled(v, on),
              ),
          ],
        ),
      ],
    );
  }
}

class _SeasonSlider extends StatelessWidget {
  final String title;
  final (int, int) bounds;
  final (int, int) value;
  final bool enabled;
  final ValueChanged<(int, int)> onChanged;
  final ValueChanged<(int, int)> onChangeEnd;

  const _SeasonSlider({
    required this.title,
    required this.bounds,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final (min, max) = bounds;

    final lo = value.$1.clamp(min, max).toDouble();
    final hi = value.$2.clamp(min, max).toDouble();
    final summary = lo == hi ? 'S${lo.toInt()}' : 'S${lo.toInt()} – S${hi.toInt()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: HextechSectionLabel(title, enabled: enabled)),
            Text(
              summary,
              style: textTheme.labelMedium?.copyWith(color: enabled ? hextech.accent : hextech.textDisabled),
            ),
          ],
        ),
        if (max <= min)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Only season $max is available',
              style: textTheme.bodySmall?.copyWith(color: hextech.textDisabled),
            ),
          )
        else
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: hextech.accent,
              inactiveTrackColor: hextech.panelBorder,
              thumbColor: HextechColors.goldBright,
              overlayColor: hextech.accent.withValues(alpha: 0.15),
              valueIndicatorColor: HextechColors.navy,
              valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(color: HextechColors.goldBright),
              disabledActiveTrackColor: hextech.textDisabled,
              disabledInactiveTrackColor: hextech.panelBorder,
              disabledThumbColor: hextech.textDisabled,
              rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
              trackHeight: 3,
            ),
            child: RangeSlider(
              values: RangeValues(lo, hi),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              labels: RangeLabels('S${lo.toInt()}', 'S${hi.toInt()}'),
              onChanged: enabled ? (v) => onChanged((v.start.round(), v.end.round())) : null,
              onChangeEnd: enabled ? (v) => onChangeEnd((v.start.round(), v.end.round())) : null,
            ),
          ),
      ],
    );
  }
}

/// "142 champions · 380 items" for the current settings; a zero is shown in
/// the danger colour because the game cannot start from an empty pool.
class PoolSizeLine extends StatelessWidget {
  final GameSettings settings;
  final PoolSize? poolSize;

  const PoolSizeLine({super.key, required this.settings, required this.poolSize});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final size = poolSize;
    if (size == null) {
      return Text('Counting the pool…', style: textTheme.bodySmall?.copyWith(color: hextech.textDisabled));
    }

    final parts = <TextSpan>[
      for (final pack in WordPack.all)
        if (settings.packs.contains(pack))
          TextSpan(
            text: '${size[pack]} ${WordPack.noun(pack, size[pack])}',
            style: textTheme.bodyMedium?.copyWith(
              color: size[pack] == 0 ? HextechColors.dangerBright : hextech.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
    ];

    return Text.rich(
      TextSpan(
        style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
        children: [
          const TextSpan(text: 'In the pool: '),
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const TextSpan(text: ' · '),
            parts[i],
          ],
        ],
      ),
    );
  }
}

/// One line describing the host's settings, for everyone else in the lobby.
class LobbyFiltersSummary extends StatelessWidget {
  final GameSettings settings;
  final PoolSize? poolSize;

  const LobbyFiltersSummary({super.key, required this.settings, required this.poolSize});

  static String describe(GameSettings s) {
    String range((int, int) r) => r.$1 == r.$2 ? 'S${r.$1}' : 'S${r.$1}–S${r.$2}';
    // Classes and regions are proper nouns and read as they are; the
    // buckets get their labels, lower-cased so "Mage, melee, hard" reads
    // as one phrase.
    String buckets(List<String> all, Set<String> picked, String Function(String) label) =>
        all.where(picked.contains).map((v) => label(v).toLowerCase()).join('/');
    final champExtras = <String>[
      if (s.champClasses.isNotEmpty) (s.champClasses.toList()..sort()).join('/'),
      if (s.champRegions.isNotEmpty) (s.champRegions.toList()..sort()).join('/'),
      if (s.champLanes.isNotEmpty) buckets(ChampionLane.all, s.champLanes, ChampionLane.label),
      if (s.champRanges.isNotEmpty) buckets(ChampionRange.all, s.champRanges, ChampionRange.label),
      if (s.champResources.isNotEmpty) buckets(ChampionResource.all, s.champResources, ChampionResource.label),
      if (s.champDamage.isNotEmpty) buckets(ChampionDamage.all, s.champDamage, ChampionDamage.label),
      if (s.champDifficulty.isNotEmpty) buckets(ChampionDifficulty.all, s.champDifficulty, ChampionDifficulty.label),
    ];
    final champSuffix = champExtras.isEmpty ? '' : ' (${champExtras.join(', ')})';
    final parts = <String>[
      for (final pack in WordPack.all)
        if (s.packs.contains(pack))
          switch (pack) {
            WordPack.champions => 'Champions ${range(s.champSeasons)}$champSuffix',
            WordPack.items => 'Items ${range(s.itemSeasons)}'
                '${s.itemTiers.length == ItemTier.all.length ? '' : ' (${s.itemTiers.length} of ${ItemTier.all.length} tiers)'}',
            WordPack.abilities => 'Abilities${s.useChampions ? '' : ' ${range(s.champSeasons)}$champSuffix'}',
            _ => WordPack.label(pack),
          },
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const HextechSectionLabel('Word packs'),
        const SizedBox(height: 8),
        Text(describe(settings), style: textTheme.bodyMedium?.copyWith(color: hextech.textPrimary)),
        const SizedBox(height: 6),
        PoolSizeLine(settings: settings, poolSize: poolSize),
      ],
    );
  }
}
