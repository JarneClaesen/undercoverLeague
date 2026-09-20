import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/achievements_screen.dart';
import 'package:undercoverleague/screens/game_screen.dart';
import 'package:undercoverleague/screens/home_screen.dart';
import 'package:undercoverleague/screens/scoreboard_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/services/settings_prefs.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/daily_theme_card.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_chip.dart';
import 'package:undercoverleague/widgets/hextech_dialog.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_route.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/lobby_code_panel.dart';
import 'package:undercoverleague/widgets/lobby_open_seat.dart';
import 'package:undercoverleague/widgets/lobby_filters.dart';
import 'package:undercoverleague/widgets/lobby_rules.dart';
import 'package:undercoverleague/widgets/player_tile.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

class LobbyScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;

  /// Whether this player created the lobby. Only the initial value: the host
  /// seat can move ("rotate host"), so the live view's `host` decides.
  final bool isHost;

  const LobbyScreen({
    super.key,
    required this.lobbyId,
    required this.playerName,
    required this.isHost,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  /// The game cannot start below this many non-spectators; the roster shows
  /// the gap until then.
  static const int _minimumPlayers = 3;

  /// Settings changes are collected for this long before they go out, so a
  /// stepper tapped five times sends one message.
  static const Duration _settingsDebounce = Duration(milliseconds: 300);

  final LobbyService _lobbyService = LobbyService();
  bool _isLeaving = false;
  bool _isStarting = false;
  bool _inGame = false;
  StreamSubscription<GameError>? _errors;

  /// Settings edited locally but not yet echoed by the server: shown in place
  /// of the view's while the debounce runs and until the next view after the
  /// send, so controls never snap back under the host's finger.
  GameSettings? _draft;
  Timer? _debounce;
  int _sentVersion = -1;

  /// Whether the device's remembered settings have been pushed to the
  /// server yet; done once, after the first view tells us the catalog's
  /// season range to clamp them into.
  bool _defaultsApplied = false;

  /// Roster size at the previous build, so the moment the lobby becomes
  /// startable can be caught and pointed at exactly once.
  int _lastPlayerCount = 0;
  int _startShimmer = 0;

  bool _isHost(Lobby? lobby) => lobby == null ? widget.isHost : lobby.host == widget.playerName;

  @override
  void initState() {
    super.initState();
    // Rejected settings or a start with an empty pool come back as plain
    // errors; the host needs to see why nothing happened.
    _errors = GameConnection.instance.errors.listen((e) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _draft = null;
      });
      showHextechSnack(context, e.message, tone: SnackTone.error);
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    _debounce?.cancel();
    // Leaving through any path other than the dialog (e.g. the lobby was
    // deleted under us) still needs to remove this player server-side.
    if (!_isLeaving) {
      _isLeaving = true;
      _lobbyService.leaveLobby().catchError((e) => debugPrint('Error leaving lobby: $e'));
    }
    super.dispose();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      hextechRoute(const HomeScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _leaveLobby() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    try {
      await _lobbyService.leaveLobby();
    } catch (e) {
      debugPrint('Error leaving lobby: $e');
    }
    _goHome();
  }

  Future<void> _showLeaveConfirmationDialog() async {
    final confirmed = await showHextechDialog(
      context,
      title: 'Leave lobby',
      message: _isHost(_lobbyService.currentLobby)
          ? 'You are the host. Leaving will close the lobby for everyone.'
          : 'Are you sure you want to leave the lobby?',
      confirmLabel: 'Leave',
      danger: true,
    );
    if (confirmed) await _leaveLobby();
  }

  Future<void> _startGame() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      _flushSettings();
      _lobbyService.startGame();
      // The server answers with a new lobby view; keep the button disabled
      // briefly so a double tap cannot fire twice before it arrives.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Error starting game: $e');
      if (mounted) {
        showHextechSnack(context, 'Could not start the game. Please try again.', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Shows [settings] at once and sends them after [_settingsDebounce].
  void _queueSettings(GameSettings settings) {
    setState(() => _draft = settings);
    _debounce?.cancel();
    _debounce = Timer(_settingsDebounce, _flushSettings);
  }

  /// Sends the pending draft now (also called right before starting).
  void _flushSettings() {
    _debounce?.cancel();
    _debounce = null;
    final settings = _draft;
    if (settings == null) return;
    try {
      _lobbyService.updateSettings(settings);
      _sentVersion = _lobbyService.currentLobby?.version ?? 0;
      final range = _lobbyService.currentLobby?.seasonRange;
      SettingsPrefs.saveHostDefaults(range == null ? settings : settings.unboundedWithin(range));
    } catch (e) {
      debugPrint('Error updating settings: $e');
      if (mounted) {
        setState(() => _draft = null);
        showHextechSnack(context, e is ArgumentError ? '${e.message}' : 'Could not update the settings.',
            tone: SnackTone.error);
      }
    }
  }

  void _toggleSpectating(bool spectating) {
    try {
      _lobbyService.setSpectating(spectating);
    } catch (e) {
      debugPrint('Error toggling spectating: $e');
    }
  }

  /// Pushes the settings remembered on this device the first time the
  /// lobby view (and with it the catalog's season range) arrives. Only for
  /// the player who created the lobby: a host who inherited the seat
  /// through rotation keeps what the table already agreed on.
  void _applySavedDefaults(Lobby lobby) {
    if (_defaultsApplied || !widget.isHost || !_isHost(lobby) || lobby.seasonRange == null) return;
    _defaultsApplied = true;
    final range = lobby.seasonRange!;
    SettingsPrefs.loadHostDefaults().then((saved) {
      if (!mounted || saved == null) return;
      final clamped = saved.clampedTo(range);
      if (clamped != lobby.settings) _queueSettings(clamped);
    });
  }

  /// The impostor counts the roster can still hold, or null when [s]
  /// already fits. Mr. Whites go first, then Undercovers down to one.
  static GameSettings? _clampImpostors(GameSettings s, int activePlayers) {
    if (activePlayers < _minimumPlayers) return null;
    final limit = maxImpostorsFor(activePlayers);
    if (s.impostors <= limit) return null;
    var mrWhites = s.mrWhites;
    var undercovers = s.undercovers;
    while (undercovers + mrWhites > limit && mrWhites > 0) {
      mrWhites--;
    }
    while (undercovers + mrWhites > limit && undercovers > 1) {
      undercovers--;
    }
    return s.copyWith(undercovers: undercovers, mrWhites: mrWhites);
  }

  /// Keeps the impostor counts valid as players leave or sit out, so the
  /// host is never stuck with a start the server would refuse.
  void _clampLive(Lobby lobby, GameSettings shown) {
    if (!_isHost(lobby)) return;
    final clamped = _clampImpostors(shown, lobby.activePlayers.length);
    if (clamped == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _draft != clamped) _queueSettings(clamped);
    });
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _openGame(String hostName) {
    if (_inGame || _isLeaving) return;
    _inGame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        hextechRoute(
          GameScreen(
            lobbyId: widget.lobbyId,
            playerName: widget.playerName,
            hostName: hostName,
          ),
        ),
      ).then((_) {
        if (mounted) setState(() => _inGame = false);
      });
    });
  }

  void _openScoreboard() {
    Navigator.push(context, hextechRoute(ScoreboardScreen(playerName: widget.playerName)));
  }

  void _openAchievements() {
    Navigator.push(context, hextechRoute(AchievementsScreen(playerName: widget.playerName)));
  }

  /// Notices the build in which the lobby first becomes startable, and queues
  /// a one-shot shimmer over the start button to say so.
  void _trackPlayerCount(int count) {
    if (count == _lastPlayerCount) return;
    final becameStartable = _lastPlayerCount < _minimumPlayers && count >= _minimumPlayers;
    _lastPlayerCount = count;
    if (!becameStartable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _startShimmer++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showLeaveConfirmationDialog();
      },
      child: HextechScaffold(
        title: 'Lobby',
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            color: hextech.accent,
            tooltip: 'Scoreboard',
            onPressed: _openScoreboard,
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            color: hextech.accent,
            tooltip: 'Achievements',
            onPressed: _openAchievements,
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            color: HextechColors.danger,
            tooltip: 'Leave lobby',
            onPressed: _showLeaveConfirmationDialog,
          ),
        ],
        body: StreamBuilder<Lobby?>(
          stream: _lobbyService.lobbyStream(),
          initialData: _lobbyService.currentLobby,
          builder: (context, snapshot) {
            final lobby = snapshot.data;
            if (lobby == null) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              // The lobby was closed (host left) or the session was lost.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_isLeaving) _goHome();
              });
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: StatusNotice(
                    message: 'Lobby has been closed. Returning to the home screen…',
                    tone: NoticeTone.warning,
                    pulse: true,
                  ),
                ),
              );
            }

            final hostName = lobby.host;
            final isHost = _isHost(lobby);
            final players = List<String>.from(lobby.players)
              ..remove(hostName)
              ..insert(0, hostName);
            final activeCount = lobby.activePlayers.length;

            if (lobby.gameStarted) {
              _openGame(hostName);
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 20),
                    StatusNotice(
                      message: 'Starting…',
                      tone: NoticeTone.warning,
                      pulse: true,
                    ),
                  ],
                ),
              );
            }

            // The draft has done its job once the server echoed a newer view.
            if (_draft != null && _debounce == null && lobby.version > _sentVersion) _draft = null;
            final settings = _draft ?? lobby.settings;

            _trackPlayerCount(activeCount);
            _applySavedDefaults(lobby);
            _clampLive(lobby, settings);

            final theme = lobby.dailyTheme;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      LobbyCodePanel(lobbyId: widget.lobbyId),
                      const SizedBox(height: 24),
                      _rosterHeader(activeCount, lobby.spectators.length),
                      const SizedBox(height: 12),
                      ..._roster(lobby, players, hostName),
                      if (theme != null && !theme.isEmpty) ...[
                        const SizedBox(height: 24),
                        DailyThemeCard(
                          theme: theme,
                          onApply: isHost ? () => _queueSettings(settings.withFilterOf(theme.filter)) : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      // The pool settings scroll with the roster: on a phone
                      // they are taller than the space left under the code.
                      HextechPanel(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: isHost
                            ? LobbyFilters(
                                settings: settings,
                                seasonRange: lobby.seasonRange,
                                poolSize: lobby.poolSize,
                                classes: lobby.classes,
                                regions: lobby.regions,
                                onChanged: _queueSettings,
                              )
                            : LobbyFiltersSummary(settings: settings, poolSize: lobby.poolSize),
                      ),
                      const SizedBox(height: 16),
                      HextechPanel(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: isHost
                            ? LobbyRules(
                                settings: settings,
                                activePlayers: activeCount,
                                onChanged: _queueSettings,
                              )
                            : LobbyRulesSummary(settings: settings),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: isHost
                      ? _startButton(lobby, settings, activeCount)
                      : StatusNotice(
                          message: 'Waiting for $hostName to start the game',
                          tone: NoticeTone.info,
                          pulse: true,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _rosterHeader(int count, int spectators) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Row(
      children: [
        Expanded(
          child: Text(
            'SUMMONERS · $count${spectators > 0 ? ' · $spectators WATCHING' : ''}',
            style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
          ),
        ),
        Text(
          'min $_minimumPlayers',
          style: textTheme.bodySmall?.copyWith(color: hextech.textDisabled),
        ),
      ],
    );
  }

  /// The players who are here, then a dashed seat for each one still missing
  /// before the game can start.
  List<Widget> _roster(Lobby lobby, List<String> players, String hostName) {
    final rows = <Widget>[];
    for (var i = 0; i < players.length; i++) {
      final player = players[i];
      final isYou = player == widget.playerName;
      final spectating = lobby.isSpectator(player);
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        PlayerTile(
          key: ValueKey(player),
          name: player,
          isHost: player == hostName,
          isYou: isYou,
          isSpectator: spectating,
          connected: lobby.connected[player] ?? true,
          index: i,
          trailing: isYou
              ? HextechChip(
                  label: 'Sit out',
                  dense: true,
                  icon: Icons.visibility_outlined,
                  selected: spectating,
                  onSelected: _toggleSpectating,
                )
              : null,
        ),
      );
    }

    final openSeats = (_minimumPlayers - lobby.activePlayers.length).clamp(0, _minimumPlayers);
    for (var i = 0; i < openSeats; i++) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(const LobbyOpenSeat());
    }
    return rows;
  }

  Widget _startButton(Lobby lobby, GameSettings settings, int playerCount) {
    final missing = _minimumPlayers - playerCount;
    // poolSize is null until the server has a catalog; only a known-empty
    // pool blocks the button, the server rejects the rest.
    final emptyPacks = lobby.poolSize?.emptyPacks ?? const [];
    final tooManyImpostors = 2 * settings.impostors >= playerCount;
    final String? reason = missing > 0
        ? 'Need $missing more summoner${missing == 1 ? '' : 's'}'
        : emptyPacks.isNotEmpty
            ? 'No ${WordPack.label(emptyPacks.first).toLowerCase()} match the filters'
            : tooManyImpostors
                ? 'Too many undercovers for $playerCount players'
                : null;

    Widget start = HextechButton(
      label: 'Start game',
      busy: _isStarting,
      onPressed: reason == null && !_isStarting ? _startGame : null,
      disabledReason: reason,
    );

    if (_startShimmer > 0 && !Motion.reduced(context)) {
      start = start
          .animate(key: ValueKey('start-shimmer-$_startShimmer'))
          .shimmer(duration: 1200.ms, color: HextechColors.goldBright);
    }
    return start;
  }
}
