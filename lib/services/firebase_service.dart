import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:undercoverleague/data/data.dart';

/// Vote value that means "no elimination this round".
const String skipVoteValue = 'skip';

const String defaultIconPath = 'assets/default_icon.jpg';

enum JoinResult { ok, notFound, inProgress, nameTaken }

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _lobby(String lobbyId) =>
      _firestore.collection('lobbies').doc(lobbyId);

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns an error message, or null when [name] is usable as a player name.
  static String? validatePlayerName(String name) {
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length > 24) return 'Names must be 24 characters or fewer.';
    if (name.toLowerCase() == skipVoteValue) return 'That name is reserved.';
    return null;
  }

  /// Returns an error message, or null when [lobbyId] is usable as a document ID.
  static String? validateLobbyId(String lobbyId) {
    if (lobbyId.isEmpty) return 'Please enter a lobby ID.';
    if (lobbyId.length > 64) return 'Lobby IDs must be 64 characters or fewer.';
    if (lobbyId.contains('/')) return 'Lobby IDs cannot contain "/".';
    if (lobbyId == '.' || lobbyId == '..') return 'Invalid lobby ID.';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Lobby
  // ---------------------------------------------------------------------------

  /// Creates the lobby. Returns false when a lobby with this ID already exists.
  Future<bool> createLobby(String hostName, String lobbyId) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (doc.exists) return false;
      tx.set(_lobby(lobbyId), {
        'host': hostName,
        'players': [hostName],
        'gameStarted': false,
        'gamePhase': 'lobby',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<JoinResult> joinLobby(String lobbyId, String playerName) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return JoinResult.notFound;
      final data = doc.data()!;
      if (data['gameStarted'] == true) return JoinResult.inProgress;
      final players = List<String>.from(data['players'] ?? []);
      if (players.contains(playerName)) return JoinResult.nameTaken;
      tx.update(_lobby(lobbyId), {
        'players': FieldValue.arrayUnion([playerName]),
      });
      return JoinResult.ok;
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> lobbyStream(String lobbyId) =>
      _lobby(lobbyId).snapshots();

  /// Removes a player from every piece of game state they appear in and, if
  /// that changes the outcome of the game, resolves it. The host leaving
  /// deletes the lobby.
  Future<void> leaveLobby(String lobbyId, String playerName, bool isHost) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return;

      if (isHost) {
        tx.delete(_lobby(lobbyId));
        return;
      }

      final data = doc.data()!;
      final players = List<String>.from(data['players'] ?? [])..remove(playerName);
      final update = <String, dynamic>{'players': players};

      if (data['gameStarted'] == true) {
        final alivePlayers = List<String>.from(data['alivePlayers'] ?? []);
        final roundOrder = List<String>.from(data['roundOrder'] ?? []);
        final roles = Map<String, dynamic>.from(data['roles'] ?? {});
        // Transaction.update only takes string keys (which Firestore parses as
        // dotted paths), so rewrite these maps whole instead of deleting by
        // FieldPath - that keeps names containing '.' safe.
        final rolesAcknowledged = Map<String, dynamic>.from(data['rolesAcknowledged'] ?? {})..remove(playerName);
        final votes = Map<String, dynamic>.from(data['votes'] ?? {})..remove(playerName);
        int currentPlayerIndex = data['currentPlayerIndex'] ?? 0;

        final leaverTurn = roundOrder.indexOf(playerName);
        if (leaverTurn != -1 && leaverTurn < currentPlayerIndex) {
          currentPlayerIndex--;
        }
        alivePlayers.remove(playerName);
        roundOrder.remove(playerName);

        update['alivePlayers'] = alivePlayers;
        update['roundOrder'] = roundOrder;
        update['currentPlayerIndex'] = currentPlayerIndex;
        update['rolesAcknowledged'] = rolesAcknowledged;
        update['votes'] = votes;

        // The leaver was the last in the round order: the round is over.
        if (data['gamePhase'] == 'playing' && currentPlayerIndex >= roundOrder.length) {
          update['roundFinished'] = true;
        }

        final winner = _resolveWinner(alivePlayers, roles);
        if (data['gamePhase'] != 'gameOver' && winner != null) {
          update['gamePhase'] = 'gameOver';
          update['winner'] = winner;
        }
      }

      tx.update(_lobby(lobbyId), update);
    });
  }

  Future<bool> lobbyExists(String lobbyId) async {
    final doc = await _lobby(lobbyId).get();
    return doc.exists;
  }

  // ---------------------------------------------------------------------------
  // Game flow
  // ---------------------------------------------------------------------------

  Future<void> startGame(String lobbyId, bool useChampions, bool useItems) {
    if (!useChampions && !useItems) {
      throw ArgumentError('At least one of useChampions or useItems must be true');
    }

    final random = Random();
    final (:word, :isChampion) = drawWord(useChampions, useItems, random);

    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return;
      final data = doc.data()!;
      // Guard against a double tap on "Start Game".
      if (data['gameStarted'] == true) return;

      final players = List<String>.from(data['players'] ?? []);
      if (players.length < 3) return;
      final (:order, :undercover) = drawRoles(players, random);

      final roles = <String, String>{
        for (final p in order) p: p == undercover ? 'Undercover' : 'Civilian',
      };
      final rolesAcknowledged = <String, bool>{for (final p in order) p: false};

      tx.update(_lobby(lobbyId), {
        'gameStarted': true,
        'gamePhase': 'revealingRoles',
        'roles': roles,
        'selectedWord': word['name'],
        'selectedIcon': word['icon'] ?? defaultIconPath,
        'selectedIsChampion': isChampion,
        'players': order,
        'alivePlayers': order,
        'roundOrder': order,
        'currentPlayerIndex': 0,
        'roundFinished': false,
        'votes': {},
        'rolesAcknowledged': rolesAcknowledged,
        'winner': null,
      });
    });
  }

  /// Picks the word for a game. When both categories are enabled the
  /// category is chosen first with a coin flip, then a member of it, so
  /// champions and items each come up 50% of the time even though there are
  /// ~3x more items than champions.
  static ({Map<String, String> word, bool isChampion}) drawWord(
      bool useChampions, bool useItems, Random random) {
    final isChampion = useChampions && (!useItems || random.nextBool());
    final pool = isChampion ? champions : items;
    return (word: pool[random.nextInt(pool.length)], isChampion: isChampion);
  }

  /// Picks the round order and the Undercover. Both are uniform: every
  /// permutation is equally likely and every player has exactly 1/n chance
  /// of being the Undercover, independent of join order or host status.
  /// Pure so it can be tested (see test/draw_roles_test.dart).
  static ({List<String> order, String undercover}) drawRoles(List<String> players, Random random) {
    final order = List<String>.from(players)..shuffle(random);
    return (order: order, undercover: order[random.nextInt(order.length)]);
  }

  Future<void> acknowledgeRole(String lobbyId, String playerName) {
    return _lobby(lobbyId).update({
      FieldPath(['rolesAcknowledged', playerName]): true,
    });
  }

  /// Moves from role reveal to the first round once every player has
  /// acknowledged. Safe to call repeatedly / from several clients.
  Future<void> startGameRounds(String lobbyId) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return;
      final data = doc.data()!;
      if (data['gamePhase'] != 'revealingRoles') return;
      final acks = Map<String, dynamic>.from(data['rolesAcknowledged'] ?? {});
      if (acks.values.any((v) => v != true)) return;

      tx.update(_lobby(lobbyId), {
        'gamePhase': 'playing',
        'roundFinished': false,
        'currentPlayerIndex': 0,
      });
    });
  }

  /// Ends the turn of the player at [expectedIndex]. A stale or duplicate call
  /// (e.g. a double tap) is ignored.
  Future<void> nextPlayer(String lobbyId, int expectedIndex) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return;
      final data = doc.data()!;
      if (data['gamePhase'] != 'playing' || data['roundFinished'] == true) return;
      final int currentPlayerIndex = data['currentPlayerIndex'] ?? 0;
      if (currentPlayerIndex != expectedIndex) return;
      final roundOrder = List<String>.from(data['roundOrder'] ?? []);

      if (currentPlayerIndex < roundOrder.length - 1) {
        tx.update(_lobby(lobbyId), {'currentPlayerIndex': currentPlayerIndex + 1});
      } else {
        tx.update(_lobby(lobbyId), {'roundFinished': true});
      }
    });
  }

  Future<void> castVote(String lobbyId, String voterName, String votedFor) {
    return _lobby(lobbyId).update({
      FieldPath(['votes', voterName]): votedFor,
    });
  }

  /// Tallies the votes once every alive player has voted. Ties and skips
  /// eliminate nobody. Safe to call repeatedly / from several clients.
  Future<void> endVotingRound(String lobbyId) {
    return _firestore.runTransaction((tx) async {
      final doc = await tx.get(_lobby(lobbyId));
      if (!doc.exists) return;
      final data = doc.data()!;
      if (data['gamePhase'] != 'playing' || data['roundFinished'] != true) return;

      final votes = Map<String, dynamic>.from(data['votes'] ?? {});
      final alivePlayers = List<String>.from(data['alivePlayers'] ?? []);
      final roles = Map<String, dynamic>.from(data['roles'] ?? {});
      if (alivePlayers.any((p) => !votes.containsKey(p))) return;

      final voteCount = <String, int>{};
      int skipVotes = 0;
      for (final voter in alivePlayers) {
        final vote = votes[voter];
        if (vote == skipVoteValue) {
          skipVotes++;
        } else if (alivePlayers.contains(vote)) {
          voteCount[vote] = (voteCount[vote] ?? 0) + 1;
        }
      }

      final maxVotes = voteCount.values.fold(0, max);
      final leaders = voteCount.keys.where((p) => voteCount[p] == maxVotes).toList();
      final hasClearWinner = leaders.length == 1 && maxVotes > 0 && maxVotes > skipVotes;

      final update = <String, dynamic>{
        'votes': {},
        'roundFinished': false,
        'currentPlayerIndex': 0,
        // Name of the eliminated player, or '' when the vote was tied/skipped.
        'lastEliminated': hasClearWinner ? leaders.single : '',
      };

      if (hasClearWinner) {
        alivePlayers.remove(leaders.single);
      }
      final roundOrder = List<String>.from(alivePlayers)..shuffle();
      update['alivePlayers'] = alivePlayers;
      update['roundOrder'] = roundOrder;

      final winner = _resolveWinner(alivePlayers, roles);
      if (winner != null) {
        update['gamePhase'] = 'gameOver';
        update['winner'] = winner;
      }

      tx.update(_lobby(lobbyId), update);
    });
  }

  /// Civilians win when the Undercover is gone; the Undercover wins when they
  /// are one of the last two players (a 1v1 vote can never remove them).
  String? _resolveWinner(List<String> alivePlayers, Map<String, dynamic> roles) {
    final undercoverAlive = alivePlayers.any((p) => roles[p] == 'Undercover');
    if (!undercoverAlive) return 'Civilians';
    if (alivePlayers.length <= 2) return 'Undercover';
    return null;
  }

  /// Ends the game (whether finished or aborted by the host) and returns the
  /// lobby to its pre-game state.
  Future<void> resetGame(String lobbyId) {
    return _lobby(lobbyId).update({
      'gameStarted': false,
      'gamePhase': 'lobby',
      'roles': {},
      'selectedWord': FieldValue.delete(),
      'selectedIcon': FieldValue.delete(),
      'selectedIsChampion': FieldValue.delete(),
      'currentPlayerIndex': 0,
      'roundFinished': false,
      'alivePlayers': [],
      'roundOrder': [],
      'votes': {},
      'rolesAcknowledged': {},
      'winner': FieldValue.delete(),
      'lastEliminated': FieldValue.delete(),
    });
  }
}
