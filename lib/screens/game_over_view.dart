import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/game_over_portrait.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/player_tile.dart';
import 'package:undercoverleague/widgets/role_chip.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

/// The end of a game, disclosed one fact at a time.
///
/// The order is the order the table cares about: did *I* win, what was the
/// word, who was lying, and how did everyone end up. Each step waits for the
/// previous one so the reveal reads as a sequence rather than a wall of
/// results; under reduced motion the whole thing renders at once.
class GameOverView extends StatefulWidget {
  final Lobby lobby;
  final String playerName;
  final bool isHost;
  final VoidCallback onBackToLobby;

  const GameOverView({
    super.key,
    required this.lobby,
    required this.playerName,
    required this.isHost,
    required this.onBackToLobby,
  });

  @override
  State<GameOverView> createState() => _GameOverViewState();
}

class _GameOverViewState extends State<GameOverView> {
  /// The beat each step lands on. Step 1 (the outcome) is immediate.
  static const List<Duration> _beats = [
    Duration.zero,
    Duration(milliseconds: 350),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1050),
    Duration(milliseconds: 1400),
  ];

  static const String _undercover = 'Undercover';
  static const String _civilian = 'Civilian';

  @override
  void initState() {
    super.initState();
    // One heavy tap the moment the result lands. Web and most desktops have
    // no haptics engine; failing there must not take the screen down.
    try {
      HapticFeedback.heavyImpact().catchError((Object _) {});
    } catch (_) {
      // No haptics here.
    }
  }

  Lobby get _lobby => widget.lobby;

  bool get _civiliansWon => _lobby.winner == 'Civilians';

  /// A spectator joined after the deal and has no side; they are shown the
  /// team result rather than a victory or a defeat that is not theirs.
  bool get _isSpectator => _lobby.myRole != _civilian && _lobby.myRole != _undercover;

  bool get _viewerWon =>
      _civiliansWon ? _lobby.myRole != _undercover : _lobby.myRole == _undercover;

  List<String> get _undercoverNames =>
      _lobby.roles.entries.where((e) => e.value == _undercover).map((e) => e.key).toList();

  /// Wraps a step in its entrance. Steps are indexed by [_beats].
  Widget _step(int beat, Widget child) {
    if (Motion.reduced(context)) return child;
    return child
        .animate()
        .fadeIn(duration: Motion.slow, delay: _beats[beat], curve: Motion.enter)
        .slideY(begin: 0.08, end: 0, duration: Motion.slow, delay: _beats[beat], curve: Motion.enter);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _outcome(context),
              const SizedBox(height: 24),
              _step(1, _wordPanel(context)),
              const SizedBox(height: 16),
              _step(2, _undercoverPanel(context)),
              const SizedBox(height: 16),
              _step(3, _rosterPanel(context)),
              const SizedBox(height: 24),
              _step(4, _footer(context)),
            ],
          ),
        ),
      ),
    );
  }

  // 1 — The outcome, from this player's seat.
  Widget _outcome(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    final subtitle = _civiliansWon ? 'Civilians win' : 'The Undercover wins';
    final (String title, Color colour) = _isSpectator
        ? (_civiliansWon ? 'CIVILIANS WIN' : 'UNDERCOVER WINS', hextech.accent)
        : _viewerWon
            ? ('VICTORY', hextech.accent)
            : ('DEFEAT', HextechColors.dangerBright);

    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'GAME OVER',
          textAlign: TextAlign.center,
          style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 3),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.displayMedium?.copyWith(color: colour),
        ),
        const SizedBox(height: 10),
        Text(
          _isSpectator ? 'You were spectating' : subtitle,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: hextech.textSecondary),
        ),
      ],
    );

    if (Motion.reduced(context)) return header;

    return header
        .animate()
        .fadeIn(duration: Motion.reveal, curve: Motion.emphasized)
        .scaleXY(begin: 1.15, end: 1, duration: Motion.reveal, curve: Motion.emphasized);
  }

  // 2 — The word everyone has been circling all game.
  Widget _wordPanel(BuildContext context) {
    final word = _lobby.selectedWord ?? _lobby.myWord ?? '';

    return HextechPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionLabel(label: 'The word was'),
          const SizedBox(height: 16),
          GameOverPortrait(
            icon: _lobby.myIcon,
            word: word,
            isChampion: _lobby.selectedIsChampion,
            delay: _beats[1],
          ),
        ],
      ),
    );
  }

  // 3 — Who was lying.
  Widget _undercoverPanel(BuildContext context) {
    final names = _undercoverNames;

    return HextechPanel(
      tone: PanelTone.danger,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(label: 'The Undercover was', colour: HextechColors.dangerBright),
          const SizedBox(height: 14),
          if (names.isEmpty)
            const StatusNotice(message: 'No Undercover was drawn.', tone: NoticeTone.info)
          else
            for (final (index, name) in names.indexed) ...[
              if (index > 0) const SizedBox(height: 8),
              PlayerTile(
                name: name,
                index: index,
                isHost: name == _lobby.host,
                isYou: name == widget.playerName,
                roleChip: const RoleChip(role: _undercover),
              ),
            ],
        ],
      ),
    );
  }

  // 4 — How the table ended up.
  Widget _rosterPanel(BuildContext context) {
    final players = _lobby.players;

    return HextechPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(label: 'Summoners'),
          const SizedBox(height: 14),
          for (final (index, name) in players.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            PlayerTile(
              name: name,
              index: index,
              isHost: name == _lobby.host,
              isYou: name == widget.playerName,
              connected: _lobby.connected[name] ?? true,
              state: _lobby.alivePlayers.contains(name)
                  ? PlayerState.normal
                  : PlayerState.eliminated,
              roleChip: RoleChip(role: _lobby.roles[name] ?? _civilian),
            ),
          ],
        ],
      ),
    );
  }

  // 5 — What happens next, and who decides it.
  Widget _footer(BuildContext context) {
    if (widget.isHost) {
      return HextechButton(label: 'Back to lobby', onPressed: widget.onBackToLobby);
    }
    return const StatusNotice(
      message: 'Waiting for the host to return to the lobby…',
      tone: NoticeTone.info,
      pulse: true,
    );
  }
}

/// The small uppercase rule that heads each panel.
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color? colour;

  const _SectionLabel({required this.label, this.colour});

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    return Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: colour ?? hextech.accent, letterSpacing: 2.4),
    );
  }
}
