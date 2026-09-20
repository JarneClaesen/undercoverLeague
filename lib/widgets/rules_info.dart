import 'package:flutter/material.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';

/// Section ids a caller can ask [showRulesInfo] to open on.
abstract final class RulesTopic {
  static const roles = 'roles';
  static const decoy = 'decoy';
  static const lastGuess = 'lastGuess';
  static const winning = 'winning';
  static const turns = 'turns';
  static const voting = 'voting';
  static const spectators = 'spectators';
  static const scoring = 'scoring';
}

/// The tooltip and title the info buttons share.
const String rulesInfoTitle = 'How this lobby plays';

/// Opens a Hextech-styled modal that explains how a game under [settings]
/// plays: one folding section per rule, worded for the rules the host has
/// actually picked. The section named by [topic] (a [RulesTopic]) starts
/// open; by default the first one does.
Future<void> showRulesInfo(BuildContext context, GameSettings settings, {String? topic}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: HextechColors.abyss.withValues(alpha: 0.78),
    transitionDuration: Motion.of(context, Motion.base),
    pageBuilder: (dialogContext, _, _) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              type: MaterialType.transparency,
              child: HextechPanel(
                accent: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: RulesInfoContent(
                  settings: settings,
                  topic: topic,
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, _, child) {
      if (Motion.reduced(dialogContext)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// One section of the sheet: a title, a one-line subtitle and the paragraphs
/// under it. Pure data, so the copy can be tested without pumping widgets.
class RulesSection {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> paragraphs;

  const RulesSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.paragraphs,
  });
}

String _count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// The sheet's copy for [s], in display order.
List<RulesSection> rulesSectionsFor(GameSettings s) {
  final mixed = s.mrWhites > 0;
  final undercovers = _count(s.undercovers, 'Undercover');
  final mrWhites = _count(s.mrWhites, 'Mr. White');
  final impostors = mixed ? '$undercovers and $mrWhites' : undercovers;
  final packs = WordPack.all.where(s.packs.contains).map((p) => WordPack.label(p).toLowerCase()).toList();
  final packList = packs.isEmpty
      ? 'the enabled packs'
      : packs.length == 1
          ? packs.single
          : '${packs.sublist(0, packs.length - 1).join(', ')} and ${packs.last}';

  return [
    RulesSection(
      id: RulesTopic.roles,
      title: 'Roles',
      subtitle: mixed ? '$undercovers, $mrWhites, the rest civilians' : '$undercovers, the rest civilians',
      icon: Icons.groups_outlined,
      paragraphs: [
        'Every game hides $impostors among the civilians. Civilians all share the same secret word.',
        if (s.undercovers > 1)
          'Undercovers don\'t know each other, so even they have to sniff out who is on their side.'
        else
          'The Undercover is on their own: nobody at the table knows who they are.',
        if (mixed) 'Nobody knows who Mr. White is — not the civilians, not the Undercovers, not another Mr. White.',
      ],
    ),
    RulesSection(
      id: RulesTopic.decoy,
      title: 'Decoy word',
      subtitle: s.decoyWord ? 'On: Undercovers get a look-alike word' : 'Off: Undercovers get no word',
      icon: s.decoyWord ? Icons.swap_horiz : Icons.visibility_off_outlined,
      paragraphs: s.decoyWord
          ? [
              'Undercovers are told a different but similar word from the same pack, picture and all. Their card is marked UNDERCOVER, so they know their word may not be the real one — but not which one is.',
              'The decoy is picked to feel close: champions get another champion of the same class first; items get something they build from or into, then something of the same tier and a similar price; runes get one from the same tree and slot; abilities get another ability of the same champion; monsters get one from the same group; summoner spells and skin lines get any other one.',
              'The decoy is always something this lobby\'s filters could have drawn from $packList, so it never gives itself away.',
              if (s.undercovers > 1) 'All ${s.undercovers} Undercovers get the same decoy.',
              'At game over both words are revealed, so everyone sees how close it was.',
            ]
          : [
              'Undercovers get no word at all. They have to listen, bluff and blend in with what the civilians say.',
              'If an Undercover is voted out they get a last guess at the word — see Last guess.',
            ],
    ),
    RulesSection(
      id: RulesTopic.lastGuess,
      title: 'Last guess',
      subtitle: 'One shot for a caught player who had no word',
      icon: Icons.lightbulb_outline,
      paragraphs: [
        'A voted-out player who had no word gets one shot at naming the word. Right: they win the game alone. Wrong: the game goes on without them.',
        if (mixed && s.decoyWord)
          'That means Mr. White. Undercovers hold a decoy, so they don\'t get a guess.'
        else if (s.decoyWord)
          'With decoys on, Undercovers hold a word of their own, so nobody gets a guess in this lobby.'
        else
          'With decoys off, that means any Undercover who is voted out.',
      ],
    ),
    RulesSection(
      id: RulesTopic.winning,
      title: 'Winning',
      subtitle: 'Vote out every impostor before they outnumber you',
      icon: Icons.emoji_events_outlined,
      paragraphs: [
        'Civilians win when every impostor is voted out.',
        'Impostors win when they equal or outnumber the civilians still at the table.',
      ],
    ),
    RulesSection(
      id: RulesTopic.turns,
      title: 'Turns & order',
      subtitle: [
        s.randomOrder ? 'Random order' : 'Fixed order',
        s.turnSeconds == 0 ? 'no timer' : '${s.turnSeconds} s per turn',
        if (s.clueLog) 'clue log',
      ].join(' · '),
      icon: Icons.format_list_numbered,
      paragraphs: [
        'Each round everyone alive describes their word in turn, one clue at a time. Say enough for civilians to trust you, not enough for an impostor to catch on.',
        if (s.randomOrder)
          'Random turn order is on: the speaking order is reshuffled every round.'
        else
          'The turn order is fixed: seating stays the same and the first speaker rotates each round, so nobody has to open twice in a row.',
        if (s.turnSeconds > 0)
          'Turn timer: ${s.turnSeconds} s per turn. Voting and the last guess get double, ${s.turnSeconds * 2} s.'
        else
          'No timer: take the time you need.',
        if (s.clueLog)
          'Clue log is on: a turn ends by typing your clue, and everyone can read the log back before voting.'
        else
          'Clues are spoken out loud; a turn ends with a tap.',
      ],
    ),
    RulesSection(
      id: RulesTopic.voting,
      title: 'Voting',
      subtitle: 'Everyone alive votes or skips',
      icon: Icons.how_to_vote_outlined,
      paragraphs: [
        'After a round everyone alive votes for who they think is an impostor, or skips.',
        'The most voted player is out, but only with a clear lead: a tie eliminates nobody, and skips count against the leader, so when skips match or beat their votes nobody goes. Then the next round starts.',
      ],
    ),
    RulesSection(
      id: RulesTopic.spectators,
      title: 'Spectators & reactions',
      subtitle: 'Watch from the bench with the word in hand',
      icon: Icons.visibility_outlined,
      paragraphs: [
        'Sit out in the lobby to watch a game without playing.',
        'Spectators and eliminated players see the word and can send emoji reactions. Players still alive can\'t react — no leaking.',
      ],
    ),
    RulesSection(
      id: RulesTopic.scoring,
      title: 'Scoreboard & titles',
      subtitle: s.rotateHost ? 'Points per game · host rotates' : 'Points per game',
      icon: Icons.leaderboard_outlined,
      paragraphs: [
        'Civilian win: +1 for every civilian, +1 more for voting out an impostor in the deciding ballot.',
        'Impostor win: +3 for a surviving impostor, +1 for an eliminated one.',
        'Correct last guess: +3 for the guesser.',
        'Titles for standout games land on the Achievements page.',
        if (s.rotateHost) 'Host rotation is on: "Play again" passes the host seat to the next player.',
      ],
    ),
  ];
}

/// The sheet's body: title, one [HextechExpander] per section and a close
/// button. Scrolls when the sections outgrow the screen.
class RulesInfoContent extends StatelessWidget {
  final GameSettings settings;
  final String? topic;
  final VoidCallback onClose;

  const RulesInfoContent({
    super.key,
    required this.settings,
    this.topic,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final sections = rulesSectionsFor(settings);
    final open = sections.any((s) => s.id == topic) ? topic : sections.first.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rulesInfoTitle.toUpperCase(),
                style: textTheme.titleLarge?.copyWith(color: hextech.accent),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: hextech.accent,
              tooltip: 'Close',
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a rule to open it.',
          style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final section in sections) ...[
                  HextechExpander(
                    key: ValueKey('rules-${section.id}'),
                    title: section.title,
                    subtitle: section.subtitle,
                    leading: Icon(section.icon, size: 20, color: hextech.accent),
                    initiallyExpanded: section.id == open,
                    accent: section.id == open,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < section.paragraphs.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          Text(
                            section.paragraphs[i],
                            style: textTheme.bodyMedium?.copyWith(color: hextech.textPrimary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        HextechButton(
          label: 'Got it',
          variant: HextechButtonVariant.secondary,
          onPressed: onClose,
        ),
      ],
    );
  }
}
