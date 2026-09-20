import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/screens/lobby_screen.dart';
import 'package:undercoverleague/services/daily_theme_service.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/home_wordmark.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_route.dart';
import 'package:undercoverleague/widgets/hextech_scaffold.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/hextech_text_field.dart';
import 'package:undercoverleague/widgets/home_theme_banner.dart';
import 'package:undercoverleague/widgets/motion_size.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/upper_case_text_formatter.dart';

class HomeScreen extends StatefulWidget {
  /// Where "Today's theme" comes from; defaults to the server's `/daily`.
  /// Injectable so tests can hand the screen a theme, or none.
  final Future<DailyTheme?> Function()? loadDailyTheme;

  const HomeScreen({super.key, this.loadDailyTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The hero entrance is a welcome, not a transition: it plays on the first
  /// home screen of the session and never again, so coming back from a lobby
  /// does not replay it.
  static bool _entrancePlayed = false;

  /// Two buttons wide enough to sit side by side; below this they stack.
  static const double _sideBySideWidth = 420;

  static const Duration _noticeLifetime = Duration(seconds: 6);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lobbyIdController = TextEditingController();
  final LobbyService _lobbyService = LobbyService();
  bool _busy = false;

  /// Which of the two buttons shows the spinner while [_busy]; display only.
  String? _busyAction;

  /// Inline validation. Server outcomes land on whichever field the player can
  /// actually do something about, rather than in a snackbar they must reread.
  String? _nameError;
  String? _lobbyError;

  /// Why the last session ended, shown at the top of the panel.
  String? _closeNotice;
  NoticeTone _closeNoticeTone = NoticeTone.warning;
  Timer? _closeNoticeTimer;

  bool _playEntrance = false;
  bool _focusNameOnOpen = false;

  /// Today's theme once it has arrived; nothing is shown while it loads and
  /// nothing at all if the server cannot say.
  DailyTheme? _dailyTheme;

  @override
  void initState() {
    super.initState();
    _playEntrance = !_entrancePlayed;
    _entrancePlayed = true;

    // Fire and forget: the banner is a nicety, the form never waits for it.
    (widget.loadDailyTheme ?? DailyThemeService.fetch)().then(
      (theme) {
        if (mounted && theme != null) setState(() => _dailyTheme = theme);
      },
      onError: (Object e) => debugPrint('Daily theme unavailable: $e'),
    );

    // Shared link: `…/?lobby=ABC12` pre-fills the code so the player only has
    // to name themselves.
    if (kIsWeb) {
      final code = Uri.base.queryParameters['lobby'] ?? '';
      if (code.isNotEmpty) {
        _lobbyIdController.text = LobbyService.normalizeLobbyId(code);
        _focusNameOnOpen = true;
      }
    }

    _nameController.addListener(() => _clearError(name: true));
    _lobbyIdController.addListener(() => _clearError(name: false));

    // Coming back here after the session ended elsewhere: say why, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (GameConnection.instance.takeCloseReason()) {
        case 'closed':
          _showCloseNotice('The host closed the lobby.');
        case 'expired':
          _showCloseNotice('Your seat in the lobby is gone. Join again with the same name to get it back.');
        case 'unreachable':
          _showCloseNotice('Lost the connection to the server.', tone: NoticeTone.danger);
      }
      // HextechTextField owns its focus node, so the first field is focused by
      // walking the traversal order rather than by an `autofocus` flag.
      if (_focusNameOnOpen && mounted) FocusScope.of(context).nextFocus();
    });
  }

  @override
  void dispose() {
    _closeNoticeTimer?.cancel();
    _nameController.dispose();
    _lobbyIdController.dispose();
    super.dispose();
  }

  void _clearError({required bool name}) {
    if (name ? _nameError == null : _lobbyError == null) return;
    setState(() {
      if (name) {
        _nameError = null;
      } else {
        _lobbyError = null;
      }
    });
  }

  void _showMessage(String message, {SnackTone tone = SnackTone.warning}) {
    if (!mounted) return;
    showHextechSnack(context, message, tone: tone);
  }

  /// Shows the "why you are back here" notice and starts its countdown. It can
  /// also be dismissed by hand; either way the timer is cancelled in [dispose].
  void _showCloseNotice(String message, {NoticeTone tone = NoticeTone.warning}) {
    if (!mounted) return;
    setState(() {
      _closeNotice = message;
      _closeNoticeTone = tone;
    });
    _closeNoticeTimer?.cancel();
    _closeNoticeTimer = Timer(_noticeLifetime, _dismissCloseNotice);
  }

  void _dismissCloseNotice() {
    _closeNoticeTimer?.cancel();
    if (!mounted || _closeNotice == null) return;
    setState(() => _closeNotice = null);
  }

  /// Runs a lobby command once both fields are usable.
  ///
  /// [requireCode] is false for Create: an empty code asks the server for a
  /// generated one. Everything a player can fix is reported on the field that
  /// is wrong; only a failure to reach the server at all becomes a snackbar.
  Future<void> _run(
    Future<void> Function(String name, String lobbyId) action, {
    required bool requireCode,
  }) async {
    if (_busy) return;

    final name = _nameController.text.trim();
    final lobbyId = LobbyService.normalizeLobbyId(_lobbyIdController.text);
    final nameError = LobbyService.validatePlayerName(name);
    final lobbyError =
        requireCode || lobbyId.isNotEmpty ? LobbyService.validateLobbyId(lobbyId) : null;
    if (nameError != null || lobbyError != null) {
      setState(() {
        _nameError = nameError;
        _lobbyError = lobbyError;
      });
      return;
    }

    setState(() {
      _busy = true;
      _nameError = null;
      _lobbyError = null;
    });
    try {
      await action(name, lobbyId);
    } on GameError catch (e) {
      // The server's own validation of the code (including "a code is still
      // required" until generated codes land) belongs on the code field.
      debugPrint('Lobby action rejected: $e');
      if (e.code == 'invalid') {
        _setLobbyError(e.message.isEmpty ? 'That lobby code is not valid.' : e.message);
      } else {
        _showMessage('Could not reach the game server. Please try again.', tone: SnackTone.error);
      }
    } catch (e) {
      debugPrint('Lobby action failed: $e');
      _showMessage('Could not reach the game server. Please try again.', tone: SnackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setNameError(String message) {
    if (!mounted) return;
    setState(() => _nameError = message);
  }

  void _setLobbyError(String message) {
    if (!mounted) return;
    setState(() => _lobbyError = message);
  }

  Future<void> _createLobby() {
    _busyAction = 'create';
    return _run((name, lobbyId) async {
      final created = await _lobbyService.createLobby(name, lobbyId);
      if (!created) {
        _setLobbyError('That code is taken. If the lobby is yours, use Join with the same name.');
        return;
      }
      // With a blank code the server picks one; it comes back on the session.
      _navigateToLobby(name, GameConnection.instance.session?.lobbyId ?? lobbyId, isHost: true);
    }, requireCode: false);
  }

  Future<void> _joinLobby() {
    _busyAction = 'join';
    return _run((name, lobbyId) async {
      final result = await _lobbyService.joinLobby(lobbyId, name);
      switch (result) {
        case JoinResult.ok:
          _navigateToLobby(name, GameConnection.instance.session?.lobbyId ?? lobbyId, isHost: false);
        case JoinResult.notFound:
          _setLobbyError('No lobby with that code. Check it with the host.');
        case JoinResult.inProgress:
          _setLobbyError('That lobby has a game in progress. Try again when it is over.');
        case JoinResult.nameTaken:
          _setNameError('Someone in that lobby already has that name.');
      }
    }, requireCode: true);
  }

  void _navigateToLobby(String name, String lobbyId, {required bool isHost}) {
    if (!mounted) return;
    Navigator.push(
      context,
      hextechRoute(LobbyScreen(lobbyId: lobbyId, playerName: name, isHost: isHost)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final reduced = Motion.reduced(context);

    Widget hero = const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: HomeWordmark(),
    );

    Widget panel = HextechPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _closeNoticeSection(),
          HextechTextField(
            controller: _nameController,
            label: 'Summoner name',
            prefixIcon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            textInputAction: TextInputAction.next,
            errorText: _nameError,
          ),
          const SizedBox(height: 16),
          HextechTextField(
            controller: _lobbyIdController,
            label: 'Lobby code',
            hint: 'Leave empty to get a random code',
            prefixIcon: Icons.tag,
            maxLength: 64,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [UpperCaseTextFormatter()],
            textInputAction: TextInputAction.go,
            errorText: _lobbyError,
            onSubmitted: (_) => _busy ? null : _joinLobby(),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final create = HextechButton(
                label: 'Create lobby',
                busy: _busy && _busyAction == 'create',
                onPressed: _busy ? null : _createLobby,
              );
              final join = HextechButton(
                label: 'Join lobby',
                variant: HextechButtonVariant.secondary,
                busy: _busy && _busyAction == 'join',
                onPressed: _busy ? null : _joinLobby,
              );
              if (constraints.maxWidth >= _sideBySideWidth) {
                return Row(
                  children: [
                    Expanded(child: create),
                    const SizedBox(width: 12),
                    Expanded(child: join),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [create, const SizedBox(height: 12), join],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '3 or more summoners. Share the code with your friends.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
          ),
        ],
      ),
    );

    if (_playEntrance && !reduced) {
      hero = hero
          .animate()
          .fadeIn(duration: Motion.slow, curve: Motion.enter)
          .slideY(begin: 0.18, end: 0, duration: Motion.slow, curve: Motion.enter);
      panel = panel
          .animate(delay: 150.ms)
          .fadeIn(duration: Motion.slow, curve: Motion.enter)
          .slideY(begin: 0.10, end: 0, duration: Motion.slow, curve: Motion.enter);
    }

    return HextechScaffold(
      // The wordmark below carries the app's name; the header names the task.
      title: 'Enter the rift',
      showConnection: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: 28),
            _dailyThemeSection(),
            panel,
          ],
        ),
      ),
    );
  }

  /// "Today's theme" under the wordmark. It takes no room until the server
  /// has answered, then fades in and pushes the form down gently.
  Widget _dailyThemeSection() {
    final theme = _dailyTheme;
    final reduced = Motion.reduced(context);
    Widget banner = theme == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: HomeThemeBanner(theme: theme),
          );
    if (theme != null && !reduced) {
      banner = banner.animate().fadeIn(duration: Motion.slow, curve: Motion.enter);
    }
    return MotionSize(child: banner);
  }

  /// The close-reason notice, with the room it takes up animated away once it
  /// is gone so the fields do not jump.
  Widget _closeNoticeSection() {
    final notice = _closeNotice;
    return MotionSize(
      child: notice == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatusNotice(message: notice, tone: _closeNoticeTone),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: context.hextech.textSecondary,
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: _dismissCloseNotice,
                  ),
                ],
              ),
            ),
    );
  }
}
