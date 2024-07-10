import 'package:flutter/material.dart';
import 'package:undercoverleague/screens/lobby_screen.dart';
import 'package:undercoverleague/services/firebase_service.dart';
import 'package:undercoverleague/widgets/responsive_layout.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lobbyIdController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();

  void _createLobby() async {
    if (_nameController.text.isNotEmpty && _lobbyIdController.text.isNotEmpty) {
      bool lobbyExists = await _firebaseService.lobbyExists(_lobbyIdController.text);
      if (lobbyExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lobby ID already exists. Please choose a different ID.')),
        );
      } else {
        await _firebaseService.createLobby(_nameController.text, _lobbyIdController.text);
        _navigateToLobby(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter both your name and a lobby ID.')),
      );
    }
  }

  void _joinLobby() async {
    if (_nameController.text.isNotEmpty && _lobbyIdController.text.isNotEmpty) {
      bool lobbyExists = await _firebaseService.lobbyExists(_lobbyIdController.text);
      if (lobbyExists) {
        await _firebaseService.joinLobby(_lobbyIdController.text, _nameController.text);
        _navigateToLobby(false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lobby does not exist. Please check the ID.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter both your name and the lobby ID.')),
      );
    }
  }

  void _navigateToLobby(bool isHost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResponsiveLayout(
          child: LobbyScreen(
            lobbyId: _lobbyIdController.text,
            playerName: _nameController.text,
            isHost: isHost,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Undercover League')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Enter your name'),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _lobbyIdController,
              decoration: InputDecoration(labelText: 'Enter lobby ID'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _createLobby,
              child: Text('Create Lobby'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _joinLobby,
              child: Text('Join Lobby'),
            ),
          ],
        ),
      ),
    );
  }
}
