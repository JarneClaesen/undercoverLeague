import 'package:flutter/material.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

/// Every clue given this game, grouped by round, newest round open.
///
/// Clues are public the moment they are submitted (the server keeps them in
/// the view for everybody), so the log can be shown wherever a player is
/// weighing who said what: during the round, on the ballot, and while
/// watching from the bench. A clue the timer submitted for somebody is blank
/// and shows as a dash rather than as an empty line.
class ClueLog extends StatefulWidget {
  final List<Clue> clues;

  /// The viewer, whose own clues are picked out.
  final String? you;

  const ClueLog({super.key, required this.clues, this.you});

  /// What a blank clue is written as.
  static const String blank = '—';

  @override
  State<ClueLog> createState() => _ClueLogState();
}

class _ClueLogState extends State<ClueLog> {
  /// Rounds the viewer has flipped away from their default (newest open,
  /// older closed). Cleared whenever a new round starts so the latest one
  /// always opens on its own.
  final Set<int> _toggled = {};
  int _newest = 0;

  @override
  void didUpdateWidget(ClueLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newest = _newestRound(widget.clues);
    if (newest != _newest) {
      _newest = newest;
      _toggled.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    _newest = _newestRound(widget.clues);
  }

  static int _newestRound(List<Clue> clues) => clues.fold(0, (max, c) => c.round > max ? c.round : max);

  bool _isOpen(int round) => (round == _newest) != _toggled.contains(round);

  /// Clues bucketed by round, newest round first, each in the order they
  /// were given.
  List<MapEntry<int, List<Clue>>> _grouped() {
    final byRound = <int, List<Clue>>{};
    for (final clue in widget.clues) {
      byRound.putIfAbsent(clue.round, () => []).add(clue);
    }
    final rounds = byRound.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final r in rounds) MapEntry(r, byRound[r]!)];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final groups = _grouped();

    return HextechPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history_edu_outlined, size: 16, color: hextech.textSecondary),
              const SizedBox(width: 8),
              const HextechSectionLabel('Clue log'),
            ],
          ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'No clues yet. The first one lands when a turn ends.',
                style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
              ),
            ),
          for (final group in groups) ...[
            const SizedBox(height: 10),
            _RoundGroup(
              round: group.key,
              clues: group.value,
              open: _isOpen(group.key),
              you: widget.you,
              onToggle: () => setState(() {
                if (!_toggled.remove(group.key)) _toggled.add(group.key);
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundGroup extends StatelessWidget {
  final int round;
  final List<Clue> clues;
  final bool open;
  final String? you;
  final VoidCallback onToggle;

  const _RoundGroup({
    required this.round,
    required this.clues,
    required this.open,
    required this.you,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    final header = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onToggle,
        splashColor: HextechColors.gold.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ROUND $round',
                  style: textTheme.labelSmall?.copyWith(
                    color: open ? hextech.accent : hextech.textSecondary,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Text(
                '${clues.length}',
                style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: Motion.of(context, Motion.fast),
                curve: Motion.enter,
                child: Icon(Icons.expand_more, size: 18, color: hextech.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );

    final body = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final clue in clues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      clue.player,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: clue.player == you ? hextech.accentGlow : hextech.accent,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      clue.text.trim().isEmpty ? ClueLog.blank : clue.text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: clue.text.trim().isEmpty ? hextech.textDisabled : hextech.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final content = open ? body : const SizedBox(width: double.infinity, height: 0);

    return Semantics(
      container: true,
      label: 'Round $round clues',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          MotionSize(child: content),
        ],
      ),
    );
  }
}
