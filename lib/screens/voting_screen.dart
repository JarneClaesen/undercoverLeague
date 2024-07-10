import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undercoverleague/services/firebase_service.dart';

class VotingScreen extends StatefulWidget {
  final String lobbyId;
  final List<String> alivePlayers;
  final String playerName;
  final String hostName;

  VotingScreen({
    required this.lobbyId,
    required this.alivePlayers,
    required this.playerName,
    required this.hostName,
  });

  @override
  _VotingScreenState createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  String? selectedPlayer;
  bool isVoteLocked = false;
  bool _isReturningToLobby = false;

  void _returnToLobby() {
    if (!_isReturningToLobby) {
      _isReturningToLobby = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService().gameStream(widget.lobbyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

        var gameData = snapshot.data!.data() as Map<String, dynamic>?;
        if (gameData == null) return Center(child: Text('Game data not found'));

        bool gameStarted = gameData['gameStarted'] ?? false;
        if (!gameStarted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _returnToLobby();
          });
          return Center(child: Text('Game ended. Returning to lobby...'));
        }

        String gamePhase = gameData['gamePhase'] ?? '';

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
                    FirebaseService().resetGame(widget.lobbyId);
                  },
                  child: Text('Return to Lobby'),
                ),
              ],
            ),
          );
        }

        Map<String, dynamic> votes = Map<String, dynamic>.from(gameData['votes'] ?? {});
        bool isAlive = widget.alivePlayers.contains(widget.playerName);
        int aliveVotesCount = votes.keys.where((voter) => widget.alivePlayers.contains(voter)).length;
        int totalAlivePlayers = widget.alivePlayers.length;

        if (aliveVotesCount == totalAlivePlayers) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseService().endVotingRound(widget.lobbyId);
          });
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Voting',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Votes: $aliveVotesCount/$totalAlivePlayers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (isAlive && !isVoteLocked)
              Expanded(
                child: ListView.builder(
                  itemCount: widget.alivePlayers.length + 1,
                  itemBuilder: (context, index) {
                    if (index == widget.alivePlayers.length) {
                      return CheckboxListTile(
                        title: Text('Skip Vote'),
                        value: selectedPlayer == 'skip',
                        onChanged: (bool? value) {
                          setState(() {
                            selectedPlayer = value! ? 'skip' : null;
                          });
                        },
                      );
                    }
                    String player = widget.alivePlayers[index];
                    if (player != widget.playerName) {
                      return CheckboxListTile(
                        title: Text(player),
                        value: selectedPlayer == player,
                        onChanged: (bool? value) {
                          setState(() {
                            selectedPlayer = value! ? player : null;
                          });
                        },
                      );
                    }
                    return SizedBox.shrink();
                  },
                ),
              )
            else if (!isAlive)
              Expanded(
                child: Center(
                  child: Text('You have been eliminated. Waiting for voting to end.'),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Text('Your vote has been locked in. Waiting for other players.'),
                ),
              ),
            if (isAlive && !isVoteLocked)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: selectedPlayer != null
                      ? () {
                    FirebaseService().castVote(widget.lobbyId, widget.playerName, selectedPlayer!);
                    setState(() {
                      isVoteLocked = true;
                    });
                  }
                      : null,
                  child: Text('Lock in Vote'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
