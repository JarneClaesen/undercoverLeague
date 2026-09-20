import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/game_screen.dart';
import 'package:undercoverleague/screens/home_screen.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_dialog.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_route.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/lobby_code_panel.dart';
import 'package:undercoverleague/widgets/lobby_open_seat.dart';
import 'package:undercoverleague/widgets/lobby_pool_toggles.dart';
import 'package:undercoverleague/widgets/player_tile.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

class LobbyScreen extends StatefulWidget {
  final String lobbyId;
  final String playerName;
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
  /// The game cannot start below this; the roster shows the gap until then.
  static const int _minimumPlayers = 3;

  final LobbyService _lobbyService = LobbyService();
  bool _isLeaving = false;
  bool _isStarting = false;
  bool _inGame = false;
  bool useChampions = true;
  bool useItems = true;

  /// Roster size at the previous build, so the moment the lobby becomes
  /// startable can be caught and pointed at exactly once.
  int _lastPlayerCount = 0;
  int _startShimmer = 0;

  @override
  void dispose() {
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
      message: widget.isHost
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
      _lobbyService.startGame(useChampions: useChampions, useItems: useItems);
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showLeaveConfirmationDialog();
      },
      child: HextechScaffold(
        title: 'Lobby',
        actions: [
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
            final players = List<String>.from(lobby.players)
              ..remove(hostName)
              ..insert(0, hostName);

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

            _trackPlayerCount(players.length);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      LobbyCodePanel(lobbyId: widget.lobbyId),
                      const SizedBox(height: 24),
                      _rosterHeader(players.length),
                      const SizedBox(height: 12),
                      ..._roster(lobby, players, hostName),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: widget.isHost
                      ? _hostControls(players.length)
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

  Widget _rosterHeader(int count) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Row(
      children: [
        Expanded(
          child: Text(
            'SUMMONERS · $count',
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
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(
        PlayerTile(
          key: ValueKey(player),
          name: player,
          isHost: player == hostName,
          isYou: player == widget.playerName,
          connected: lobby.connected[player] ?? true,
          index: i,
        ),
      );
    }

    final openSeats = (_minimumPlayers - players.length).clamp(0, _minimumPlayers);
    for (var i = 0; i < openSeats; i++) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(const LobbyOpenSeat());
    }
    return rows;
  }

  Widget _hostControls(int playerCount) {
    final missing = _minimumPlayers - playerCount;

    Widget start = HextechButton(
      label: 'Start game',
      busy: _isStarting,
      onPressed: playerCount >= _minimumPlayers && !_isStarting ? _startGame : null,
      disabledReason: missing > 0
          ? 'Need $missing more summoner${missing == 1 ? '' : 's'}'
          : null,
    );

    if (_startShimmer > 0 && !Motion.reduced(context)) {
      start = start
          .animate(key: ValueKey('start-shimmer-$_startShimmer'))
          .shimmer(duration: 1200.ms, color: HextechColors.goldBright);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HextechPanel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: LobbyPoolToggles(
            useChampions: useChampions,
            useItems: useItems,
            onChanged: (champions, items) => setState(() {
              useChampions = champions;
              useItems = items;
            }),
          ),
        ),
        const SizedBox(height: 16),
        start,
      ],
    );
  }
}
