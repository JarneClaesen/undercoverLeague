import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:undercoverleague/data/data.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> createLobby(String hostName, String lobbyId) async {
    await _firestore.collection('lobbies').doc(lobbyId).set({
      'host': hostName,
      'players': [hostName],
      'gameStarted': false,
    });
    return lobbyId;
  }

  Future<void> joinLobby(String lobbyId, String playerName) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'players': FieldValue.arrayUnion([playerName]),
    });
  }

  Stream<DocumentSnapshot> lobbyStream(String lobbyId) {
    return _firestore.collection('lobbies').doc(lobbyId).snapshots();
  }

  Future<void> leaveLobby(String lobbyId, String playerName, bool isHost) async {
    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    List<String> players = List<String>.from(lobby['players']);
    players.remove(playerName);

    if (isHost) {
      // If the host is leaving, end the game and clear the lobby
      await _firestore.collection('lobbies').doc(lobbyId).delete();
    } else {
      // If a regular player is leaving, just update the players list
      await _firestore.collection('lobbies').doc(lobbyId).update({
        'players': players,
      });

      // If the game has started, also remove the player from alive players
      bool gameStarted = lobby['gameStarted'] ?? false;
      if (gameStarted) {
        List<String> alivePlayers = List<String>.from(lobby['alivePlayers']);
        alivePlayers.remove(playerName);
        await _firestore.collection('lobbies').doc(lobbyId).update({
          'alivePlayers': alivePlayers,
        });
      }
    }
  }

  Future<void> deleteLobby(String lobbyId) async {
    try {
      await _firestore.collection('lobbies').doc(lobbyId).delete();
    } catch (e) {
      print('Error deleting lobby: $e');
      // The lobby might have already been deleted, so we can ignore this error
    }
  }

  Future<bool> lobbyExists(String lobbyId) async {
    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    return lobby.exists;
  }

  Future<void> acknowledgeRole(String lobbyId, String playerName) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'rolesAcknowledged.$playerName': true,
    });
  }

  Future<void> startGameRounds(String lobbyId) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'gamePhase': 'playing',
      'roundFinished': false,
      'currentPlayerIndex': 0,
    });
  }

  Future<void> startGame(String lobbyId, bool useChampions, bool useItems) async {
    List<String> combinedList = [];
    if (useChampions) combinedList.addAll(champions);
    if (useItems) combinedList.addAll(items);
    String selectedItem = (combinedList..shuffle()).first;

    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    List<String> players = List<String>.from(lobby['players']);
    players.shuffle();

    Map<String, String> roles = {};
    roles[players.first] = 'Undercover';
    for (var i = 1; i < players.length; i++) {
      roles[players[i]] = selectedItem;
    }

    Map<String, bool> rolesRevealed = {};
    for (var player in players) {
      rolesRevealed[player] = false;
    }

    Map<String, bool> rolesAcknowledged = {};
    for (var player in players) {
      rolesAcknowledged[player] = false;
    }

    await _firestore.collection('lobbies').doc(lobbyId).update({
      'gameStarted': true,
      'roles': roles,
      'selectedItem': selectedItem,
      'currentPlayerIndex': 0,
      'roundFinished': false,
      'alivePlayers': players,
      'players': players,
      'roundOrder': players,
      'votes': {},
      'hostEliminated': false,
      'rolesAcknowledged': rolesAcknowledged,
      'gamePhase': 'revealingRoles',
    });
  }

  Future<void> endGame(String lobbyId) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'gameStarted': false,
      'roles': {},
      'selectedItem': '',
      'currentPlayerIndex': 0,
      'roundFinished': false,
      'alivePlayers': [],
      'roundOrder': [],
      'votes': {},
      'hostEliminated': false,
    });
  }

  Stream<DocumentSnapshot> gameStream(String lobbyId) {
    return _firestore.collection('lobbies').doc(lobbyId).snapshots();
  }

  Future<void> nextPlayer(String lobbyId) async {
    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    int currentPlayerIndex = lobby['currentPlayerIndex'];
    List<String> roundOrder = List<String>.from(lobby['roundOrder']);

    if (currentPlayerIndex < roundOrder.length - 1) {
      await _firestore.collection('lobbies').doc(lobbyId).update({
        'currentPlayerIndex': currentPlayerIndex + 1,
      });
    } else {
      await _firestore.collection('lobbies').doc(lobbyId).update({
        'roundFinished': true,
      });
    }
  }

  Future<void> eliminatePlayer(String lobbyId, String player) async {
    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    List<String> alivePlayers = List<String>.from(lobby['alivePlayers']);
    alivePlayers.remove(player);

    await _firestore.collection('lobbies').doc(lobbyId).update({
      'alivePlayers': alivePlayers,
      'roundFinished': false,
      'currentPlayerIndex': 0,
      'roundOrder': alivePlayers..shuffle(),
    });
  }

  Future<void> markRoleRevealed(String lobbyId, String playerName) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'rolesRevealed.$playerName': true,
    });
  }

  Future<void> castVote(String lobbyId, String voterName, String votedFor) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'votes.$voterName': votedFor,
    });
  }

  Future<void> skipVote(String lobbyId, String voterName) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'votes.$voterName': 'skip',
    });
  }

  Future<void> endVotingRound(String lobbyId) async {
    DocumentSnapshot lobby = await _firestore.collection('lobbies').doc(lobbyId).get();
    Map<String, dynamic> votes = Map<String, dynamic>.from(lobby['votes'] ?? {});
    List<String> alivePlayers = List<String>.from(lobby['alivePlayers']);
    Map<String, String> roles = Map<String, String>.from(lobby['roles']);

    // Count votes
    Map<String, int> voteCount = {};
    for (var vote in votes.values) {
      if (vote != 'skip' && alivePlayers.contains(vote)) {
        voteCount[vote] = (voteCount[vote] ?? 0) + 1;
      }
    }

    // Find player with most votes
    String? playerToEliminate;
    int maxVotes = 0;
    voteCount.forEach((player, count) {
      if (count > maxVotes) {
        maxVotes = count;
        playerToEliminate = player;
      }
    });

    // Eliminate player if there's a clear winner and at least one vote was cast
    if (playerToEliminate != null && maxVotes > 0) {
      alivePlayers.remove(playerToEliminate);

      if (roles[playerToEliminate] == 'Undercover') {
        // Undercover was eliminated, Civilians win
        await _firestore.collection('lobbies').doc(lobbyId).update({
          'gamePhase': 'gameOver',
          'winner': 'Civilians',
          'alivePlayers': alivePlayers,
        });
        return;
      } else if (alivePlayers.length == 1 && roles[alivePlayers.first] == 'Undercover') {
        // Only Undercover remains, Undercover wins
        await _firestore.collection('lobbies').doc(lobbyId).update({
          'gamePhase': 'gameOver',
          'winner': 'Undercover',
          'alivePlayers': alivePlayers,
        });
        return;
      }
    }

    // Continue the game if it's not over
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'alivePlayers': alivePlayers,
      'roundFinished': false,
      'currentPlayerIndex': 0,
      'roundOrder': alivePlayers..shuffle(),
      'votes': {},
    });
  }


  Future<void> endGameAndReturnToLobby(String lobbyId) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'gameStarted': false,
      'gamePhase': 'lobby',
      'roles': {},
      'selectedItem': '',
      'currentPlayerIndex': 0,
      'roundFinished': false,
      'alivePlayers': [],
      'roundOrder': [],
      'votes': {},
      'rolesAcknowledged': {},
      'winner': null,
    });
  }

  Future<void> resetGame(String lobbyId) async {
    await _firestore.collection('lobbies').doc(lobbyId).update({
      'gameStarted': false,
      'gamePhase': 'lobby',
      'roles': {},
      'selectedItem': '',
      'currentPlayerIndex': 0,
      'roundFinished': false,
      'alivePlayers': [],
      'roundOrder': [],
      'votes': {},
      'rolesAcknowledged': {},
      'winner': null,
    });
  }


}
