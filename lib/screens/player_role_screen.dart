import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/widgets/role_card.dart';

/// Body of the role-reveal phase. Rendered inside GameScreen's Scaffold.
class PlayerRoleScreen extends StatelessWidget {
  final String lobbyId;
  final String playerName;
  final String role;
  final String word;
  final String icon;
  final bool isChampion;
  final Map<String, bool> rolesAcknowledged;

  const PlayerRoleScreen({
    super.key,
    required this.lobbyId,
    required this.playerName,
    required this.role,
    required this.word,
    required this.icon,
    required this.isChampion,
    required this.rolesAcknowledged,
  });

  @override
  Widget build(BuildContext context) {
    final readyCount = rolesAcknowledged.values.where((v) => v).length;
    final totalPlayers = rolesAcknowledged.length;
    final hasAcknowledged = rolesAcknowledged[playerName] ?? false;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            RoleCard(role: role, word: word, icon: icon, isChampion: isChampion, large: true),
            const SizedBox(height: 40),
            Text('Players ready: $readyCount/$totalPlayers', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            if (!hasAcknowledged && role != 'Spectator')
              ElevatedButton(
                onPressed: () => FirebaseService().acknowledgeRole(lobbyId, playerName),
                child: const Text('I understand my role'),
              )
            else
              const Text('Waiting for other players...', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
