import 'package:flutter/material.dart';

class PlayerRoleScreen extends StatelessWidget {
  final String playerName;
  final String role;
  final String champion;

  const PlayerRoleScreen({
    Key? key,
    required this.playerName,
    required this.role,
    required this.champion,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Role for $playerName'),
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
              style: TextStyle(fontSize: 24),
            ),
            if (role == 'Undercover')
              Text(
                'Champion: $champion',
                style: TextStyle(fontSize: 24),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}