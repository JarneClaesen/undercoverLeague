/// One player's view of a lobby, as sent by the server. Secrets are already
/// filtered server-side: only this player's role is included, the word is
/// absent for the Undercover, and [roles] / [selectedWord] are only present
/// once the game is over.
class Lobby {
  final String id;
  final String host;
  final List<String> players;
  final bool gameStarted;
  final String gamePhase; // lobby | revealingRoles | playing | gameOver
  final List<String> alivePlayers;
  final List<String> roundOrder;
  final int currentPlayerIndex;
  final bool roundFinished; // false = describing, true = voting
  final Map<String, String> votes;
  final Map<String, bool> rolesAcknowledged;
  final String? winner;
  /// null before the first vote, '' when a vote eliminated nobody.
  final String? lastEliminated;
  final bool selectedIsChampion;

  final String myRole; // Civilian | Undercover | Spectator
  final String? myWord;
  final String myIcon;

  final Map<String, String> roles; // empty until game over
  final String? selectedWord; // null until game over

  final Map<String, bool> connected;
  final int version;

  const Lobby({
    required this.id,
    required this.host,
    required this.players,
    required this.gameStarted,
    required this.gamePhase,
    required this.alivePlayers,
    required this.roundOrder,
    required this.currentPlayerIndex,
    required this.roundFinished,
    required this.votes,
    required this.rolesAcknowledged,
    required this.winner,
    required this.lastEliminated,
    required this.selectedIsChampion,
    required this.myRole,
    required this.myWord,
    required this.myIcon,
    required this.roles,
    required this.selectedWord,
    required this.connected,
    required this.version,
  });

  factory Lobby.fromJson(Map<String, dynamic> json) {
    return Lobby(
      id: json['id'] as String? ?? '',
      host: json['host'] as String? ?? '',
      players: _strings(json['players']),
      gameStarted: json['gameStarted'] as bool? ?? false,
      gamePhase: json['gamePhase'] as String? ?? 'lobby',
      alivePlayers: _strings(json['alivePlayers']),
      roundOrder: _strings(json['roundOrder']),
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      roundFinished: json['roundFinished'] as bool? ?? false,
      votes: _map<String>(json['votes']),
      rolesAcknowledged: _map<bool>(json['rolesAcknowledged']),
      winner: json['winner'] as String?,
      lastEliminated: json['lastEliminated'] as String?,
      selectedIsChampion: json['selectedIsChampion'] as bool? ?? false,
      myRole: json['myRole'] as String? ?? 'Spectator',
      myWord: json['myWord'] as String?,
      myIcon: json['myIcon'] as String? ?? 'assets/default_icon.jpg',
      roles: _map<String>(json['roles']),
      selectedWord: json['selectedWord'] as String?,
      connected: _map<bool>(json['connected']),
      version: json['version'] as int? ?? 0,
    );
  }

  bool get isGameOver => gamePhase == 'gameOver';

  String? get currentPlayer =>
      currentPlayerIndex < roundOrder.length ? roundOrder[currentPlayerIndex] : null;

  /// Names of the Undercover(s); only known once the game is over.
  String get undercoverNames =>
      roles.entries.where((e) => e.value == 'Undercover').map((e) => e.key).join(', ');

  static List<String> _strings(Object? v) => (v as List?)?.cast<String>() ?? const [];

  static Map<String, T> _map<T>(Object? v) => (v as Map?)?.cast<String, T>() ?? const {};
}
