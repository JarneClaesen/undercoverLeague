import 'package:flutter/material.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/lobby_pool_toggles.dart';

/// The host's word-pool controls: which categories, which seasons and which
/// item tiers, plus the server's count of what that leaves to draw from.
///
/// [settings] is whatever the server last broadcast and is the source of
/// truth; while a slider is being dragged a local draft is shown instead so
/// the thumbs do not jump back on every incoming view, and [onChanged] fires
/// once on release. Chips and toggles fire immediately.
class LobbyFilters extends StatefulWidget {
  final GameSettings settings;
  final SeasonRange? seasonRange;
  final PoolSize? poolSize;
  final ValueChanged<GameSettings> onChanged;

  const LobbyFilters({
    super.key,
    required this.settings,
    required this.seasonRange,
    required this.poolSize,
    required this.onChanged,
  });

  @override
  State<LobbyFilters> createState() => _LobbyFiltersState();
}

class _LobbyFiltersState extends State<LobbyFilters> {
  GameSettings? _draft;

  GameSettings get _current => _draft ?? widget.settings;

  void _commit(GameSettings next) {
    setState(() => _draft = null);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final s = _current;
    final range = widget.seasonRange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LobbyPoolToggles(
          useChampions: s.useChampions,
          useItems: s.useItems,
          onChanged: (champions, items) => _commit(s.copyWith(useChampions: champions, useItems: items)),
        ),
        if (range != null) ...[
          const SizedBox(height: 16),
          _SeasonSlider(
            title: 'CHAMPIONS · RELEASED',
            bounds: range.champions,
            value: s.champSeasons,
            enabled: s.useChampions,
            onChanged: (v) => setState(() => _draft = s.copyWith(champSeasons: v)),
            onChangeEnd: (v) => _commit(s.copyWith(champSeasons: v)),
          ),
          const SizedBox(height: 12),
          _SeasonSlider(
            title: 'ITEMS · IN THE SHOP',
            bounds: range.items,
            value: s.itemSeasons,
            enabled: s.useItems,
            onChanged: (v) => setState(() => _draft = s.copyWith(itemSeasons: v)),
            onChangeEnd: (v) => _commit(s.copyWith(itemSeasons: v)),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'ITEM TIERS',
          style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tier in ItemTier.all)
              _TierChip(
                label: ItemTier.label(tier),
                selected: s.itemTiers.contains(tier),
                enabled: s.useItems,
                onChanged: (on) {
                  final tiers = {...s.itemTiers};
                  if (on) {
                    tiers.add(tier);
                  } else {
                    tiers.remove(tier);
                  }
                  _commit(s.copyWith(itemTiers: tiers));
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        PoolSizeLine(settings: s, poolSize: widget.poolSize),
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
    final labelColor = enabled ? hextech.textSecondary : hextech.textDisabled;

    final lo = value.$1.clamp(min, max).toDouble();
    final hi = value.$2.clamp(min, max).toDouble();
    final summary = lo == hi ? 'S${lo.toInt()}' : 'S${lo.toInt()} – S${hi.toInt()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: textTheme.labelSmall?.copyWith(color: labelColor, letterSpacing: 2),
              ),
            ),
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

class _TierChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _TierChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final on = selected && enabled;
    final foreground = on
        ? HextechColors.abyss
        : enabled
            ? hextech.accent
            : hextech.textDisabled;

    return FilterChip(
      label: Text(label.toUpperCase()),
      selected: on,
      showCheckmark: false,
      backgroundColor: hextech.panel,
      selectedColor: hextech.accent,
      disabledColor: hextech.panel,
      side: BorderSide(color: on ? hextech.accent : hextech.panelBorder),
      labelStyle: textTheme.labelSmall?.copyWith(color: foreground),
      visualDensity: VisualDensity.compact,
      onSelected: enabled ? onChanged : null,
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

    TextSpan part(int n, String noun) => TextSpan(
          text: '$n $noun${n == 1 ? '' : 's'}',
          style: textTheme.bodyMedium?.copyWith(
            color: n == 0 ? HextechColors.dangerBright : hextech.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        );
    final parts = <TextSpan>[
      if (settings.useChampions) part(size.champions, 'champion'),
      if (settings.useItems) part(size.items, 'item'),
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
    final parts = <String>[
      if (s.useChampions) 'Champions ${range(s.champSeasons)}',
      if (s.useItems)
        'Items ${range(s.itemSeasons)}'
            '${s.itemTiers.length == ItemTier.all.length ? '' : ' (${s.itemTiers.length} of ${ItemTier.all.length} tiers)'}',
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
        Text(
          'GAME POOLS',
          style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        Text(describe(settings), style: textTheme.bodyMedium?.copyWith(color: hextech.textPrimary)),
        const SizedBox(height: 6),
        PoolSizeLine(settings: settings, poolSize: poolSize),
      ],
    );
  }
}
