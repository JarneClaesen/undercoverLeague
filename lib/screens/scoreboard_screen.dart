import 'package:flutter/material.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/score_row.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

/// How points are handed out at game over, in the order the server applies
/// them. Shown in the empty state and under "How scoring works".
const List<String> scoringRules = [
  'Civilians win: every civilian +1, and +1 more for voting an impostor out in the final ballot.',
  'Impostors win by outnumbering: every impostor still standing +3, eliminated impostors +1.',
  'A correct last guess: the guesser +3, and the game ends right there.',
  'Civilians get nothing when they lose.',
];

/// One ranked line of the table, already sorted and ranked.
class ScoreboardEntry {
  final String name;
  final int points;

  /// Competition ranking: equal points share a rank and the next rank skips
  /// ("1, 2, 2, 4").
  final int rank;

  const ScoreboardEntry({required this.name, required this.points, required this.rank});

  @override
  bool operator ==(Object other) =>
      other is ScoreboardEntry && other.name == name && other.points == points && other.rank == rank;

  @override
  int get hashCode => Object.hash(name, points, rank);

  @override
  String toString() => 'ScoreboardEntry($rank. $name: $points)';
}

/// Every name in [scores], highest points first, then by name so ties are
/// stable across updates.
List<ScoreboardEntry> rankScores(Map<String, int> scores) {
  final names = scores.keys.toList()
    ..sort((a, b) {
      final byPoints = (scores[b] ?? 0).compareTo(scores[a] ?? 0);
      if (byPoints != 0) return byPoints;
      final byName = a.toLowerCase().compareTo(b.toLowerCase());
      return byName != 0 ? byName : a.compareTo(b);
    });
  final entries = <ScoreboardEntry>[];
  for (var i = 0; i < names.length; i++) {
    final points = scores[names[i]] ?? 0;
    final rank = i > 0 && entries[i - 1].points == points ? entries[i - 1].rank : i + 1;
    entries.add(ScoreboardEntry(name: names[i], points: points, rank: rank));
  }
  return entries;
}

/// The lobby's running score, live for as long as the page is open.
class ScoreboardScreen extends StatelessWidget {
  final String playerName;

  const ScoreboardScreen({super.key, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final lobbyService = LobbyService();
    return StreamBuilder<Lobby?>(
      stream: lobbyService.lobbyStream(),
      initialData: lobbyService.currentLobby,
      builder: (context, snapshot) {
        final lobby = snapshot.data;
        return HextechScaffold(
          title: 'Scoreboard',
          subtitle: lobby == null ? null : _subtitle(lobby),
          onLeading: () => Navigator.of(context).maybePop(),
          body: lobby == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: StatusNotice(message: 'The lobby is closed.', tone: NoticeTone.warning),
                  ),
                )
              : _ScoreboardBody(lobby: lobby, playerName: playerName),
        );
      },
    );
  }

  static String _subtitle(Lobby lobby) {
    final games = lobby.gamesPlayed;
    return 'Lobby ${lobby.id} · $games game${games == 1 ? '' : 's'} played';
  }
}

class _ScoreboardBody extends StatelessWidget {
  final Lobby lobby;
  final String playerName;

  const _ScoreboardBody({required this.lobby, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final entries = rankScores(lobby.scores);
    final empty = entries.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (empty) ...[
          StatusNotice(
            icon: Icons.leaderboard_outlined,
            message: 'No games played yet. Points are handed out when a game ends:\n'
                '${scoringRules.map((r) => '• $r').join('\n')}',
          ),
        ] else ...[
          for (var i = 0; i < entries.length; i++) ...[
            ScoreRow(
              name: entries[i].name,
              rank: entries[i].rank,
              points: entries[i].points,
              stats: lobby.stats[entries[i].name],
              isHost: entries[i].name == lobby.host,
              isYou: entries[i].name == playerName,
              left: !lobby.players.contains(entries[i].name),
              index: i,
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
        if (empty) const SizedBox(height: 16),
        const _ScoringRules(),
      ],
    );
  }
}

class _ScoringRules extends StatelessWidget {
  const _ScoringRules();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return HextechExpander(
      title: 'How scoring works',
      leading: Icon(Icons.help_outline, color: hextech.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const HextechSectionLabel('At game over'),
          const SizedBox(height: 8),
          for (final rule in scoringRules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Icon(Icons.circle, size: 6, color: hextech.accent),
                  ),
                  Expanded(
                    child: Text(rule, style: textTheme.bodyMedium?.copyWith(color: hextech.textPrimary)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Scores stay with the lobby: leaving keeps your row, closing the lobby clears the table.',
            style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
          ),
        ],
      ),
    );
  }
}
