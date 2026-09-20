import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/eliminated_view.dart';
import 'package:undercoverleague/screens/game_screen.dart';
import 'package:undercoverleague/screens/last_guess_screen.dart';
import 'package:undercoverleague/screens/round_screen.dart';
import 'package:undercoverleague/screens/voting_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/reaction_bar.dart';
import 'package:undercoverleague/widgets/reaction_overlay.dart';
import 'package:undercoverleague/widgets/reveal_card.dart';
import 'package:undercoverleague/widgets/rules_info.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';

const _players = ['Ashe', 'Braum', 'Caitlyn', 'Draven'];

Lobby _lobby({
  String gamePhase = GamePhase.playing,
  bool roundFinished = false,
  List<String> alive = const ['Ashe', 'Braum', 'Caitlyn'],
  List<String> spectators = const [],
  int currentPlayerIndex = 0,
  int round = 2,
  int deadline = 0,
  String guesser = '',
  String myRole = Role.civilian,
  String? myWord = 'Ahri',
  bool myDecoy = false,
  GameSettings settings = const GameSettings(),
  List<Clue> clues = const [],
  String host = 'Ashe',
}) {
  return Lobby(
    id: 'ABCDE',
    host: host,
    players: _players,
    spectators: spectators,
    gameStarted: true,
    gamePhase: gamePhase,
    alivePlayers: alive,
    roundOrder: alive,
    currentPlayerIndex: currentPlayerIndex,
    roundFinished: roundFinished,
    round: round,
    deadline: deadline,
    votes: const {},
    rolesAcknowledged: const {},
    clues: clues,
    guesser: guesser,
    winner: null,
    lastEliminated: null,
    selectedPack: WordPack.champions,
    myRole: myRole,
    myWord: myWord,
    myIcon: 'assets/default_icon.jpg',
    myDecoy: myDecoy,
    roles: const {},
    selectedWord: null,
    settings: settings,
    connected: {for (final p in _players) p: true},
    version: 5,
  );
}

/// Hosts the shell over a lobby the connection already holds, animations
/// off so every phase body is at rest on the first pump.
Widget _host(Lobby lobby, String playerName) {
  GameConnection.instance.current = lobby;
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: GameScreen(lobbyId: lobby.id, playerName: playerName, hostName: 'Ashe'),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GameConnection.instance.current = null);

  setUp(() {
    // Tall enough that every panel of a phase is laid out at once.
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
  });

  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize());

  testWidgets('a describing round shows the round number, the timer and the clue field', (tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 42)).millisecondsSinceEpoch;
    await tester.pumpWidget(_host(
      _lobby(
        deadline: deadline,
        settings: const GameSettings(clueLog: true),
        clues: const [Clue(round: 1, player: 'Braum', text: 'Fox')],
      ),
      'Ashe',
    ));
    await tester.pump();

    expect(find.byType(RoundScreen), findsOneWidget);
    expect(find.text('ROUND 2 · DESCRIBING'), findsOneWidget);
    expect(find.byType(TurnTimer), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    // Clue log on: the current player types the clue, and everyone gets the log.
    expect(find.text('SUBMIT CLUE'), findsOneWidget);
    expect(find.text('END MY TURN'), findsNothing);
    expect(find.byType(ClueLog), findsOneWidget);
    expect(find.text('Fox'), findsOneWidget);
    // The peek card is docked, the overlay mounted, no reactions for the living.
    expect(find.byType(RevealCard), findsOneWidget);
    expect(find.byType(ReactionOverlay), findsOneWidget);
    expect(find.byType(ReactionBar), findsNothing);
    // Ashe hosts, so the End game action is there.
    expect(find.byTooltip('End game'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without the clue log the turn still ends with a tap and no log is drawn', (tester) async {
    await tester.pumpWidget(_host(_lobby(), 'Ashe'));
    await tester.pump();

    expect(find.text('END MY TURN'), findsOneWidget);
    expect(find.byType(ClueLog), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
  });

  testWidgets('host comes from the live view, not the constructor', (tester) async {
    await tester.pumpWidget(_host(_lobby(host: 'Braum'), 'Ashe'));
    await tester.pump();

    expect(find.byTooltip('End game'), findsNothing);
    // The rules sheet is for everyone, host or not.
    expect(find.byTooltip(rulesInfoTitle), findsOneWidget);
  });

  testWidgets('the info action opens the rules sheet for the running game', (tester) async {
    await tester.pumpWidget(_host(
      _lobby(roundFinished: true, settings: const GameSettings(undercovers: 2, decoyWord: true, turnSeconds: 30)),
      'Braum',
    ));
    await tester.pump();

    await tester.tap(find.byTooltip(rulesInfoTitle));
    await tester.pump();
    await tester.pump();

    expect(find.byType(RulesInfoContent), findsOneWidget);
    expect(find.text('2 Undercovers, the rest civilians'), findsOneWidget);
    expect(find.text('On: Undercovers get a look-alike word'), findsOneWidget);
    expect(find.text('Fixed order · 30 s per turn'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(RulesInfoContent), findsNothing);
    expect(find.byType(VotingScreen), findsOneWidget);
  });

  testWidgets('voting shows the ballot with the timer and the log', (tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 90)).millisecondsSinceEpoch;
    await tester.pumpWidget(_host(
      _lobby(roundFinished: true, deadline: deadline, settings: const GameSettings(clueLog: true)),
      'Braum',
    ));
    await tester.pump();

    expect(find.byType(VotingScreen), findsOneWidget);
    expect(find.text('ROUND 2 · VOTING'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byType(ClueLog), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the guesser gets the last-guess screen and the table waits', (tester) async {
    final caught = _lobby(
      gamePhase: GamePhase.lastGuess,
      alive: const ['Ashe', 'Caitlyn'],
      guesser: 'Braum',
      myRole: Role.mrWhite,
      myWord: null,
    );
    await tester.pumpWidget(_host(caught, 'Braum'));
    await tester.pump();
    expect(find.byType(LastGuessScreen), findsOneWidget);
    expect(find.text('Which champion was it?'), findsOneWidget);

    await tester.pumpWidget(_host(caught, 'Ashe'));
    await tester.pump();
    expect(find.byType(LastGuessScreen), findsNothing);
    expect(find.text('BRAUM WAS CAUGHT'), findsOneWidget);
    expect(find.text('Waiting for Braum to guess…'), findsOneWidget);
  });

  testWidgets('a spectator watches with the word, the strip and the reaction bar', (tester) async {
    await tester.pumpWidget(_host(
      _lobby(spectators: const ['Draven'], myRole: Role.spectator, myWord: 'Ahri'),
      'Draven',
    ));
    await tester.pump();

    expect(find.byType(EliminatedView), findsOneWidget);
    expect(find.text('SPECTATING'), findsOneWidget);
    expect(find.text('ELIMINATED'), findsNothing);
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('ROUND 2 · DESCRIBING'), findsOneWidget);
    expect(find.byType(ReactionBar), findsOneWidget);
    // No peek card for the bench: the word is already on the page.
    expect(find.byType(RevealCard), findsNothing);
  });

  testWidgets('an eliminated player gets the bench view with reactions', (tester) async {
    await tester.pumpWidget(_host(
      _lobby(alive: const ['Ashe', 'Caitlyn'], roundFinished: true),
      'Braum',
    ));
    await tester.pump();

    expect(find.byType(EliminatedView), findsOneWidget);
    expect(find.text('ELIMINATED'), findsOneWidget);
    expect(find.text('THE TABLE IS VOTING'), findsOneWidget);
    expect(find.byType(ReactionBar), findsOneWidget);
    expect(find.byType(VotingScreen), findsNothing);
  });
}
