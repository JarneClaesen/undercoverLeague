import 'dart:io';

import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/data/data.dart';

class PlayerRoleScreen extends StatelessWidget {
  final String lobbyId;
  final String playerName;
  final String role;
  final String word;
  final Map<String, bool> rolesAcknowledged;
  final bool isChampion;

  const PlayerRoleScreen({
    Key? key,
    required this.lobbyId,
    required this.playerName,
    required this.role,
    required this.word,
    required this.rolesAcknowledged,
    required this.isChampion,
  }) : super(key: key);

  String getIconPath(String name, bool isChampion) {
    final list = isChampion ? champions : items;
    final item = list.firstWhere((item) => item['name']?.toLowerCase() == name.toLowerCase(), orElse: () => {'icon': ''});
    String iconPath = item['icon'] ?? '';

    if (iconPath.isEmpty) {
      for (var ext in ['png', 'jpg', 'jpeg']) {
        if (FileSystemEntity.typeSync('assets/${isChampion ? "champions" : "items"}/$name.$ext') != FileSystemEntityType.notFound) {
          iconPath = 'assets/${isChampion ? "champions" : "items"}/$name.$ext';
          break;
        }
      }
    }

    return iconPath.isNotEmpty ? iconPath : 'assets/default_icon.jpg';
  }

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (role == 'Civilian')
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    getIconPath(word, isChampion),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading image: $error');
                      return Icon(Icons.error, size: 200);
                    },
                  ),
                ),
              if (role == 'Undercover')
                Icon(Icons.question_mark, size: 200, color: Colors.red),
              SizedBox(height: 20),
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
                  isChampion ? 'Your champion: $word' : 'Your item: $word',
                  style: TextStyle(fontSize: 24, color: isChampion ? Colors.blue : Colors.blue),
                ),
              if (role == 'Undercover')
                Text(
                  'You are the Undercover!',
                  style: TextStyle(fontSize: 24, color: Colors.red, fontWeight: FontWeight.bold),
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
      ),
    );
  }
}
