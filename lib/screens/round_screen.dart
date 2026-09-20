import 'package:flutter/material.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/widgets/role_card.dart';

/// Body of a describing round. Rendered inside GameScreen's Scaffold.
class RoundScreen extends StatelessWidget {
  final String? currentPlayer;
  final int currentPlayerIndex;
  final bool isCurrentPlayer;
  final String playerRole;
  final String word;
  final String icon;
  final bool isChampion;
  final String? lastEliminated;

  const RoundScreen({
    super.key,
    required this.currentPlayer,
    required this.currentPlayerIndex,
    required this.isCurrentPlayer,
    required this.playerRole,
    required this.word,
    required this.icon,
    required this.isChampion,
    this.lastEliminated,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Turn ${currentPlayerIndex + 1}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        if (lastEliminated != null)
          Text(
            lastEliminated!.isEmpty ? 'Last vote: nobody was eliminated' : 'Last vote: $lastEliminated was eliminated',
            style: const TextStyle(fontSize: 16, color: Colors.orange),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RoleCard(role: playerRole, word: word, icon: icon, isChampion: isChampion),
                  const SizedBox(height: 20),
                  Text(
                    currentPlayer == null ? 'Waiting...' : 'Current Player: $currentPlayer',
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 20),
                  if (isCurrentPlayer)
                    ElevatedButton(
                      onPressed: () => LobbyService().nextPlayer(currentPlayerIndex),
                      child: const Text('End Turn'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
