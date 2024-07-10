import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/screens/game_screen.dart';
import 'package:undercoverleague/screens/home_screen.dart';
import 'package:undercoverleague/widgets/responsive_layout.dart';

class LobbyScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;
  final bool isHost;

  LobbyScreen({required this.lobbyId, required this.playerName, required this.isHost});

  @override
  _LobbyScreenState createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLeaving = false;
  bool useChampions = true;
  bool useItems = true;
  bool _gameStarted = false;

  @override
  void dispose() {
    if (!_isLeaving) {
      _leaveLobby();
    }
    super.dispose();
  }

  Future<void> _leaveLobby() async {
    if (_isLeaving) return;
    setState(() {
      _isLeaving = true;
    });
    try {
      await _firebaseService.leaveLobby(widget.lobbyId, widget.playerName, widget.isHost);
    } catch (e) {
      print('Error leaving lobby: $e');
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => ResponsiveLayout(child: HomeScreen())),
            (Route<dynamic> route) => false,
      );
    }
  }

  void _showLeaveConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Leave Lobby'),
          content: Text('Are you sure you want to leave the lobby?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Leave'),
              onPressed: () {
                Navigator.of(context).pop();
                _leaveLobby();
              },
            ),
          ],
        );
      },
    );
  }

  void _startGame() async {
    await _firebaseService.startGame(widget.lobbyId, useChampions, useItems);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showLeaveConfirmationDialog();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Lobby'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(Icons.exit_to_app),
              onPressed: _showLeaveConfirmationDialog,
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _firebaseService.lobbyStream(widget.lobbyId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('An error occurred. Please try again.'));
            }

            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            if (!snapshot.data!.exists) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_isLeaving) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => ResponsiveLayout(child: HomeScreen())),
                        (Route<dynamic> route) => false,
                  );
                }
              });
              return Center(child: Text('Lobby has been closed. Returning to home screen...'));
            }

            var lobbyData = snapshot.data!.data() as Map<String, dynamic>?;

            if (lobbyData == null) {
              return Center(child: Text('Lobby data is null. Please try again.'));
            }

            List<String> players = List<String>.from(lobbyData['players']);
            String hostName = lobbyData['host'];
            bool gameStarted = lobbyData['gameStarted'] ?? false;

            // Sort players to put host at the top
            players.remove(hostName);
            players.insert(0, hostName);

            if (gameStarted && !_gameStarted) {
              _gameStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResponsiveLayout(
                      child: GameScreen(
                        lobbyId: widget.lobbyId,
                        playerName: widget.playerName,
                        hostName: hostName,
                      ),
                    ),
                  ),
                ).then((_) {
                  setState(() {
                    _gameStarted = false;
                  });
                });
              });
            }

            if (gameStarted) {
              return Center(child: Text('Game in progress...'));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Lobby ID: ${widget.lobbyId}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      String player = players[index];
                      bool isHost = player == hostName;
                      return ListTile(
                        title: Text(player),
                        leading: Icon(Icons.person),
                        trailing: isHost ? Icon(Icons.star, color: Colors.yellow) : null,
                      );
                    },
                  ),
                ),
                if (widget.isHost) ...[
                  CheckboxListTile(
                    title: Text('Use Champions'),
                    value: useChampions,
                    onChanged: (value) => setState(() => useChampions = value!),
                  ),
                  CheckboxListTile(
                    title: Text('Use Items'),
                    value: useItems,
                    onChanged: (value) => setState(() => useItems = value!),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: players.length >= 3 ? _startGame : null,
                      child: Text('Start Game'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
                  ),
                ],
                if (!widget.isHost)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Waiting for host to start the game...', style: TextStyle(fontSize: 16)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
