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

  GameScreen({required this.lobbyId, required this.playerName, required this.hostName});

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _isReturningToLobby = false;

  void _showEndGameConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('End Game'),
          content: Text('Are you sure you want to end the game and return to the lobby?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('End Game'),
              onPressed: () {
                Navigator.of(context).pop();
                FirebaseService().endGameAndReturnToLobby(widget.lobbyId);
              },
            ),
          ],
        );
      },
    );
  }

  void _returnToLobby() {
    if (!_isReturningToLobby) {
      _isReturningToLobby = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.playerName == widget.hostName) {
          _showEndGameConfirmationDialog();
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Undercover Game'),
          automaticallyImplyLeading: false,
          actions: [
            if (widget.playerName == widget.hostName)
              IconButton(
                icon: Icon(Icons.stop),
                onPressed: _showEndGameConfirmationDialog,
                tooltip: 'End Game',
              ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseService().gameStream(widget.lobbyId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

            var gameData = snapshot.data!.data() as Map<String, dynamic>?;

            if (gameData == null) {
              return Center(child: Text('Game data not found'));
            }

            bool gameStarted = gameData['gameStarted'] ?? false;
            if (!gameStarted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _returnToLobby();
              });
              return Center(child: Text('Game ended. Returning to lobby...'));
            }

            String gamePhase = gameData['gamePhase'] ?? '';
            Map<String, String> roles = Map<String, String>.from(gameData['roles'] ?? {});
            List<String> alivePlayers = List<String>.from(gameData['alivePlayers'] ?? []);
            List<String> roundOrder = List<String>.from(gameData['roundOrder'] ?? []);
            int currentPlayerIndex = gameData['currentPlayerIndex'] ?? 0;
            bool isRoundFinished = gameData['roundFinished'] ?? false;
            String selectedItem = gameData['selectedItem'] ?? '';
            Map<String, bool> rolesAcknowledged = Map<String, bool>.from(gameData['rolesAcknowledged'] ?? {});

            if (gamePhase == 'gameOver') {
              String winner = gameData['winner'] ?? 'Unknown';
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Game Over!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 20),
                    Text('$winner win!', style: TextStyle(fontSize: 20)),
                    SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () {
                        FirebaseService().resetGame(widget.lobbyId).then((_) {
                          _returnToLobby();
                        });
                      },
                      child: Text('Return to Lobby'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        textStyle: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (gamePhase == 'revealingRoles') {
              String playerRole = roles[widget.playerName] ?? 'Spectator';
              String playerWord = selectedItem;

              bool allAcknowledged = rolesAcknowledged.values.every((v) => v == true);

              if (allAcknowledged) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  FirebaseService().startGameRounds(widget.lobbyId);
                });
              }

              return PlayerRoleScreen(
                lobbyId: widget.lobbyId,
                playerName: widget.playerName,
                role: playerRole,
                word: playerWord,
                rolesAcknowledged: rolesAcknowledged,
              );
            }

            if (!alivePlayers.contains(widget.playerName) && widget.playerName != widget.hostName) {
              return Center(child: Text('You have been eliminated!'));
            }

            if (gamePhase == 'playing') {
              if (!isRoundFinished) {
                return RoundScreen(
                  lobbyId: widget.lobbyId,
                  players: roundOrder,
                  currentPlayerIndex: currentPlayerIndex,
                  isCurrentPlayer: roundOrder[currentPlayerIndex] == widget.playerName,
                );
              } else {
                return VotingScreen(
                  lobbyId: widget.lobbyId,
                  alivePlayers: alivePlayers,
                  playerName: widget.playerName,
                  hostName: widget.hostName,
                );
              }
            }

            return Center(child: Text('Waiting for game to start...'));
          },
        ),
      ),
    );
  }
}
