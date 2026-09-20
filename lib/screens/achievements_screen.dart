import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/achievements.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/achievement_badge.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/phase_switcher.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

enum AchievementsView { byPlayer, allTitles }

/// The titles earned in this lobby, live: per player, or the whole table
/// with what has been unlocked so far.
class AchievementsScreen extends StatefulWidget {
  final String playerName;

  const AchievementsScreen({super.key, required this.playerName});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final LobbyService _lobbyService = LobbyService();
  AchievementsView _view = AchievementsView.byPlayer;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lobby?>(
      stream: _lobbyService.lobbyStream(),
      initialData: _lobbyService.currentLobby,
      builder: (context, snapshot) {
        final lobby = snapshot.data;
        return HextechScaffold(
          title: 'Achievements',
          subtitle: lobby == null ? null : 'Lobby ${lobby.id} · ${_earnedCount(lobby)} of ${Achievements.all.length} titles unlocked',
          onLeading: () => Navigator.of(context).maybePop(),
          body: lobby == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: StatusNotice(message: 'The lobby is closed.', tone: NoticeTone.warning),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        children: [
                          for (final view in AchievementsView.values) ...[
                            HextechChip(
                              label: switch (view) {
                                AchievementsView.byPlayer => 'By player',
                                AchievementsView.allTitles => 'All titles',
                              },
                              icon: switch (view) {
                                AchievementsView.byPlayer => Icons.people_outline,
                                AchievementsView.allTitles => Icons.emoji_events_outlined,
                              },
                              selected: _view == view,
                              onSelected: (_) => setState(() => _view = view),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: PhaseSwitcher(
                        phaseKey: _view,
                        child: switch (_view) {
                          AchievementsView.byPlayer => _ByPlayer(lobby: lobby, playerName: widget.playerName),
                          AchievementsView.allTitles => _AllTitles(lobby: lobby),
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  static int _earnedCount(Lobby lobby) => {for (final ids in lobby.achievements.values) ...ids}.length;
}

/// Every seat (and every past player with a title), each a fold-out list
/// of what they earned. The viewer's own panel starts open.
class _ByPlayer extends StatelessWidget {
  final Lobby lobby;
  final String playerName;

  const _ByPlayer({required this.lobby, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final names = [
      ...lobby.players,
      ...lobby.achievements.keys.where((n) => !lobby.players.contains(n)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (var i = 0; i < names.length; i++) ...[
          _stagger(
            context,
            i,
            _PlayerPanel(
              key: ValueKey(names[i]),
              name: names[i],
              ids: lobby.achievements[names[i]] ?? const [],
              isHost: names[i] == lobby.host,
              isYou: names[i] == playerName,
              left: !lobby.players.contains(names[i]),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (names.isEmpty)
          Text(
            'Nobody here yet.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
          ),
      ],
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  final String name;
  final List<String> ids;
  final bool isHost;
  final bool isYou;
  final bool left;

  const _PlayerPanel({
    super.key,
    required this.name,
    required this.ids,
    required this.isHost,
    required this.isYou,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final count = ids.length;
    final subtitle = [
      count == 0 ? 'No titles yet' : '$count title${count == 1 ? '' : 's'}',
      if (isYou) 'you',
      if (left) 'left the lobby',
    ].join(' · ');

    return HextechExpander(
      title: name,
      subtitle: subtitle,
      accent: isYou,
      initiallyExpanded: isYou,
      leading: _PlayerMark(name: name, isHost: isHost, isYou: isYou, dimmed: left),
      child: count == 0
          ? Text(
              'Win as an impostor, guess the word with your last breath or keep your votes sharp to earn a title.',
              style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final id in ids) _TitleLine(achievement: Achievements.byId(id), earned: true),
              ],
            ),
    );
  }
}

/// The player's initials ring, host gold or viewer blue like [PlayerTile].
class _PlayerMark extends StatelessWidget {
  final String name;
  final bool isHost;
  final bool isYou;
  final bool dimmed;

  const _PlayerMark({required this.name, required this.isHost, required this.isYou, required this.dimmed});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final ring = isHost
        ? hextech.accent
        : isYou
            ? hextech.accentGlow
            : hextech.panelBorder;

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HextechColors.navyLight,
              border: Border.all(color: ring, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: textTheme.labelMedium?.copyWith(
                color: dimmed ? hextech.textDisabled : hextech.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (isHost)
            Positioned(
              top: -4,
              child: Icon(Icons.workspace_premium, size: 16, color: hextech.accent),
            ),
        ],
      ),
    );
  }
}

/// The full table: lit where somebody in the lobby has earned it, locked
/// otherwise, with the names under each one.
class _AllTitles extends StatelessWidget {
  final Lobby lobby;

  const _AllTitles({required this.lobby});

  @override
  Widget build(BuildContext context) {
    final holders = <String, List<String>>{};
    for (final entry in lobby.achievements.entries) {
      for (final id in entry.value) {
        (holders[id] ??= []).add(entry.key);
      }
    }
    for (final names in holders.values) {
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    // Ids the server awards that this build has no words for yet still get a line.
    final unknown = holders.keys.where((id) => Achievements.all.every((a) => a.id != id)).toList()..sort();
    final table = [...Achievements.all, for (final id in unknown) Achievements.byId(id)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        for (var i = 0; i < table.length; i++) ...[
          _stagger(
            context,
            i,
            HextechPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _TitleLine(
                achievement: table[i],
                earned: holders.containsKey(table[i].id),
                holders: holders[table[i].id] ?? const [],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Badge, title and description; in the full table also who holds it.
class _TitleLine extends StatelessWidget {
  final Achievement achievement;
  final bool earned;
  final List<String>? holders;

  const _TitleLine({required this.achievement, required this.earned, this.holders});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AchievementBadge(id: achievement.id, earned: earned),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  achievement.title,
                  style: textTheme.titleSmall?.copyWith(color: earned ? hextech.accent : hextech.textDisabled),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: textTheme.bodySmall?.copyWith(color: earned ? hextech.textPrimary : hextech.textSecondary),
                ),
                if (holders != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    holders!.isEmpty ? 'Not yet earned' : 'Earned by ${holders!.join(', ')}',
                    style: textTheme.labelSmall?.copyWith(
                      color: earned ? hextech.accentGlow : hextech.textDisabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrance stagger for list rows, off under reduced motion.
Widget _stagger(BuildContext context, int index, Widget child) {
  if (Motion.reduced(context)) return child;
  return child
      .animate()
      .fadeIn(duration: Motion.base, delay: Duration(milliseconds: index * 40), curve: Motion.enter)
      .slideY(begin: 0.04, end: 0, duration: Motion.base, curve: Motion.enter);
}
