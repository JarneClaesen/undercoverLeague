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

  const LobbyScreen({
    super.key,
    required this.lobbyId,
    required this.playerName,
    required this.isHost,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLeaving = false;
  bool _isStarting = false;
  bool _inGame = false;
  bool useChampions = true;
  bool useItems = true;

  @override
  void dispose() {
    // Leaving through any path other than the dialog (e.g. the lobby was
    // deleted under us) still needs to remove this player server-side.
    if (!_isLeaving) {
      _isLeaving = true;
      _firebaseService
          .leaveLobby(widget.lobbyId, widget.playerName, widget.isHost)
          .catchError((e) => debugPrint('Error leaving lobby: $e'));
    }
    super.dispose();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const ResponsiveLayout(child: HomeScreen())),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _leaveLobby() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    try {
      await _firebaseService.leaveLobby(widget.lobbyId, widget.playerName, widget.isHost);
    } catch (e) {
      debugPrint('Error leaving lobby: $e');
    }
    _goHome();
  }

  void _showLeaveConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave Lobby'),
          content: Text(widget.isHost
              ? 'You are the host. Leaving will close the lobby for everyone.'
              : 'Are you sure you want to leave the lobby?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Leave'),
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

  Future<void> _startGame() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      await _firebaseService.startGame(widget.lobbyId, useChampions, useItems);
    } catch (e) {
      debugPrint('Error starting game: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the game. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _openGame(String hostName) {
    if (_inGame || _isLeaving) return;
    _inGame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        if (mounted) setState(() => _inGame = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showLeaveConfirmationDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lobby'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'Leave lobby',
              onPressed: _showLeaveConfirmationDialog,
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

            final lobbyData = snapshot.data!.data();
            if (lobbyData == null) {
              // The host closed the lobby.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_isLeaving) _goHome();
              });
              return const Center(child: Text('Lobby has been closed. Returning to home screen...'));
            }

            final String hostName = lobbyData['host'] ?? '';
            final bool gameStarted = lobbyData['gameStarted'] ?? false;
            final players = List<String>.from(lobbyData['players'] ?? [])
              ..remove(hostName)
              ..insert(0, hostName);

            if (gameStarted) {
              _openGame(hostName);
              return const Center(child: Text('Game in progress...'));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Lobby ID: ${widget.lobbyId}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      final isHost = player == hostName;
                      return ListTile(
                        title: Text(player),
                        leading: const Icon(Icons.person),
                        trailing: isHost ? const Icon(Icons.star, color: Colors.yellow) : null,
                      );
                    },
                  ),
                ),
                if (widget.isHost) ...[
                  CheckboxListTile(
                    title: const Text('Use Champions'),
                    value: useChampions,
                    // Never allow both to be off: there would be nothing to draw.
                    onChanged: !useItems ? null : (value) => setState(() => useChampions = value!),
                  ),
                  CheckboxListTile(
                    title: const Text('Use Items'),
                    value: useItems,
                    onChanged: !useChampions ? null : (value) => setState(() => useItems = value!),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: players.length >= 3 && !_isStarting ? _startGame : null,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: Text(players.length >= 3 ? 'Start Game' : 'Need at least 3 players'),
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(16.0),
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
