// screens/game_screen.dart

import 'package:flutter/material.dart';
import '../data/data.dart';
import 'round_screen.dart';
import 'add_players_screen.dart';

class GameScreen extends StatefulWidget {
  final List<String> players;
  final bool useChampions;
  final bool useItems;

  GameScreen({required this.players, required this.useChampions, required this.useItems});

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Map<String, String> roles = {};
  String selectedItem = '';
  List<bool> revealedStatus = [];

  @override
  void initState() {
    super.initState();
    assignRoles();
    revealedStatus = List.generate(widget.players.length, (_) => false);
  }

  void assignRoles() {
    setState(() {
      roles.clear();
      List<String> combinedList = [];
      if (widget.useChampions) combinedList.addAll(champions);
      if (widget.useItems) combinedList.addAll(items);
      selectedItem = (combinedList..shuffle()).first;
      List<String> shuffledPlayers = List.from(widget.players)..shuffle();
      roles[shuffledPlayers.first] = 'Undercover';
      for (var i = 1; i < shuffledPlayers.length; i++) {
        roles[shuffledPlayers[i]] = selectedItem;
      }
      revealedStatus = List.generate(widget.players.length, (_) => false);
    });
  }

  bool allRolesRevealed() {
    return revealedStatus.every((revealed) => revealed);
  }

  void startRounds() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RoundScreen(
          players: widget.players,
          roles: roles,
          useChampions: widget.useChampions,
          useItems: widget.useItems,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Undercover Game'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => AddPlayersScreen(),
              ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.players.length,
              itemBuilder: (context, index) {
                String player = widget.players[index];
                return Card(
                  child: ExpansionTile(
                    title: Text(player),
                    trailing: Icon(revealedStatus[index] ? Icons.check : Icons.arrow_drop_down),
                    onExpansionChanged: (expanded) {
                      if (expanded && !revealedStatus[index]) {
                        setState(() {
                          revealedStatus[index] = true;
                        });
                      }
                    },
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          roles[player] ?? 'Role not assigned',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: assignRoles,
                  child: Text('Randomize Roles'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                  ),
                ),
                SizedBox(height: 10),
                if (allRolesRevealed())
                  ElevatedButton(
                    onPressed: startRounds,
                    child: Text('Start Rounds'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
