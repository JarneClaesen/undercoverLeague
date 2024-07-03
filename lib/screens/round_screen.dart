// screens/round_screen.dart

import 'package:flutter/material.dart';
import 'dart:math';

class RoundScreen extends StatefulWidget {
  final List<String> players;
  final Map<String, String> roles;
  final bool useChampions;
  final bool useItems;

  RoundScreen({
    required this.players,
    required this.roles,
    required this.useChampions,
    required this.useItems,
  });

  @override
  _RoundScreenState createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  List<String> alivePlayers = [];
  List<String> roundOrder = [];
  int currentPlayerIndex = 0;
  bool isRoundFinished = false;

  @override
  void initState() {
    super.initState();
    alivePlayers = List.from(widget.players);
    startNewRound();
  }

  void startNewRound() {
    setState(() {
      roundOrder = List.from(alivePlayers)..shuffle();
      currentPlayerIndex = 0;
      isRoundFinished = false;
    });
  }

  void nextPlayer() {
    setState(() {
      if (currentPlayerIndex < roundOrder.length - 1) {
        currentPlayerIndex++;
      } else {
        isRoundFinished = true;
      }
    });
  }

  void eliminatePlayer(String player) {
    setState(() {
      alivePlayers.remove(player);
      if (widget.roles[player] == 'Undercover') {
        // Game over, civilians win
        showGameOverDialog('Civilians Win!');
      } else if (alivePlayers.length == 1 && widget.roles[alivePlayers.first] == 'Undercover') {
        // Game over, undercover wins
        showGameOverDialog('Undercover Wins!');
      } else {
        // Continue to next round
        startNewRound();
      }
    });
  }

  void showGameOverDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Game Over'),
          content: Text(message),
          actions: [
            TextButton(
              child: Text('New Game'),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Round ${alivePlayers.length}'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isRoundFinished)
              Text('Current Player: ${roundOrder[currentPlayerIndex]}', style: TextStyle(fontSize: 24)),
            if (isRoundFinished)
              Text('Round Finished', style: TextStyle(fontSize: 24)),
            SizedBox(height: 20),
            if (!isRoundFinished)
              ElevatedButton(
                onPressed: nextPlayer,
                child: Text('Next Player'),
              ),
            if (isRoundFinished)
              Column(
                children: [
                  ...alivePlayers.map((player) => ElevatedButton(
                    onPressed: () => eliminatePlayer(player),
                    child: Text('Eliminate $player'),
                  )).toList(),
                  ElevatedButton(
                    onPressed: startNewRound,
                    child: Text('Skip Elimination'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
