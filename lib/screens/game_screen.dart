import 'dart:async';

import 'package:flutter/material.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/player_role_screen.dart';
import 'package:undercoverleague/screens/round_screen.dart';
import 'package:undercoverleague/screens/voting_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/widgets/connection_banner.dart';

class GameScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;
  final String hostName;

  const GameScreen({super.key, required this.lobbyId, required this.playerName, required this.hostName});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final LobbyService _lobbyService = LobbyService();
  StreamSubscription<GameError>? _errors;
  bool _isReturningToLobby = false;

  bool get _isHost => widget.playerName == widget.hostName;

  @override
  void initState() {
    super.initState();
    // Actions the server refused (e.g. a tap that arrived after the turn
    // moved on) are worth a small notice; the view itself is already right.
    _errors = GameConnection.instance.errors.listen((e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    super.dispose();
  }

  void _showEndGameConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Game'),
          content: const Text('Are you sure you want to end the game and return to the lobby?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text('End Game'),
              onPressed: () {
                Navigator.of(context).pop();
                _lobbyService.resetGame();
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
              IconButton(icon: const Icon(Icons.stop), onPressed: _showEndGameConfirmationDialog, tooltip: 'End Game'),
          ],
        ),
        body: StreamBuilder<Lobby?>(
          stream: _lobbyService.lobbyStream(),
          initialData: _lobbyService.currentLobby,
          builder: (context, snapshot) {
            final lobby = snapshot.data;
            if (lobby == null) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              // Lobby closed or session lost; the LobbyScreen underneath navigates home.
              return const Center(child: Text('Lobby has been closed.'));
            }

            if (!lobby.gameStarted) {
              _returnToLobby();
              return const Center(child: Text('Game ended. Returning to lobby...'));
            }

            return Column(
              children: [
                const ConnectionBanner(),
                Expanded(child: _gameBody(lobby)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _gameBody(Lobby lobby) {
    // The server already filtered this view for us: myWord is null for the
    // Undercover until the game is over.
    final playerRole = lobby.myRole;
    final word = lobby.myWord ?? lobby.selectedWord ?? '';
    final icon = lobby.myIcon;
    final isChampion = lobby.selectedIsChampion;

    if (lobby.isGameOver) {
      final winner = lobby.winner ?? 'Unknown';
      final undercover = lobby.undercoverNames;
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
                onPressed: _lobbyService.resetGame,
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

    if (lobby.gamePhase == 'revealingRoles') {
      return PlayerRoleScreen(
        playerName: widget.playerName,
        role: playerRole,
        word: word,
        icon: icon,
        isChampion: isChampion,
        rolesAcknowledged: lobby.rolesAcknowledged,
      );
    }

    // Eliminated players spectate; the host keeps the full view so
    // they can still end the game.
    final alivePlayers = lobby.alivePlayers;
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

    if (lobby.gamePhase == 'playing') {
      if (!lobby.roundFinished) {
        final currentPlayer = lobby.currentPlayer;
        return RoundScreen(
          currentPlayer: currentPlayer,
          currentPlayerIndex: lobby.currentPlayerIndex,
          isCurrentPlayer: currentPlayer == widget.playerName,
          playerRole: playerRole,
          word: word,
          icon: icon,
          isChampion: isChampion,
          lastEliminated: lobby.lastEliminated,
        );
      }

      return VotingScreen(alivePlayers: alivePlayers, votes: lobby.votes, playerName: widget.playerName);
    }

    return const Center(child: Text('Waiting for game to start...'));
  }
}
