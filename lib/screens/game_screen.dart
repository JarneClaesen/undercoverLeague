import 'dart:async';

import 'package:flutter/material.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/eliminated_view.dart';
import 'package:undercoverleague/screens/game_over_view.dart';
import 'package:undercoverleague/screens/last_guess_screen.dart';
import 'package:undercoverleague/screens/player_role_screen.dart';
import 'package:undercoverleague/screens/round_screen.dart';
import 'package:undercoverleague/screens/vote_result_view.dart';
import 'package:undercoverleague/screens/voting_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/hextech_dialog.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/phase_switcher.dart';
import 'package:undercoverleague/widgets/reaction_overlay.dart';
import 'package:undercoverleague/widgets/reveal_card.dart';
import 'package:undercoverleague/widgets/rules_info.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';

/// The shell the whole game runs inside: it owns the lobby stream and picks
/// which phase body to show. Each phase is its own widget so this file only
/// ever answers "what is happening now", never "how does it look".
class GameScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;

  /// Who hosted when the game opened. Only the first guess: the live view's
  /// `host` wins as soon as it arrives, since "play again" can pass the seat.
  final String hostName;

  const GameScreen({super.key, required this.lobbyId, required this.playerName, required this.hostName});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// Which body the shell is showing. Also the [PhaseSwitcher] key, so a change
/// of phase cross-fades while a new snapshot inside one phase does not.
enum _Phase {
  loading,
  closed,
  ending,
  reveal,
  round,
  voting,
  voteResult,
  eliminated,
  spectator,
  lastGuess,
  guessWaiting,
  gameOver,
  waiting,
}

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

  /// The last guess as it stood when the tally was spotted, so a guess that
  /// lands afterwards can be told apart from one left over from an earlier
  /// round; and the last one seen at all, to notice a new one arriving.
  LastGuess? _guessAtTally;
  LastGuess? _seenGuess;
  bool _seenSnapshot = false;

  bool _isHostOf(Lobby? lobby) =>
      lobby == null ? widget.playerName == widget.hostName : lobby.host == widget.playerName;

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
  /// voting to describing, to a last guess or straight to game over with a
  /// ballot attached. A last guess that lands while the game goes on brings
  /// the tally back with the verdict on it, since that is what decided
  /// whether the elimination stuck; a correct guess ends the game and is
  /// told there instead. Runs inside build, so it only mutates fields; the
  /// timer does the setState.
  void _trackVoteResult(Lobby? lobby) {
    if (lobby == null || !lobby.gameStarted) {
      _wasVoting = null;
      _seenSnapshot = false;
      _seenGuess = null;
      if (_showingVoteResult) _dismissVoteResult(rebuild: false);
      return;
    }
    final voting = lobby.gamePhase == GamePhase.playing && lobby.roundFinished;
    final tallied = _wasVoting == true && !voting && lobby.lastVotes.isNotEmpty;
    _wasVoting = voting;

    final guessLanded = _seenSnapshot && lobby.lastGuess != null && lobby.lastGuess != _seenGuess;
    _seenSnapshot = true;
    _seenGuess = lobby.lastGuess;

    if (tallied) {
      _guessAtTally = lobby.lastGuess;
      _showVoteResult();
    } else if (guessLanded && !lobby.isGameOver) {
      _showVoteResult();
    }
  }

  void _showVoteResult() {
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

  /// The last guess, when it came after the ballot on show.
  ({String player, String word, bool correct})? _guessSince(Lobby lobby) {
    final guess = lobby.lastGuess;
    if (guess == null || guess == _guessAtTally) return null;
    return (player: guess.player, word: guess.word, correct: guess.correct);
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
        if (!didPop && _isHostOf(_lobbyService.currentLobby)) _showEndGameConfirmationDialog();
      },
      child: StreamBuilder<Lobby?>(
        stream: _lobbyService.lobbyStream(),
        initialData: _lobbyService.currentLobby,
        builder: (context, snapshot) {
          final lobby = snapshot.data;
          _trackVoteResult(lobby);
          final phase = _phaseOf(lobby, snapshot.connectionState);
          final isHost = _isHostOf(lobby);

          // The lobby has to go home exactly once, and only while a real
          // snapshot says the game is over.
          if (phase == _Phase.ending) _returnToLobby();

          return HextechScaffold(
            title: 'Undercover',
            subtitle: widget.lobbyId,
            actions: [
              if (lobby != null)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  color: context.hextech.accent,
                  onPressed: () => showRulesInfo(context, lobby.settings),
                  tooltip: rulesInfoTitle,
                ),
              if (isHost)
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: HextechColors.danger,
                  onPressed: _showEndGameConfirmationDialog,
                  tooltip: 'End game',
                ),
            ],
            footer: _footer(phase, lobby),
            body: Stack(
              fit: StackFit.expand,
              children: [
                PhaseSwitcher(
                  phaseKey: phase,
                  child: _body(phase, lobby, isHost),
                ),
                // Mounted once, over every phase, so a reaction thrown during
                // the vote is still rising when the tally comes up.
                const Positioned.fill(child: ReactionOverlay()),
              ],
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
    if (lobby.gamePhase == GamePhase.revealingRoles) return _Phase.reveal;

    // Whoever sat this game out watches it from the bench, the host included;
    // the End game action in the header stays with the host either way.
    if (lobby.myRole == Role.spectator || lobby.isSpectator(widget.playerName)) return _Phase.spectator;

    // The guesser has just been voted out, so this comes before the
    // eliminated check.
    if (lobby.isLastGuess && lobby.guesser == widget.playerName) return _Phase.lastGuess;
    if (!lobby.alivePlayers.contains(widget.playerName)) return _Phase.eliminated;
    if (lobby.isLastGuess) return _Phase.guessWaiting;

    if (lobby.gamePhase == GamePhase.playing) {
      return lobby.roundFinished ? _Phase.voting : _Phase.round;
    }
    return _Phase.waiting;
  }

  /// The peek card, docked under the body while a round is being played, so
  /// anybody can re-check their word without leaving the phase they are in.
  /// The card knows every face: a decoy reads as the Undercover's own word,
  /// Mr. White gets his own, and a wordless Undercover an empty one.
  Widget? _footer(_Phase phase, Lobby? lobby) {
    if (lobby == null) return null;
    if (phase != _Phase.round && phase != _Phase.voting && phase != _Phase.guessWaiting) return null;
    return RevealCard(
      role: lobby.myRole,
      word: lobby.myWord ?? '',
      icon: lobby.myIcon,
      isChampion: lobby.selectedIsChampion,
      pack: lobby.selectedPack,
      size: RevealCardSize.compact,
    );
  }

  Widget _body(_Phase phase, Lobby? lobby, bool isHost) {
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
        final guess = lobby!.lastGuess;
        return GameOverView(
          lobby: lobby,
          playerName: widget.playerName,
          isHost: isHost,
          onBackToLobby: _lobbyService.resetGame,
          onPlayAgain: isHost ? _lobbyService.playAgain : null,
          winReason: lobby.winReason,
          decoyWord: lobby.decoyWord,
          lastGuess: guess == null ? null : (player: guess.player, word: guess.word, correct: guess.correct),
        );

      case _Phase.reveal:
        return PlayerRoleScreen(
          playerName: widget.playerName,
          role: lobby!.myRole,
          word: lobby.myWord ?? lobby.selectedWord ?? '',
          icon: lobby.myIcon,
          isChampion: lobby.selectedIsChampion,
          pack: lobby.selectedPack,
          rolesAcknowledged: lobby.rolesAcknowledged,
          settings: lobby.settings,
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
          lastGuess: _guessSince(lobby),
          onDone: _dismissVoteResult,
        );

      case _Phase.eliminated:
        return EliminatedView(lobby: lobby!, playerName: widget.playerName);

      case _Phase.spectator:
        return EliminatedView(lobby: lobby!, playerName: widget.playerName, spectator: true);

      case _Phase.lastGuess:
        return LastGuessScreen(
          playerName: widget.playerName,
          role: lobby!.myRole,
          pack: lobby.selectedPack,
          deadline: lobby.deadline,
          clues: lobby.settings.clueLog ? lobby.clues : const [],
        );

      case _Phase.guessWaiting:
        return _GuessWaitingBody(lobby: lobby!, playerName: widget.playerName);

      case _Phase.round:
        return RoundScreen(
          currentPlayer: lobby!.currentPlayer,
          currentPlayerIndex: lobby.currentPlayerIndex,
          isCurrentPlayer: lobby.currentPlayer == widget.playerName,
          roundOrder: lobby.roundOrder,
          playerName: widget.playerName,
          lastEliminated: lobby.lastEliminated,
          round: lobby.round,
          deadline: lobby.deadline,
          clueLog: lobby.settings.clueLog,
          clues: lobby.clues,
        );

      case _Phase.voting:
        return VotingScreen(
          alivePlayers: lobby!.alivePlayers,
          votes: lobby.votes,
          playerName: widget.playerName,
          round: lobby.round,
          deadline: lobby.deadline,
          clueLog: lobby.settings.clueLog,
          clues: lobby.clues,
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

/// What everyone still at the table sees while the player they just voted
/// out takes their last guess: who is guessing, how long they have, and the
/// clues they have to go on.
class _GuessWaitingBody extends StatelessWidget {
  final Lobby lobby;
  final String playerName;

  const _GuessWaitingBody({required this.lobby, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final guesser = lobby.guesser.isEmpty ? 'The eliminated player' : lobby.guesser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhaseHeader(
            eyebrow: 'Last guess',
            title: '$guesser was caught',
            subtitle: 'They had no word. One guess at it: right, and they steal the game.',
            tone: PhaseTone.danger,
            trailing: TurnTimer(deadline: lobby.deadline),
          ),
          const SizedBox(height: 20),
          StatusNotice(
            message: 'Waiting for $guesser to guess…',
            tone: NoticeTone.warning,
            pulse: true,
          ),
          if (lobby.settings.clueLog) ...[
            const SizedBox(height: 16),
            ClueLog(clues: lobby.clues, you: playerName),
          ],
        ],
      ),
    );
  }
}
