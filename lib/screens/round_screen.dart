import 'dart:io';

import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/data/data.dart';

class RoundScreen extends StatelessWidget {
  final String lobbyId;
  final List<String> players;
  final int currentPlayerIndex;
  final bool isCurrentPlayer;
  final String playerRole;
  final String word;
  final bool isChampion;

  RoundScreen({
    required this.lobbyId,
    required this.players,
    required this.currentPlayerIndex,
    required this.isCurrentPlayer,
    required this.playerRole,
    required this.word,
    required this.isChampion,
  });

  String getIconPath(String name, bool isChampion) {
    final list = isChampion ? champions : items;
    final item = list.firstWhere(
            (item) => item['name']?.toLowerCase() == name.toLowerCase(),
        orElse: () => {'icon': ''}
    );
    String iconPath = item['icon'] ?? '';

    print("Searching for ${isChampion ? 'champion' : 'item'}: $name");
    print("Icon path from data: $iconPath");

    if (iconPath.isEmpty) {
      for (var ext in ['png', 'jpg', 'jpeg']) {
        String testPath = 'assets/${isChampion ? "champions" : "items"}/$name.$ext';
        print("Trying path: $testPath");
        if (FileSystemEntity.typeSync(testPath) != FileSystemEntityType.notFound) {
          iconPath = testPath;
          print("Found file: $iconPath");
          break;
        }
      }
    }

    if (iconPath.isEmpty) {
      print("No icon found for $name. Using default.");
      return isChampion ? 'assets/default_champion.jpg' : 'assets/default_item.jpg';
    }

    return iconPath;
  }

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
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (playerRole == 'Civilian')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        getIconPath(word, isChampion),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print('Error loading image for $word: $error');
                          return Icon(Icons.error, size: 200);
                        },
                      ),
                    ),
                  if (playerRole == 'Undercover')
                    Icon(Icons.question_mark, size: 200, color: Colors.red),
                  SizedBox(height: 20),
                  Text('Current Player: ${players[currentPlayerIndex]}', style: TextStyle(fontSize: 24)),
                  SizedBox(height: 20),
                  Text('Your Role: $playerRole', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  if (playerRole == 'Civilian')
                    Text(
                      isChampion ? 'Your champion: $word' : 'Your item: $word',
                      style: TextStyle(fontSize: 18, color: isChampion ? Colors.blue : Colors.blue),
                    ),
                  if (playerRole == 'Undercover')
                    Text(
                      'You are the Undercover!',
                      style: TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
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
        ),
      ],
    );
  }
}
