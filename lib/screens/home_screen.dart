import 'package:flutter/material.dart';
import 'package:undercoverleague/screens/lobby_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/widgets/responsive_layout.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lobbyIdController = TextEditingController();
  final LobbyService _lobbyService = LobbyService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Coming back here after the session ended elsewhere: say why, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (GameConnection.instance.takeCloseReason()) {
        case 'closed':
          _showMessage('The host closed the lobby.');
        case 'expired':
          _showMessage('Your seat in the lobby is gone. Join again with the same name to get it back.');
        case 'unreachable':
          _showMessage('Lost the connection to the server.');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lobbyIdController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Validates both fields, showing the first problem found. Returns
  /// `(name, lobbyId)` when everything is fine.
  (String, String)? _validatedInput() {
    final name = _nameController.text.trim();
    final lobbyId = _lobbyIdController.text.trim();
    final error = LobbyService.validatePlayerName(name) ?? LobbyService.validateLobbyId(lobbyId);
    if (error != null) {
      _showMessage(error);
      return null;
    }
    return (name, lobbyId);
  }

  Future<void> _run(Future<void> Function(String name, String lobbyId) action) async {
    if (_busy) return;
    final input = _validatedInput();
    if (input == null) return;
    setState(() => _busy = true);
    try {
      await action(input.$1, input.$2);
    } catch (e) {
      debugPrint('Lobby action failed: $e');
      _showMessage('Could not reach the game server. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createLobby() => _run((name, lobbyId) async {
        final created = await _lobbyService.createLobby(name, lobbyId);
        if (!created) {
          _showMessage('Lobby ID already exists. If it is yours, use Join with the same name.');
          return;
        }
        _navigateToLobby(name, lobbyId, isHost: true);
      });

  Future<void> _joinLobby() => _run((name, lobbyId) async {
        final result = await _lobbyService.joinLobby(lobbyId, name);
        switch (result) {
          case JoinResult.ok:
            _navigateToLobby(name, lobbyId, isHost: false);
          case JoinResult.notFound:
            _showMessage('Lobby does not exist. Please check the ID.');
          case JoinResult.inProgress:
            _showMessage('That lobby has a game in progress. Try again when it is over.');
          case JoinResult.nameTaken:
            _showMessage('Someone in that lobby already has that name.');
        }
      });

  void _navigateToLobby(String name, String lobbyId, {required bool isHost}) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResponsiveLayout(
          child: LobbyScreen(lobbyId: lobbyId, playerName: name, isHost: isHost),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Undercover League')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Enter your name'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _lobbyIdController,
              decoration: const InputDecoration(labelText: 'Enter lobby ID'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _createLobby,
              child: const Text('Create Lobby'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _joinLobby,
              child: const Text('Join Lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
