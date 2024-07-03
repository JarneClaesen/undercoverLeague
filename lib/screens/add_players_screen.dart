// screens/add_players_screen.dart

import 'package:flutter/material.dart';
import 'game_screen.dart';

class AddPlayersScreen extends StatefulWidget {
  @override
  _AddPlayersScreenState createState() => _AddPlayersScreenState();
}

class _AddPlayersScreenState extends State<AddPlayersScreen> {
  List<String> players = [];
  final TextEditingController playerController = TextEditingController();
  bool useChampions = true;
  bool useItems = true;

  void addPlayer() {
    String name = playerController.text.trim();
    if (name.isNotEmpty) {
      setState(() {
        players.add(name);
        playerController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Players'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: playerController,
                    decoration: InputDecoration(
                      labelText: 'Enter player name',
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: addPlayer,
                  child: Text('Add Player'),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Checkbox(
                value: useChampions,
                onChanged: (value) {
                  setState(() {
                    useChampions = value!;
                  });
                },
              ),
              Text('Champions'),
              SizedBox(width: 20),
              Checkbox(
                value: useItems,
                onChanged: (value) {
                  setState(() {
                    useItems = value!;
                  });
                },
              ),
              Text('Items'),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: players.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(players[index]),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (players.length < 3) {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Not Enough Players'),
                      content: Text('Please add at least 3 players to start the game.'),
                      actions: [
                        TextButton(
                          child: Text('OK'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    );
                  },
                );
              } else if (!useChampions && !useItems) {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('No Category Selected'),
                      content: Text('Please select at least one category (Champions or Items).'),
                      actions: [
                        TextButton(
                          child: Text('OK'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    );
                  },
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GameScreen(
                      players: players,
                      useChampions: useChampions,
                      useItems: useItems,
                    ),
                  ),
                );
              }
            },
            child: Text('Start Game'),
          ),
          SizedBox(height: 50),
        ],
      ),
    );
  }
}
