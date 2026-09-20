import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Which word pools the host wants the game drawn from.
///
/// At least one pool has to stay on — with both off there would be nothing to
/// draw — so instead of quietly disabling the last chip (which reads as a bug)
/// the tap is refused: the chip shakes and the rule is spelled out underneath.
class LobbyPoolToggles extends StatefulWidget {
  final bool useChampions;
  final bool useItems;

  /// Called with the new pair whenever a tap is actually allowed.
  final void Function(bool useChampions, bool useItems) onChanged;

  const LobbyPoolToggles({
    super.key,
    required this.useChampions,
    required this.useItems,
    required this.onChanged,
  });

  @override
  State<LobbyPoolToggles> createState() => _LobbyPoolTogglesState();
}

enum _Pool { champions, items }

class _LobbyPoolTogglesState extends State<LobbyPoolToggles> {
  /// Bumped on every refusal so the shake replays rather than being reused.
  int _refusals = 0;
  _Pool? _refused;
  bool _showRule = false;

  void _toggle(_Pool pool) {
    final champions = pool == _Pool.champions ? !widget.useChampions : widget.useChampions;
    final items = pool == _Pool.items ? !widget.useItems : widget.useItems;

    if (!champions && !items) {
      setState(() {
        _refused = pool;
        _refusals++;
        _showRule = true;
      });
      return;
    }

    setState(() {
      _refused = null;
      if (champions && items) _showRule = false;
    });
    widget.onChanged(champions, items);
  }

  Widget _chip(_Pool pool, String label, IconData icon, bool selected) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final foreground = selected ? HextechColors.abyss : hextech.accent;

    Widget chip = FilterChip(
      label: Text(label.toUpperCase()),
      avatar: Icon(icon, size: 16, color: foreground),
      selected: selected,
      showCheckmark: false,
      backgroundColor: hextech.panel,
      selectedColor: hextech.accent,
      side: BorderSide(color: selected ? hextech.accent : hextech.panelBorder),
      labelStyle: textTheme.labelMedium?.copyWith(color: foreground),
      onSelected: (_) => _toggle(pool),
    );

    if (_refused == pool && !Motion.reduced(context)) {
      chip = chip
          .animate(key: ValueKey('refused-$pool-$_refusals'))
          .shakeX(duration: 400.ms, hz: 6, amount: 3);
    }
    return chip;
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _chip(_Pool.champions, 'Champions', Icons.shield_outlined, widget.useChampions),
            _chip(_Pool.items, 'Items', Icons.inventory_2_outlined, widget.useItems),
          ],
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.enter,
          alignment: Alignment.topLeft,
          child: _showRule
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'At least one pool must stay on',
                    style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
