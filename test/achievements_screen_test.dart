import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/achievements.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/achievements_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/achievement_badge.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';

Lobby _lobby({
  List<String> players = const ['Ashe', 'Braum', 'Caitlyn'],
  Map<String, List<String>> achievements = const {},
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
    achievements: achievements,
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
        child: AchievementsScreen(playerName: playerName),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GameConnection.instance.current = null);

  testWidgets('lists each player with their titles; the viewer starts open', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      _lobby(achievements: const {
        'Braum': [Achievements.survivor, Achievements.firstBlood],
        'Draven': [Achievements.veteran],
      }),
      'Braum',
    ));
    await tester.pump();

    expect(find.text('Lobby ABCDE · 3 of 10 titles unlocked'), findsOneWidget);

    // Seats first, then a past player who still holds a title.
    final panels = tester.widgetList<HextechExpander>(find.byType(HextechExpander)).toList();
    expect(panels.map((p) => p.title), ['Ashe', 'Braum', 'Caitlyn', 'Draven']);
    expect(panels.map((p) => p.initiallyExpanded), [false, true, false, false]);
    expect(panels[0].subtitle, 'No titles yet');
    expect(panels[1].subtitle, '2 titles · you');
    expect(panels[3].subtitle, '1 title · left the lobby');

    // Braum's panel is open: his badges, titles and descriptions are there.
    expect(find.text('Survivor'), findsOneWidget);
    expect(find.text('First Blood'), findsOneWidget);
    expect(find.text(Achievements.byId(Achievements.survivor).description), findsOneWidget);
    expect(find.byType(AchievementBadge), findsNWidgets(2));
    expect(find.text('Veteran'), findsNothing);

    // Opening Draven's shows his.
    await tester.tap(find.text('Draven'));
    await tester.pumpAndSettle();
    expect(find.text('Veteran'), findsOneWidget);
    expect(find.byType(AchievementBadge), findsNWidgets(3));

    // Ashe has none; her panel says how to get one.
    await tester.tap(find.text('Ashe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('to earn a title'), findsOneWidget);
  });

  testWidgets('the full table lights what was earned and locks the rest', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      _lobby(achievements: const {
        'Braum': [Achievements.survivor],
        'Caitlyn': [Achievements.survivor, Achievements.sharpEye],
      }),
      'Ashe',
    ));
    await tester.pump();

    await tester.tap(find.text('ALL TITLES'));
    await tester.pumpAndSettle();

    final badges = tester.widgetList<AchievementBadge>(find.byType(AchievementBadge)).toList();
    expect(badges.length, Achievements.all.length);
    final earned = {for (final b in badges) b.id: b.earned};
    expect(earned[Achievements.survivor], isTrue);
    expect(earned[Achievements.sharpEye], isTrue);
    expect(earned[Achievements.mindReader], isFalse);
    expect(earned.values.where((e) => e).length, 2);

    expect(find.text('Earned by Braum, Caitlyn'), findsOneWidget);
    expect(find.text('Earned by Caitlyn'), findsOneWidget);
    expect(find.text('Not yet earned'), findsNWidgets(Achievements.all.length - 2));
    // Locked badges carry a padlock.
    expect(find.byIcon(Icons.lock), findsNWidgets(Achievements.all.length - 2));
  });

  testWidgets('every known achievement has its own icon', (tester) async {
    final icons = {for (final a in Achievements.all) AchievementBadge.iconFor(a.id)};
    expect(icons.length, Achievements.all.length);
    expect(icons, isNot(contains(AchievementBadge.iconFor('something_new'))));
  });
}
