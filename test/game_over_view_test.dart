import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/game_over_view.dart';
import 'package:undercoverleague/theme/app_theme.dart';

Lobby _gameOver({required String myRole, String winner = 'Civilians'}) {
  return Lobby(
    id: 'ABCDE',
    host: 'Ashe',
    players: const ['Ashe', 'Braum', 'Caitlyn'],
    gameStarted: true,
    gamePhase: 'gameOver',
    alivePlayers: const ['Ashe', 'Caitlyn'],
    roundOrder: const ['Ashe', 'Braum', 'Caitlyn'],
    currentPlayerIndex: 0,
    roundFinished: true,
    votes: const {},
    rolesAcknowledged: const {},
    winner: winner,
    lastEliminated: 'Braum',
    selectedIsChampion: true,
    myRole: myRole,
    myWord: 'Ahri',
    myIcon: 'assets/champions/ahri.jpg',
    roles: const {'Ashe': 'Civilian', 'Braum': 'Undercover', 'Caitlyn': 'Civilian'},
    selectedWord: 'Ahri',
    connected: const {'Ashe': true, 'Braum': true, 'Caitlyn': true},
    version: 7,
  );
}

/// Hosts the view. [animate] off — the default — disables animations so every
/// step of the sequenced reveal is already on screen at the first pump.
Widget _host(Lobby lobby, String playerName, {bool animate = false}) {
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: !animate),
        child: Scaffold(
          body: GameOverView(
            lobby: lobby,
            playerName: playerName,
            isHost: playerName == lobby.host,
            onBackToLobby: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a civilian on the winning side sees a victory, the word and the Undercover',
      (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian'), 'Ashe'));
    await tester.pump();

    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('DEFEAT'), findsNothing);
    expect(find.text('Civilians win'), findsOneWidget);

    // The word, with the frame's eyebrow saying which kind it was.
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('CHAMPION'), findsOneWidget);

    // Named in the Undercover panel and again in the roster.
    expect(find.text('Braum'), findsNWidgets(2));
    expect(find.text('UNDERCOVER'), findsNWidgets(2));

    // The host is the one who can restart.
    expect(find.text('BACK TO LOBBY'), findsOneWidget);
  });

  testWidgets('the Undercover sees a defeat when the Civilians win', (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Undercover'), 'Braum'));
    await tester.pump();

    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    expect(find.text('Civilians win'), findsOneWidget);

    // Not the host: nothing to press, just the wait.
    expect(find.text('BACK TO LOBBY'), findsNothing);
    expect(find.textContaining('Waiting for the host'), findsOneWidget);
  });

  testWidgets('the Undercover winning is a victory for them and a defeat for a civilian',
      (tester) async {
    await tester.pumpWidget(
      _host(_gameOver(myRole: 'Undercover', winner: 'Undercover'), 'Braum'),
    );
    await tester.pump();
    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('The Undercover wins'), findsOneWidget);

    await tester.pumpWidget(
      _host(_gameOver(myRole: 'Civilian', winner: 'Undercover'), 'Ashe'),
    );
    await tester.pump();
    expect(find.text('DEFEAT'), findsOneWidget);
  });

  testWidgets('the sequenced reveal arrives step by step and lands complete', (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian'), 'Ashe', animate: true));
    await tester.pump();

    double footerOpacity() => tester
        .widgetList<FadeTransition>(
          find.ancestor(of: find.text('BACK TO LOBBY'), matching: find.byType(FadeTransition)),
        )
        .map((f) => f.opacity.value)
        .fold<double>(1, (a, b) => a < b ? a : b);

    // The footer is the last beat (1400 ms); it is still held back at zero.
    expect(footerOpacity(), 0);

    // Past every beat plus the longest step duration, a frame at a time.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('BACK TO LOBBY'), findsOneWidget);
    expect(footerOpacity(), 1);
  });
}
