import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';

class RoundScreen extends StatelessWidget {
  final String lobbyId;
  final List<String> players;
  final int currentPlayerIndex;
  final bool isCurrentPlayer;

  RoundScreen({
    required this.lobbyId,
    required this.players,
    required this.currentPlayerIndex,
    required this.isCurrentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Turn ${currentPlayerIndex + 1}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Current Player: ${players[currentPlayerIndex]}', style: TextStyle(fontSize: 24)),
                SizedBox(height: 20),
                if (isCurrentPlayer)
                  ElevatedButton(
                    onPressed: () => FirebaseService().nextPlayer(lobbyId),
                    child: Text('End Turn'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
