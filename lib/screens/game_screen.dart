import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/screens/player_role_screen.dart';
import 'package:undercoverleague/screens/round_screen.dart';
import 'package:undercoverleague/screens/voting_screen.dart';

class GameScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;
  final String hostName;

  const GameScreen({
    super.key,
    required this.lobbyId,
    required this.playerName,
    required this.hostName,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isReturningToLobby = false;

  bool get _isHost => widget.playerName == widget.hostName;

  void _showEndGameConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Game'),
          content: const Text('Are you sure you want to end the game and return to the lobby?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('End Game'),
              onPressed: () {
                Navigator.of(context).pop();
                _firebaseService.resetGame(widget.lobbyId);
              },
            ),
          ],
        );
      },
    );
  }

  /// Pops back to the lobby exactly once, however many snapshots arrive.
  void _returnToLobby() {
    if (_isReturningToLobby) return;
    _isReturningToLobby = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Phase transitions are driven by the host only, so a client with a
  /// flaky connection can't replay a stale transition later. The service
  /// methods re-check the state in a transaction, so a duplicate call is
  /// harmless anyway.
  void _hostTransition(Future<void> Function() transition) {
    if (!_isHost) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) transition().catchError((e) => debugPrint('Transition failed: $e'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isHost) _showEndGameConfirmationDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Undercover Game'),
          automaticallyImplyLeading: false,
          actions: [
            if (_isHost)
              IconButton(
                icon: const Icon(Icons.stop),
                onPressed: _showEndGameConfirmationDialog,
                tooltip: 'End Game',
              ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _firebaseService.lobbyStream(widget.lobbyId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('An error occurred. Please try again.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final gameData = snapshot.data!.data();
            if (gameData == null) {
              // Lobby deleted; the LobbyScreen underneath handles navigation.
              return const Center(child: Text('Lobby has been closed.'));
            }

            final bool gameStarted = gameData['gameStarted'] ?? false;
            if (!gameStarted) {
              _returnToLobby();
              return const Center(child: Text('Game ended. Returning to lobby...'));
            }

            final String gamePhase = gameData['gamePhase'] ?? '';
            final roles = Map<String, dynamic>.from(gameData['roles'] ?? {});
            final alivePlayers = List<String>.from(gameData['alivePlayers'] ?? []);
            final roundOrder = List<String>.from(gameData['roundOrder'] ?? []);
            final int currentPlayerIndex = gameData['currentPlayerIndex'] ?? 0;
            final bool isRoundFinished = gameData['roundFinished'] ?? false;
            final rolesAcknowledged = Map<String, dynamic>.from(gameData['rolesAcknowledged'] ?? {})
                .map((k, v) => MapEntry(k, v == true));
            final votes = Map<String, dynamic>.from(gameData['votes'] ?? {});

            final String playerRole = roles[widget.playerName] ?? 'Spectator';
            final String word = gameData['selectedWord'] ?? '';
            final String icon = gameData['selectedIcon'] ?? defaultIconPath;
            final bool isChampion = gameData['selectedIsChampion'] ?? true;
            final String? lastEliminated = gameData['lastEliminated'];

            if (gamePhase == 'gameOver') {
              final String winner = gameData['winner'] ?? 'Unknown';
              final undercover = roles.entries
                  .where((e) => e.value == 'Undercover')
                  .map((e) => e.key)
                  .join(', ');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Game Over!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Text('$winner win!', style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 12),
                    Text('The Undercover was $undercover', style: const TextStyle(fontSize: 16)),
                    Text('The word was $word', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 40),
                    if (_isHost)
                      ElevatedButton(
                        onPressed: () => _firebaseService.resetGame(widget.lobbyId),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        child: const Text('Return to Lobby'),
                      )
                    else
                      const Text('Waiting for the host to return to the lobby...'),
                  ],
                ),
              );
            }

            if (gamePhase == 'revealingRoles') {
              if (rolesAcknowledged.isNotEmpty && rolesAcknowledged.values.every((v) => v)) {
                _hostTransition(() => _firebaseService.startGameRounds(widget.lobbyId));
              }
              return PlayerRoleScreen(
                lobbyId: widget.lobbyId,
                playerName: widget.playerName,
                role: playerRole,
                word: word,
                icon: icon,
                isChampion: isChampion,
                rolesAcknowledged: rolesAcknowledged,
              );
            }

            // Eliminated players spectate; the host keeps the full view so
            // they can still end the game.
            if (!alivePlayers.contains(widget.playerName) && !_isHost) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('You have been eliminated!', style: TextStyle(fontSize: 24)),
                    const SizedBox(height: 12),
                    Text('${alivePlayers.length} players remain', style: const TextStyle(fontSize: 16)),
                  ],
                ),
              );
            }

            if (gamePhase == 'playing') {
              if (!isRoundFinished) {
                final String? currentPlayer =
                    currentPlayerIndex < roundOrder.length ? roundOrder[currentPlayerIndex] : null;
                return RoundScreen(
                  lobbyId: widget.lobbyId,
                  currentPlayer: currentPlayer,
                  currentPlayerIndex: currentPlayerIndex,
                  isCurrentPlayer: currentPlayer == widget.playerName,
                  playerRole: playerRole,
                  word: word,
                  icon: icon,
                  isChampion: isChampion,
                  lastEliminated: lastEliminated,
                );
              }

              if (alivePlayers.every(votes.containsKey)) {
                _hostTransition(() => _firebaseService.endVotingRound(widget.lobbyId));
              }
              return VotingScreen(
                lobbyId: widget.lobbyId,
                alivePlayers: alivePlayers,
                votes: votes,
                playerName: widget.playerName,
              );
            }

            return const Center(child: Text('Waiting for game to start...'));
          },
        ),
      ),
    );
  }
}
