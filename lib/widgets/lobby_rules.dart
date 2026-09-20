import 'package:flutter/material.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

/// How many impostors (Undercovers + Mr. Whites) a game of [activePlayers]
/// can hold: the server requires `2 * impostors < players`. Never below 1,
/// so the steppers keep working while seats are still filling up.
int maxImpostorsFor(int activePlayers) {
  final n = (activePlayers - 1) ~/ 2;
  return n < 1 ? 1 : n;
}

/// The host's rules: how many impostors of each kind, decoy words, turn
/// order, the timer, the clue log and host rotation. Every change goes out
/// through [onChanged] at once; the screen debounces the network.
class LobbyRules extends StatelessWidget {
  final GameSettings settings;

  /// Non-spectator players, which bounds the impostor steppers.
  final int activePlayers;
  final ValueChanged<GameSettings> onChanged;

  const LobbyRules({
    super.key,
    required this.settings,
    required this.activePlayers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final s = settings;
    final maxImpostors = maxImpostorsFor(activePlayers);
    final mixed = s.mrWhites > 0;
    final maxUndercovers = (maxImpostors - s.mrWhites).clamp(1, maxImpostors);
    final maxMrWhites = (maxImpostors - s.undercovers).clamp(mixed ? 1 : 0, maxImpostors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const HextechSectionLabel('Rules'),
        const SizedBox(height: 12),
        _Stepper(
          title: 'Undercovers',
          subtitle: 'Up to $maxImpostors impostor${maxImpostors == 1 ? '' : 's'} with $activePlayers player${activePlayers == 1 ? '' : 's'}',
          value: s.undercovers,
          min: 1,
          max: maxUndercovers,
          onChanged: (v) => onChanged(s.copyWith(undercovers: v)),
        ),
        const SizedBox(height: 8),
        _RuleSwitch(
          title: 'Decoy word',
          subtitle: 'Undercovers get a related word instead of nothing',
          value: s.decoyWord,
          // Mixed mode needs decoys, so the switch is locked while it is on.
          onChanged: mixed ? null : (v) => onChanged(s.copyWith(decoyWord: v)),
        ),
        _RuleSwitch(
          title: 'Mixed mode (Mr. White)',
          subtitle: 'Adds players who get no word at all; turns decoys on',
          value: mixed,
          onChanged: maxImpostors - s.undercovers < 1 && !mixed
              ? null
              : (v) => onChanged(v ? s.copyWith(mrWhites: 1, decoyWord: true) : s.copyWith(mrWhites: 0)),
        ),
        MotionSize(
          child: mixed
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: _Stepper(
                    title: 'Mr. Whites',
                    subtitle: 'Nobody knows who they are, not even each other',
                    value: s.mrWhites,
                    min: 1,
                    max: maxMrWhites,
                    onChanged: (v) => onChanged(s.copyWith(mrWhites: v)),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        _RuleSwitch(
          title: 'Random turn order',
          subtitle: 'Off keeps the order and rotates the first speaker',
          value: s.randomOrder,
          onChanged: (v) => onChanged(s.copyWith(randomOrder: v)),
        ),
        const SizedBox(height: 8),
        Text('Turn timer', style: textTheme.bodyLarge?.copyWith(color: hextech.textPrimary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in turnTimerChoices)
              HextechChip(
                label: seconds == 0 ? 'Off' : '$seconds s',
                dense: true,
                selected: s.turnSeconds == seconds,
                onSelected: (_) => onChanged(s.copyWith(turnSeconds: seconds)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _RuleSwitch(
          title: 'Clue log',
          subtitle: 'Turns end by typing a clue everyone can read back',
          value: s.clueLog,
          onChanged: (v) => onChanged(s.copyWith(clueLog: v)),
        ),
        _RuleSwitch(
          title: 'Rotate host after each game',
          subtitle: '"Play again" passes the host seat to the next player',
          value: s.rotateHost,
          onChanged: (v) => onChanged(s.copyWith(rotateHost: v)),
        ),
      ],
    );
  }
}

/// The rules in one paragraph, for everyone who is not the host.
class LobbyRulesSummary extends StatelessWidget {
  final GameSettings settings;

  const LobbyRulesSummary({super.key, required this.settings});

  static String describe(GameSettings s) {
    final parts = <String>[
      '${s.undercovers} Undercover${s.undercovers == 1 ? '' : 's'}',
      if (s.mrWhites > 0) '${s.mrWhites} Mr. White${s.mrWhites == 1 ? '' : 's'}',
      s.decoyWord ? 'decoy words' : 'no decoy word',
      s.randomOrder ? 'random turn order' : 'fixed turn order',
      s.turnSeconds == 0 ? 'no timer' : '${s.turnSeconds} s per turn',
      if (s.clueLog) 'clue log',
      if (s.rotateHost) 'host rotates',
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
        const HextechSectionLabel('Rules'),
        const SizedBox(height: 8),
        Text(describe(settings), style: textTheme.bodyMedium?.copyWith(color: hextech.textPrimary)),
      ],
    );
  }
}

class _RuleSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _RuleSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final enabled = onChanged != null;

    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(color: enabled ? hextech.textPrimary : hextech.textDisabled),
                  ),
                  Text(subtitle, style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// "- 1 +" with the title beside it; the buttons dim at the bounds.
class _Stepper extends StatelessWidget {
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
          icon: Icon(icon),
          iconSize: 20,
          color: onPressed == null ? hextech.textDisabled : hextech.accent,
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: textTheme.bodyLarge?.copyWith(color: hextech.textPrimary)),
              Text(subtitle, style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(border: Border.all(color: hextech.panelBorder)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(Icons.remove, 'Fewer $title', value > min ? () => onChanged(value - 1) : null),
              SizedBox(
                width: 28,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(color: HextechColors.goldBright),
                ),
              ),
              button(Icons.add, 'More $title', value < max ? () => onChanged(value + 1) : null),
            ],
          ),
        ),
      ],
    );
  }
}
