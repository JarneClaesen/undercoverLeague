import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/game_connection.dart';

/// Vote value that means "no elimination this round".
const String skipVoteValue = 'skip';

const String defaultIconPath = 'assets/default_icon.jpg';

enum JoinResult { ok, notFound, inProgress, nameTaken }

/// Thin command layer over [GameConnection]. All game rules run on the
/// server; this only validates input early and maps commands to messages.
class LobbyService {
  final GameConnection _connection = GameConnection.instance;

  // ---------------------------------------------------------------------------
  // Validation (mirrored server-side)
  // ---------------------------------------------------------------------------

  /// Returns an error message, or null when [name] is usable as a player name.
  static String? validatePlayerName(String name) {
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length > 24) return 'Names must be 24 characters or fewer.';
    if (name.toLowerCase() == skipVoteValue) return 'That name is reserved.';
    return null;
  }

  /// Returns an error message, or null when [lobbyId] is usable.
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
  Future<bool> createLobby(String hostName, String lobbyId) async {
    try {
      await _connection.request({'type': 'create', 'lobbyId': lobbyId, 'name': hostName});
      return true;
    } on GameError catch (e) {
      if (e.code == 'exists') return false;
      rethrow;
    }
  }

  Future<JoinResult> joinLobby(String lobbyId, String playerName) async {
    try {
      await _connection.request({'type': 'join', 'lobbyId': lobbyId, 'name': playerName});
      return JoinResult.ok;
    } on GameError catch (e) {
      switch (e.code) {
        case 'notFound':
          return JoinResult.notFound;
        case 'inProgress':
          return JoinResult.inProgress;
        case 'nameTaken':
          return JoinResult.nameTaken;
      }
      rethrow;
    }
  }

  /// Emits every new view of the lobby; `null` when it was closed or lost.
  Stream<Lobby?> lobbyStream() => _connection.lobby;

  /// Last view received, for `StreamBuilder.initialData`.
  Lobby? get currentLobby => _connection.current;

  Future<void> leaveLobby() => _connection.leave();

  // ---------------------------------------------------------------------------
  // Game flow (server validates; rejections surface on GameConnection.errors)
  // ---------------------------------------------------------------------------

  /// Host only. The server stores the settings on the lobby and broadcasts
  /// them (with the resulting pool size) to everyone.
  void updateSettings(GameSettings settings) {
    if (!settings.useChampions && !settings.useItems) {
      throw ArgumentError('At least one of champions or items must be enabled');
    }
    _connection.send({'type': 'settings', 'settings': settings.toJson()});
  }

  /// Host only; draws from the settings last sent with [updateSettings].
  void startGame() => _connection.send({'type': 'start'});

  void acknowledgeRole() => _connection.send({'type': 'ack'});

  /// Ends the turn of the player at [expectedIndex]; a stale call is ignored.
  void nextPlayer(int expectedIndex) => _connection.send({'type': 'nextPlayer', 'expectedIndex': expectedIndex});

  void castVote(String votedFor) => _connection.send({'type': 'vote', 'votedFor': votedFor});

  /// Ends the game (finished or aborted by the host) and returns to the lobby.
  void resetGame() => _connection.send({'type': 'reset'});
}
