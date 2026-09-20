import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/lobby_screen.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/daily_theme_card.dart';
import 'package:undercoverleague/widgets/hextech_menu.dart';
import 'package:undercoverleague/widgets/lobby_filters.dart';
import 'package:undercoverleague/widgets/lobby_rules.dart';
import 'package:undercoverleague/widgets/player_tile.dart';
import 'package:undercoverleague/widgets/rules_info.dart';

Lobby _lobby({
  List<String> players = const ['Ashe', 'Braum', 'Caitlyn', 'Draven', 'Ezreal'],
  List<String> spectators = const [],
  GameSettings settings = const GameSettings(champSeasons: (1, 16), itemSeasons: (3, 16)),
}) {
  return Lobby(
    id: 'ABCDE',
    host: 'Ashe',
    players: players,
    spectators: spectators,
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
    settings: settings,
    poolSize: const PoolSize({'champions': 170, 'items': 210}),
    seasonRange: const SeasonRange(champions: (1, 16), items: (3, 16)),
    classes: const ['Assassin', 'Fighter', 'Mage', 'Marksman', 'Support', 'Tank'],
    regions: const ['Demacia', 'Ionia', 'Shurima'],
    dailyTheme: const DailyTheme(
      id: 'shurima',
      title: 'Shurima Day',
      description: 'Only champions from Shurima and their abilities.',
      filter: GameSettings(packs: {WordPack.champions, WordPack.abilities}, champRegions: {'Shurima'}),
    ),
    connected: {for (final p in players) p: true},
    version: 3,
  );
}

/// Hosts the screen over a lobby that the connection already holds, with
/// animations off so every panel is at rest on the first pump.
Widget _host(Lobby lobby, String playerName) {
  GameConnection.instance.current = lobby;
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: LobbyScreen(lobbyId: lobby.id, playerName: playerName, isHost: playerName == lobby.host),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => GameConnection.instance.current = null);

  testWidgets('the host sees the pool controls, the rules and the theme', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(), 'Ashe'));
    await tester.pump();

    expect(find.byType(LobbyFilters), findsOneWidget);
    expect(find.byType(LobbyRules), findsOneWidget);
    expect(find.text('WORD PACKS'), findsOneWidget);
    expect(find.textContaining('CHAMPIONS'), findsWidgets);
    expect(find.text('ITEM TIERS'), findsOneWidget);
    expect(find.text('CHAMPION FILTERS'), findsOneWidget);
    expect(find.text('RULES'), findsOneWidget);
    expect(find.text('Undercovers'), findsOneWidget);
    expect(find.text('Decoy word'), findsOneWidget);
    expect(find.text('Mixed mode (Mr. White)'), findsOneWidget);
    expect(find.text('Random turn order'), findsOneWidget);
    expect(find.text('Turn timer'), findsOneWidget);
    expect(find.text('Clue log'), findsOneWidget);
    expect(find.text('Rotate host after each game'), findsOneWidget);
    expect(find.byType(DailyThemeCard), findsOneWidget);
    expect(find.text('Shurima Day'), findsOneWidget);
    expect(find.text('APPLY'), findsOneWidget);
    expect(find.text('SIT OUT'), findsOneWidget);
    expect(find.text('START GAME'), findsOneWidget);
    expect(find.byType(PlayerTile), findsNWidgets(5));
  });

  testWidgets('everyone else sees a read-only summary and waits for the host', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(spectators: const ['Draven']), 'Braum'));
    await tester.pump();

    expect(find.byType(LobbyFilters), findsNothing);
    expect(find.byType(LobbyFiltersSummary), findsOneWidget);
    expect(find.byType(LobbyRulesSummary), findsOneWidget);
    expect(find.text('APPLY'), findsNothing);
    expect(find.text('START GAME'), findsNothing);
    expect(find.text('Waiting for Ashe to start the game'), findsOneWidget);
    // Spectators are counted apart from the summoners who will play.
    expect(find.text('SUMMONERS · 4 · 1 WATCHING'), findsOneWidget);
    expect(find.text('SPECTATING'), findsOneWidget);
    expect(find.text('SIT OUT'), findsOneWidget);
  });

  testWidgets('the host gets a kebab on every other row that offers to remove them', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(), 'Ashe'));
    await tester.pump();

    // Four other players, no menu on the host's own row.
    expect(find.byWidgetPredicate((w) => w is HextechMenuButton), findsNWidgets(4));
    expect(find.byTooltip('Options for Ashe'), findsNothing);

    await tester.tap(find.byTooltip('Options for Draven'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from lobby'), findsOneWidget);

    await tester.tap(find.text('Remove from lobby'));
    await tester.pumpAndSettle();
    expect(find.text('REMOVE PLAYER'), findsOneWidget);
    expect(find.textContaining('Remove Draven from the lobby?'), findsOneWidget);
  });

  testWidgets('non-hosts get no kebab', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(), 'Braum'));
    await tester.pump();

    expect(find.byWidgetPredicate((w) => w is HextechMenuButton), findsNothing);
  });

  testWidgets('the info action opens the rules sheet for the lobby\'s settings', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      _lobby(settings: const GameSettings(champSeasons: (1, 16), itemSeasons: (3, 16), mrWhites: 1, decoyWord: true)),
      'Ashe',
    ));
    await tester.pump();

    expect(find.byTooltip(rulesInfoTitle), findsOneWidget);
    await tester.tap(find.byTooltip(rulesInfoTitle));
    await tester.pump();
    await tester.pump();

    expect(find.byType(RulesInfoContent), findsOneWidget);
    expect(find.text('HOW THIS LOBBY PLAYS'), findsOneWidget);
    expect(find.text('1 Undercover, 1 Mr. White, the rest civilians'), findsOneWidget);
    expect(find.text('On: Undercovers get a look-alike word'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(RulesInfoContent), findsNothing);

    // The decoy row's own "i" lands straight on the decoy section.
    await tester.tap(find.byTooltip('About Decoy word'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('told a different but similar word'), findsOneWidget);
  });

  testWidgets('non-hosts get the info button beside the rules summary', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_lobby(), 'Braum'));
    await tester.pump();

    // One in the header, one on the summary panel.
    expect(find.byTooltip(rulesInfoTitle), findsNWidgets(2));
    await tester.tap(find.byTooltip(rulesInfoTitle).last);
    await tester.pump();
    await tester.pump();
    expect(find.byType(RulesInfoContent), findsOneWidget);
    expect(find.text('Off: Undercovers get no word'), findsOneWidget);
  });

  testWidgets('the impostor steppers respect the player count', (tester) async {
    GameSettings? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: hextechTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: LobbyRules(
                settings: changed ?? const GameSettings(),
                activePlayers: 5,
                onChanged: (s) => setState(() => changed = s),
              ),
            ),
          ),
        ),
      ),
    );

    // Five players allow two impostors: one more Undercover, then no more.
    await tester.tap(find.byTooltip('More Undercovers'));
    await tester.pump();
    expect(changed!.undercovers, 2);
    await tester.tap(find.byTooltip('More Undercovers'));
    await tester.pump();
    expect(changed!.undercovers, 2);

    // Back to one, then mixed mode takes the second slot and forces decoys.
    await tester.tap(find.byTooltip('Fewer Undercovers'));
    await tester.pump();
    expect(changed!.undercovers, 1);
    await tester.tap(find.text('Mixed mode (Mr. White)'));
    await tester.pump();
    expect(changed!.mrWhites, 1);
    expect(changed!.decoyWord, isTrue);
    expect(find.text('Mr. Whites'), findsOneWidget);

    await tester.tap(find.text('60 S'));
    await tester.pump();
    expect(changed!.turnSeconds, 60);
  });
}
