import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/game_connection.dart';

/// Vote value that means "no elimination this round".
const String skipVoteValue = 'skip';

const String defaultIconPath = 'assets/default_icon.jpg';

/// The emoji the server accepts for [LobbyService.react], in its order:
/// fire, joy, eyes, thinking, scream, clap, skull, brain.
const List<String> reactionEmoji = [
  '\u{1F525}',
  '\u{1F602}',
  '\u{1F440}',
  '\u{1F914}',
  '\u{1F631}',
  '\u{1F44F}',
  '\u{1F480}',
  '\u{1F9E0}',
];

/// Longest clue the server keeps, in characters.
const int maxClueLength = 40;

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

  /// Lobby codes are not case sensitive; the server stores and shows them in
  /// upper case, so the client does the same before sending or displaying one.
  static String normalizeLobbyId(String lobbyId) => lobbyId.trim().toUpperCase();

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
    final problem = validateSettings(settings);
    if (problem != null) throw ArgumentError(problem);
    _connection.send({'type': 'settings', 'settings': settings.toJson()});
  }

  /// Returns why the server would refuse [settings], or null when it would
  /// not. The player-count rule is only checked at start, not here.
  static String? validateSettings(GameSettings settings) {
    if (settings.packs.isEmpty) return 'Enable at least one word pack.';
    if (settings.packs.any((p) => !WordPack.all.contains(p))) return 'Unknown word pack.';
    if (settings.undercovers < 1) return 'There must be at least one Undercover.';
    if (settings.mrWhites < 0) return 'Mr. Whites cannot be negative.';
    if (settings.mrWhites > 0 && !settings.decoyWord) {
      return 'Mixed mode needs decoy words, otherwise Undercover and Mr. White are the same role.';
    }
    final t = settings.turnSeconds;
    if (t != 0 && (t < 10 || t > 300)) return 'The turn timer must be off or between 10 and 300 seconds.';
    return null;
  }

  /// Sit this game out (or rejoin the seats); lobby phase only, for yourself.
  void setSpectating(bool spectating) => _connection.send({'type': 'spectate', 'spectating': spectating});

  /// Host only: removes [name] from the lobby, in any phase. They are told
  /// why and may join again.
  void kickPlayer(String name) => _connection.send({'type': 'kick', 'name': name});

  /// Host only; draws from the settings last sent with [updateSettings].
  void startGame() => _connection.send({'type': 'start'});

  void acknowledgeRole() => _connection.send({'type': 'ack'});

  /// Ends the turn of the player at [expectedIndex]; a stale call is ignored.
  void nextPlayer(int expectedIndex) => _connection.send({'type': 'nextPlayer', 'expectedIndex': expectedIndex});

  /// Ends the turn with a typed clue (clue log on). [expectedIndex] guards
  /// against a stale turn like [nextPlayer].
  void submitClue(String text, int expectedIndex) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Write a clue first.');
    if (trimmed.runes.length > maxClueLength) throw ArgumentError('Clues must be $maxClueLength characters or fewer.');
    _connection.send({'type': 'clue', 'text': trimmed, 'expectedIndex': expectedIndex});
  }

  void castVote(String votedFor) => _connection.send({'type': 'vote', 'votedFor': votedFor});

  /// The eliminated wordless player's last guess at the word.
  void submitGuess(String word) => _connection.send({'type': 'guess', 'word': word.trim()});

  /// Host only, at game over: back to the lobby with the same seats and
  /// settings (and the next host, when host rotation is on).
  void playAgain() => _connection.send({'type': 'playAgain'});

  /// Throws an emoji at the room; spectators and eliminated players only.
  /// [emoji] must be one of [reactionEmoji].
  void react(String emoji) {
    if (!reactionEmoji.contains(emoji)) throw ArgumentError('Unknown reaction: $emoji');
    _connection.send({'type': 'react', 'emoji': emoji});
  }

  /// Ends the game (finished or aborted by the host) and returns to the lobby.
  void resetGame() => _connection.send({'type': 'reset'});
}
