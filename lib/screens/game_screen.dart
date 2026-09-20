import 'dart:async';

import 'package:flutter/material.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/eliminated_view.dart';
import 'package:undercoverleague/screens/game_over_view.dart';
import 'package:undercoverleague/screens/player_role_screen.dart';
import 'package:undercoverleague/screens/round_screen.dart';
import 'package:undercoverleague/screens/vote_result_view.dart';
import 'package:undercoverleague/screens/voting_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/hextech_dialog.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/phase_switcher.dart';
import 'package:undercoverleague/widgets/reveal_card.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

/// The shell the whole game runs inside: it owns the lobby stream and picks
/// which phase body to show. Each phase is its own widget so this file only
/// ever answers "what is happening now", never "how does it look".
class GameScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;
  final String hostName;

  const GameScreen({super.key, required this.lobbyId, required this.playerName, required this.hostName});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Which body the shell is showing. Also the [PhaseSwitcher] key, so a change
/// of phase cross-fades while a new snapshot inside one phase does not.
enum _Phase { loading, closed, ending, reveal, round, voting, voteResult, eliminated, gameOver, waiting }

/// How long the vote-result interstitial stays up unless the player taps it away.
const _voteResultDuration = Duration(seconds: 5);

class _GameScreenState extends State<GameScreen> {
  final LobbyService _lobbyService = LobbyService();
  StreamSubscription<GameError>? _errors;
  bool _isReturningToLobby = false;

  /// The tally is only observable as the transition voting -> not voting, so
  /// the previous snapshot's [Lobby.roundFinished] is remembered to spot it.
  bool? _wasVoting;
  bool _showingVoteResult = false;
  Timer? _voteResultTimer;

  bool get _isHost => widget.playerName == widget.hostName;

  @override
  void initState() {
    super.initState();
    // Actions the server refused (e.g. a tap that arrived after the turn
    // moved on) are worth a small notice; the view itself is already right.
    _errors = GameConnection.instance.errors.listen((e) {
      if (mounted) showHextechSnack(context, e.message, tone: SnackTone.warning);
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    _voteResultTimer?.cancel();
    super.dispose();
  }

  /// Shows the tally once per finished vote: when a snapshot flips from
  /// voting to describing (or straight to game over) with a ballot attached.
  /// Runs inside build, so it only mutates fields; the timer does the setState.
  void _trackVoteResult(Lobby? lobby) {
    if (lobby == null || !lobby.gameStarted) {
      _wasVoting = null;
      if (_showingVoteResult) _dismissVoteResult(rebuild: false);
      return;
    }
    final voting = lobby.gamePhase == 'playing' && lobby.roundFinished;
    final tallied = _wasVoting == true && !voting && lobby.lastVotes.isNotEmpty;
    _wasVoting = voting;
    if (!tallied || _showingVoteResult) return;
    _showingVoteResult = true;
    _voteResultTimer?.cancel();
    _voteResultTimer = Timer(_voteResultDuration, _dismissVoteResult);
  }

  void _dismissVoteResult({bool rebuild = true}) {
    _voteResultTimer?.cancel();
    _voteResultTimer = null;
    if (!_showingVoteResult) return;
    _showingVoteResult = false;
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _showEndGameConfirmationDialog() async {
    final confirmed = await showHextechDialog(
      context,
      title: 'End game',
      message: 'Are you sure you want to end the game and return to the lobby?',
      confirmLabel: 'End game',
      danger: true,
    );
    if (confirmed) _lobbyService.resetGame();
  }

  /// Pops back to the lobby exactly once, however many snapshots arrive.
  void _returnToLobby() {
    if (_isReturningToLobby) return;
    _isReturningToLobby = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isHost) _showEndGameConfirmationDialog();
      },
      child: StreamBuilder<Lobby?>(
        stream: _lobbyService.lobbyStream(),
        initialData: _lobbyService.currentLobby,
        builder: (context, snapshot) {
          final lobby = snapshot.data;
          _trackVoteResult(lobby);
          final phase = _phaseOf(lobby, snapshot.connectionState);

          // The lobby has to go home exactly once, and only while a real
          // snapshot says the game is over.
          if (phase == _Phase.ending) _returnToLobby();

          return HextechScaffold(
            title: 'Undercover',
            subtitle: widget.lobbyId,
            actions: [
              if (_isHost)
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: HextechColors.danger,
                  onPressed: _showEndGameConfirmationDialog,
                  tooltip: 'End game',
                ),
            ],
            footer: _footer(phase, lobby),
            body: PhaseSwitcher(
              phaseKey: phase,
              child: _body(phase, lobby),
            ),
          );
        },
      ),
    );
  }

  _Phase _phaseOf(Lobby? lobby, ConnectionState connectionState) {
    if (lobby == null) {
      return connectionState == ConnectionState.waiting ? _Phase.loading : _Phase.closed;
    }
    if (!lobby.gameStarted) return _Phase.ending;
    // The tally is shown to everyone, including whoever it just eliminated,
    // before the next phase (or the game-over screen) takes over.
    if (_showingVoteResult) return _Phase.voteResult;
    if (lobby.isGameOver) return _Phase.gameOver;
    if (lobby.gamePhase == 'revealingRoles') return _Phase.reveal;

    // Eliminated players spectate; the host keeps the full view so they can
    // still end the game.
    if (!lobby.alivePlayers.contains(widget.playerName) && !_isHost) return _Phase.eliminated;

    if (lobby.gamePhase == 'playing') {
      return lobby.roundFinished ? _Phase.voting : _Phase.round;
    }
    return _Phase.waiting;
  }

  /// The peek card, docked under the body while a round is being played, so
  /// anybody can re-check their word without leaving the phase they are in.
  Widget? _footer(_Phase phase, Lobby? lobby) {
    if (lobby == null) return null;
    if (phase != _Phase.round && phase != _Phase.voting) return null;
    return RevealCard(
      role: lobby.myRole,
      word: lobby.myWord ?? lobby.selectedWord ?? '',
      icon: lobby.myIcon,
      isChampion: lobby.selectedIsChampion,
      size: RevealCardSize.compact,
    );
  }

  Widget _body(_Phase phase, Lobby? lobby) {
    switch (phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());

      case _Phase.closed:
        // Lobby closed or session lost; the LobbyScreen underneath navigates home.
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: StatusNotice(message: 'Lobby has been closed.', tone: NoticeTone.danger),
          ),
        );

      case _Phase.ending:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusNotice(
                  message: 'Game ended. Returning to the lobby…',
                  tone: NoticeTone.warning,
                  pulse: true,
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        );

      case _Phase.gameOver:
        return GameOverView(
          lobby: lobby!,
          playerName: widget.playerName,
          isHost: _isHost,
          onBackToLobby: _lobbyService.resetGame,
        );

      case _Phase.reveal:
        return PlayerRoleScreen(
          playerName: widget.playerName,
          role: lobby!.myRole,
          word: lobby.myWord ?? lobby.selectedWord ?? '',
          icon: lobby.myIcon,
          isChampion: lobby.selectedIsChampion,
          rolesAcknowledged: lobby.rolesAcknowledged,
        );

      case _Phase.voteResult:
        final eliminated = lobby!.lastEliminated;
        final candidates = [
          ...lobby.alivePlayers,
          if (eliminated != null && eliminated.isNotEmpty && !lobby.alivePlayers.contains(eliminated)) eliminated,
        ];
        return VoteResultView(
          lastVotes: lobby.lastVotes,
          candidates: candidates,
          eliminated: eliminated,
          you: widget.playerName,
          onDone: _dismissVoteResult,
        );

      case _Phase.eliminated:
        return EliminatedView(lobby: lobby!, playerName: widget.playerName);

      case _Phase.round:
        return RoundScreen(
          currentPlayer: lobby!.currentPlayer,
          currentPlayerIndex: lobby.currentPlayerIndex,
          isCurrentPlayer: lobby.currentPlayer == widget.playerName,
          roundOrder: lobby.roundOrder,
          playerName: widget.playerName,
          lastEliminated: lobby.lastEliminated,
        );

      case _Phase.voting:
        return VotingScreen(
          alivePlayers: lobby!.alivePlayers,
          votes: lobby.votes,
          playerName: widget.playerName,
        );

      case _Phase.waiting:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: StatusNotice(
              message: 'Waiting for the game to start…',
              tone: NoticeTone.warning,
              pulse: true,
            ),
          ),
        );
    }
  }
}
