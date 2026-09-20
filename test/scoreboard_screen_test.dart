import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/scoreboard_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/score_row.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

Lobby _lobby({
  List<String> players = const ['Ashe', 'Braum', 'Caitlyn'],
  Map<String, int> scores = const {},
  int gamesPlayed = 0,
  Map<String, PlayerStats> stats = const {},
}) {
  return Lobby(
    id: 'ABCDE',
    host: 'Ashe',
    players: players,
    gameStarted: false,
    gamePhase: GamePhase.lobby,
    alivePlayers: const [],
    roundOrder: const [],
    currentPlayerIndex: 0,
    roundFinished: false,
    votes: const {},
    rolesAcknowledged: const {},
    winner: null,
    lastEliminated: null,
    myRole: Role.spectator,
    myWord: null,
    myIcon: 'assets/default_icon.jpg',
    roles: const {},
    selectedWord: null,
    scores: scores,
    gamesPlayed: gamesPlayed,
    stats: stats,
    connected: {for (final p in players) p: true},
    version: 1,
  );
}

Widget _host(Lobby lobby, String playerName) {
  GameConnection.instance.current = lobby;
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: ScoreboardScreen(playerName: playerName),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GameConnection.instance.current = null);

  group('rankScores', () {
    test('sorts by points, then name, and shares ranks on ties', () {
      final ranked = rankScores({'braum': 2, 'Ashe': 5, 'Caitlyn': 2, 'Draven': 0});
      expect(ranked, const [
        ScoreboardEntry(name: 'Ashe', points: 5, rank: 1),
        ScoreboardEntry(name: 'braum', points: 2, rank: 2),
        ScoreboardEntry(name: 'Caitlyn', points: 2, rank: 2),
        ScoreboardEntry(name: 'Draven', points: 0, rank: 4),
      ]);
    });

    test('is empty for an empty table', () {
      expect(rankScores(const {}), isEmpty);
    });
  });

  test('ScoreRow describes stats in words', () {
    expect(
      ScoreRow.describe(const PlayerStats(games: 3, impostorGames: 2, civilianSurvivals: 1)),
      '3 games · 2 as impostor · 1 survival',
    );
    expect(
      ScoreRow.describe(const PlayerStats(games: 1, impostorGames: 0, civilianSurvivals: 2)),
      '1 game · 0 as impostor · 2 survivals',
    );
    expect(ScoreRow.describe(null), isNull);
  });

  testWidgets('shows the ranked table with medals, the host, the viewer and who left', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      _lobby(
        scores: const {'Ashe': 4, 'Braum': 6, 'Caitlyn': 4, 'Draven': 1},
        gamesPlayed: 3,
        stats: const {
          'Braum': PlayerStats(games: 3, impostorGames: 2, civilianSurvivals: 1),
        },
      ),
      'Caitlyn',
    ));
    await tester.pump();

    expect(find.text('Lobby ABCDE · 3 games played'), findsOneWidget);

    final rows = tester.widgetList<ScoreRow>(find.byType(ScoreRow)).toList();
    expect(rows.map((r) => r.name), ['Braum', 'Ashe', 'Caitlyn', 'Draven']);
    expect(rows.map((r) => r.rank), [1, 2, 2, 4]);
    expect(rows.map((r) => r.points), [6, 4, 4, 1]);
    expect(rows.map((r) => r.isHost), [false, true, false, false]);
    expect(rows.map((r) => r.isYou), [false, false, true, false]);
    // Draven has a row but no seat any more.
    expect(rows.map((r) => r.left), [false, false, false, true]);
    expect(find.text('LEFT'), findsOneWidget);
    expect(find.text('(you)'), findsOneWidget);
    expect(find.text('3 games · 2 as impostor · 1 survival'), findsOneWidget);

    // Rows are laid out in rank order, top to bottom.
    final tops = [for (final r in rows) tester.getTopLeft(find.byWidget(r)).dy];
    expect(tops, orderedEquals([...tops]..sort()));

    expect(ScoreRow.medalColor(1), isNotNull);
    expect(ScoreRow.medalColor(3), isNotNull);
    expect(ScoreRow.medalColor(4), isNull);
    expect(find.byType(StatusNotice), findsNothing);
    expect(find.byType(HextechExpander), findsOneWidget);
  });

  testWidgets('before the first game it explains the scoring instead', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(), 'Ashe'));
    await tester.pump();

    expect(find.text('Lobby ABCDE · 0 games played'), findsOneWidget);
    expect(find.byType(ScoreRow), findsNothing);
    expect(find.byType(StatusNotice), findsOneWidget);
    expect(find.textContaining('No games played yet'), findsOneWidget);
    expect(find.textContaining('Civilians win: every civilian +1'), findsOneWidget);

    // The rules panel is folded until asked for.
    expect(find.text('How scoring works'), findsOneWidget);
    expect(find.text('AT GAME OVER'), findsNothing);
    await tester.tap(find.text('How scoring works'));
    await tester.pumpAndSettle();
    expect(find.text('AT GAME OVER'), findsOneWidget);
    expect(find.text(scoringRules.last), findsOneWidget);
  });

  testWidgets('says so when there is no lobby any more', (tester) async {
    GameConnection.instance.current = null;
    await tester.pumpWidget(MaterialApp(
      theme: hextechTheme(),
      home: const ScoreboardScreen(playerName: 'Ashe'),
    ));
    await tester.pump();
    expect(find.text('The lobby is closed.'), findsOneWidget);
  });
}
