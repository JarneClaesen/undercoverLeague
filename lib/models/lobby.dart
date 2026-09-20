import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/models/game_settings.dart';

/// Player roles as the server names them.
class Role {
  static const civilian = 'Civilian';
  static const undercover = 'Undercover';
  static const mrWhite = 'MrWhite';
  static const spectator = 'Spectator';

  static bool isImpostor(String role) => role == undercover || role == mrWhite;

  static String label(String role) => switch (role) {
        mrWhite => 'Mr. White',
        _ => role,
      };
}

/// Game phases as the server names them.
class GamePhase {
  static const lobby = 'lobby';
  static const revealingRoles = 'revealingRoles';
  static const playing = 'playing';
  static const lastGuess = 'lastGuess';
  static const gameOver = 'gameOver';
}

/// One entry of the public clue log (only kept when `clueLog` is on).
class Clue {
  final int round;
  final String player;
  final String text;

  const Clue({required this.round, required this.player, required this.text});

  factory Clue.fromJson(Map<String, dynamic> json) => Clue(
        round: (json['round'] as num?)?.toInt() ?? 0,
        player: json['player'] as String? ?? '',
        text: json['text'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is Clue && other.round == round && other.player == player && other.text == text;

  @override
  int get hashCode => Object.hash(round, player, text);
}

/// The most recent last-breath guess of an eliminated wordless player.
class LastGuess {
  final String player;
  final String word;
  final bool correct;

  const LastGuess({required this.player, required this.word, required this.correct});

  factory LastGuess.fromJson(Map<String, dynamic> json) => LastGuess(
        player: json['player'] as String? ?? '',
        word: json['word'] as String? ?? '',
        correct: json['correct'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is LastGuess && other.player == player && other.word == word && other.correct == correct;

  @override
  int get hashCode => Object.hash(player, word, correct);
}

/// Per-player counters the server keeps for achievements.
class PlayerStats {
  final int civilianSurvivals;
  final int impostorGames;
  final int games;

  const PlayerStats({this.civilianSurvivals = 0, this.impostorGames = 0, this.games = 0});

  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
        civilianSurvivals: (json['civilianSurvivals'] as num?)?.toInt() ?? 0,
        impostorGames: (json['impostorGames'] as num?)?.toInt() ?? 0,
        games: (json['games'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayerStats &&
      other.civilianSurvivals == civilianSurvivals &&
      other.impostorGames == impostorGames &&
      other.games == games;

  @override
  int get hashCode => Object.hash(civilianSurvivals, impostorGames, games);
}

/// One player's view of a lobby, as sent by the server. Secrets are already
/// filtered server-side: only this player's role is included, the word is
/// absent for a wordless player, and [roles] / [selectedWord] are only
/// present once the game is over. [lastVotes] is the exception that is meant
/// to be public: it only ever holds a ballot that has already been tallied.
class Lobby {
  final String id;
  final String host;
  final List<String> players;

  /// Players sitting this game out; a subset of [players].
  final List<String> spectators;
  final bool gameStarted;
  final String gamePhase; // lobby | revealingRoles | playing | lastGuess | gameOver
  final List<String> alivePlayers;
  final List<String> roundOrder;
  final int currentPlayerIndex;
  final bool roundFinished; // false = describing, true = voting

  /// 1-based describing round; 0 in the lobby.
  final int round;

  /// Unix milliseconds when the current turn / vote / guess times out; 0 = no timer.
  final int deadline;
  final Map<String, String> votes;

  /// The ballot of the round that just ended (voter -> target, or 'skip').
  /// Empty until the first tally.
  final Map<String, String> lastVotes;

  /// Every tallied ballot of this game, oldest first.
  final List<Map<String, String>> ballots;
  final Map<String, bool> rolesAcknowledged;

  /// Public clue log of this game (only filled when `clueLog` is on).
  final List<Clue> clues;

  /// Who is making a last guess; '' outside the `lastGuess` phase.
  final String guesser;

  /// The latest last guess of this game; null until the first one.
  final LastGuess? lastGuess;
  final String? winner; // Civilians | Undercover | MrWhite

  /// Why the game ended: eliminated | outnumbered | guess. Null while running.
  final String? winReason;

  /// null before the first vote, '' when a vote eliminated nobody.
  final String? lastEliminated;

  /// Which pack the word was drawn from ('' before a game).
  final String selectedPack;

  final String myRole; // Civilian | Undercover | MrWhite | Spectator
  final String? myWord;
  final String myIcon;

  /// True when [myWord] is a decoy (an Undercover in decoy mode).
  final bool myDecoy;

  final Map<String, String> roles; // empty until game over
  final String? selectedWord; // null until game over

  /// The Undercovers' decoy word; only at game over and only in decoy mode.
  final String? decoyWord;

  /// The host's settings, normalized by the server.
  final GameSettings settings;

  /// Only present in the lobby phase: what [settings] can draw from, which
  /// seasons the sliders may span, the classes, regions, resource buckets
  /// and lanes in the catalog and today's theme. [lanes] is empty when the
  /// server has no play-rate data, and the lane filter is then not offered.
  final PoolSize? poolSize;
  final SeasonRange? seasonRange;
  final List<String> classes;
  final List<String> regions;
  final List<String> resources;
  final List<String> lanes;
  final DailyTheme? dailyTheme;

  /// Lobby-lifetime scoreboard and achievements (player -> ...).
  final Map<String, int> scores;
  final int gamesPlayed;
  final Map<String, List<String>> achievements;
  final Map<String, PlayerStats> stats;

  final Map<String, bool> connected;
  final int version;

  const Lobby({
    required this.id,
    required this.host,
    required this.players,
    this.spectators = const [],
    required this.gameStarted,
    required this.gamePhase,
    required this.alivePlayers,
    required this.roundOrder,
    required this.currentPlayerIndex,
    required this.roundFinished,
    this.round = 0,
    this.deadline = 0,
    required this.votes,
    this.lastVotes = const {},
    this.ballots = const [],
    required this.rolesAcknowledged,
    this.clues = const [],
    this.guesser = '',
    this.lastGuess,
    required this.winner,
    this.winReason,
    required this.lastEliminated,
    String? selectedPack,
    // Older call sites pass the boolean; [selectedPack] wins when both are given.
    bool selectedIsChampion = false,
    required this.myRole,
    required this.myWord,
    required this.myIcon,
    this.myDecoy = false,
    required this.roles,
    required this.selectedWord,
    this.decoyWord,
    this.settings = const GameSettings(),
    this.poolSize,
    this.seasonRange,
    this.classes = const [],
    this.regions = const [],
    this.resources = const [],
    this.lanes = const [],
    this.dailyTheme,
    this.scores = const {},
    this.gamesPlayed = 0,
    this.achievements = const {},
    this.stats = const {},
    required this.connected,
    required this.version,
  }) : selectedPack = selectedPack ?? (selectedIsChampion ? WordPack.champions : '');

  factory Lobby.fromJson(Map<String, dynamic> json) {
    return Lobby(
      id: json['id'] as String? ?? '',
      host: json['host'] as String? ?? '',
      players: _strings(json['players']),
      spectators: _strings(json['spectators']),
      gameStarted: json['gameStarted'] as bool? ?? false,
      gamePhase: json['gamePhase'] as String? ?? GamePhase.lobby,
      alivePlayers: _strings(json['alivePlayers']),
      roundOrder: _strings(json['roundOrder']),
      currentPlayerIndex: _int(json['currentPlayerIndex']),
      roundFinished: json['roundFinished'] as bool? ?? false,
      round: _int(json['round']),
      deadline: _int(json['deadline']),
      votes: _map<String>(json['votes']),
      lastVotes: _map<String>(json['lastVotes']),
      ballots: [for (final b in (json['ballots'] as List?) ?? const []) _map<String>(b)],
      rolesAcknowledged: _map<bool>(json['rolesAcknowledged']),
      clues: [for (final c in (json['clues'] as List?) ?? const []) Clue.fromJson((c as Map).cast())],
      guesser: json['guesser'] as String? ?? '',
      lastGuess: json['lastGuess'] is Map ? LastGuess.fromJson((json['lastGuess'] as Map).cast()) : null,
      winner: json['winner'] as String?,
      winReason: _nonEmpty(json['winReason']),
      lastEliminated: json['lastEliminated'] as String?,
      // Old servers sent a boolean; keep reading it so a mixed deploy works.
      selectedPack: json['selectedPack'] as String? ?? (json['selectedIsChampion'] == true ? WordPack.champions : ''),
      myRole: json['myRole'] as String? ?? Role.spectator,
      myWord: json['myWord'] as String?,
      myIcon: json['myIcon'] as String? ?? 'assets/default_icon.jpg',
      myDecoy: json['myDecoy'] as bool? ?? false,
      roles: _map<String>(json['roles']),
      selectedWord: json['selectedWord'] as String?,
      decoyWord: _nonEmpty(json['decoyWord']),
      settings: json['settings'] is Map ? GameSettings.fromJson((json['settings'] as Map).cast()) : const GameSettings(),
      poolSize: json['poolSize'] is Map ? PoolSize.fromJson((json['poolSize'] as Map).cast()) : null,
      seasonRange: json['seasonRange'] is Map ? SeasonRange.fromJson((json['seasonRange'] as Map).cast()) : null,
      classes: _strings(json['classes']),
      regions: _strings(json['regions']),
      resources: _strings(json['resources']),
      lanes: _strings(json['lanes']),
      dailyTheme: json['dailyTheme'] is Map ? DailyTheme.fromJson((json['dailyTheme'] as Map).cast()) : null,
      scores: {for (final e in _map<Object?>(json['scores']).entries) e.key: _int(e.value)},
      gamesPlayed: _int(json['gamesPlayed']),
      achievements: {for (final e in _map<Object?>(json['achievements']).entries) e.key: _strings(e.value)},
      stats: {
        for (final e in _map<Object?>(json['stats']).entries)
          if (e.value is Map) e.key: PlayerStats.fromJson((e.value as Map).cast()),
      },
      connected: _map<bool>(json['connected']),
      version: _int(json['version']),
    );
  }

  bool get isGameOver => gamePhase == GamePhase.gameOver;
  bool get isLastGuess => gamePhase == GamePhase.lastGuess;

  /// Kept for screens written against the boolean; prefer [selectedPack].
  bool get selectedIsChampion => selectedPack == WordPack.champions;

  String? get currentPlayer =>
      currentPlayerIndex < roundOrder.length ? roundOrder[currentPlayerIndex] : null;

  bool isSpectator(String name) => spectators.contains(name);

  /// Everyone who plays this game: [players] minus the spectators.
  List<String> get activePlayers => players.where((p) => !spectators.contains(p)).toList();

  /// Names of the Undercover(s); only known once the game is over.
  String get undercoverNames =>
      roles.entries.where((e) => e.value == Role.undercover).map((e) => e.key).join(', ');

  /// Names of every impostor (Undercovers and Mr. Whites); only known once
  /// the game is over.
  String get impostorNames =>
      roles.entries.where((e) => Role.isImpostor(e.value)).map((e) => e.key).join(', ');

  /// Time left on the current deadline, null when no timer is running.
  /// Never negative: an overdue deadline reads as zero until the server
  /// moves on.
  Duration? deadlineRemaining(DateTime now) {
    if (deadline == 0) return null;
    final left = deadline - now.millisecondsSinceEpoch;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  static List<String> _strings(Object? v) => (v as List?)?.cast<String>() ?? const [];

  static Map<String, T> _map<T>(Object? v) => (v as Map?)?.cast<String, T>() ?? const {};

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
}
