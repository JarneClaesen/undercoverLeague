import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

/// Which word packs the host wants the game drawn from, one chip per pack
/// with the server's count of what the filters leave in it.
///
/// At least one pack has to stay on — with none there would be nothing to
/// draw — so instead of quietly disabling the last chip (which reads as a
/// bug) the tap is refused: the chip shakes and the rule is spelled out
/// underneath.
class LobbyPoolToggles extends StatefulWidget {
  final Set<String> packs;

  /// Per-pack counts under the current filters; null while unknown.
  final PoolSize? poolSize;

  /// Called with the new set whenever a tap is actually allowed.
  final ValueChanged<Set<String>> onChanged;

  const LobbyPoolToggles({
    super.key,
    required this.packs,
    this.poolSize,
    required this.onChanged,
  });

  @override
  State<LobbyPoolToggles> createState() => _LobbyPoolTogglesState();
}

class _LobbyPoolTogglesState extends State<LobbyPoolToggles> {
  /// Bumped on every refusal so the shake replays rather than being reused.
  int _refusals = 0;
  String? _refused;
  bool _showRule = false;

  void _toggle(String pack) {
    final next = {...widget.packs};
    if (next.contains(pack)) {
      next.remove(pack);
    } else {
      next.add(pack);
    }

    if (next.isEmpty) {
      setState(() {
        _refused = pack;
        _refusals++;
        _showRule = true;
      });
      return;
    }

    setState(() {
      _refused = null;
      if (next.length > 1) _showRule = false;
    });
    widget.onChanged(next);
  }

  Widget _chip(String pack) {
    final selected = widget.packs.contains(pack);
    final count = selected ? widget.poolSize?.perPack[pack] : null;
    Widget chip = HextechChip(
      label: WordPack.label(pack),
      icon: WordPack.icon(pack),
      selected: selected,
      badge: count == null ? null : '· $count',
      onSelected: (_) => _toggle(pack),
    );

    if (_refused == pack && !Motion.reduced(context)) {
      chip = chip
          .animate(key: ValueKey('refused-$pack-$_refusals'))
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
        const HextechSectionLabel('Word packs'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final pack in WordPack.all) _chip(pack)],
        ),
        MotionSize(
          alignment: Alignment.topLeft,
          child: _showRule
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'At least one pack must stay on',
                    style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
