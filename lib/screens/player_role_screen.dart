import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';

class PlayerRoleScreen extends StatelessWidget {
  final String lobbyId;
  final String playerName;
  final String role;
  final String word;
  final Map<String, bool> rolesAcknowledged;

  const PlayerRoleScreen({
    Key? key,
    required this.lobbyId,
    required this.playerName,
    required this.role,
    required this.word,
    required this.rolesAcknowledged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    int readyCount = rolesAcknowledged.values.where((v) => v).length;
    int totalPlayers = rolesAcknowledged.length;
    bool hasAcknowledged = rolesAcknowledged[playerName] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Role'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Player: $playerName',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 20),
            Text(
              'Role: $role',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            if (role == 'Civilian')
              Text(
                'Your word: $word',
                style: TextStyle(fontSize: 24, color: Colors.blue),
              ),
            SizedBox(height: 40),
            Text(
              'Players ready: $readyCount/$totalPlayers',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            if (!hasAcknowledged)
              ElevatedButton(
                onPressed: () {
                  FirebaseService().acknowledgeRole(lobbyId, playerName);
                },
                child: Text('I understand my role'),
              ),
            if (hasAcknowledged)
              Text('Waiting for other players...', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
