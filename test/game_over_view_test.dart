import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/game_over_view.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/game_over_portrait.dart';

Lobby _gameOver({
  required String myRole,
  String winner = 'Civilians',
  Map<String, String> roles = const {'Ashe': 'Civilian', 'Braum': 'Undercover', 'Caitlyn': 'Civilian'},
  List<String> alive = const ['Ashe', 'Caitlyn'],
}) {
  return Lobby(
    id: 'ABCDE',
    host: 'Ashe',
    players: roles.keys.toList(),
    gameStarted: true,
    gamePhase: 'gameOver',
    alivePlayers: alive,
    roundOrder: roles.keys.toList(),
    currentPlayerIndex: 0,
    roundFinished: true,
    votes: const {},
    rolesAcknowledged: const {},
    winner: winner,
    lastEliminated: 'Braum',
    selectedIsChampion: true,
    myRole: myRole,
    myWord: 'Ahri',
    myIcon: 'assets/default_icon.jpg',
    roles: roles,
    selectedWord: 'Ahri',
    connected: {for (final name in roles.keys) name: true},
    version: 7,
  );
}

/// Hosts the view. [animate] off — the default — disables animations so the
/// whole reveal is already at rest on the first pump.
Widget _host(
  Lobby lobby,
  String playerName, {
  bool animate = false,
  String? winReason,
  String? decoyWord,
  ({String player, String word, bool correct})? lastGuess,
  VoidCallback? onPlayAgain,
  VoidCallback? onBackToLobby,
}) {
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
            onBackToLobby: onBackToLobby ?? () {},
            winReason: winReason,
            decoyWord: decoyWord,
            lastGuess: lastGuess,
            onPlayAgain: onPlayAgain,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('with reduced motion every role and the winner are on screen at once', (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian'), 'Ashe'));
    await tester.pump();

    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('DEFEAT'), findsNothing);
    expect(find.text('CIVILIANS WIN'), findsOneWidget);
    // No reason from the server: derived from the winner.
    expect(find.text('The Undercover was voted out.'), findsOneWidget);

    // The word, with the frame's eyebrow saying which kind it was.
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('CHAMPION'), findsOneWidget);

    // One portrait per seat, each naming its role.
    expect(find.byType(GameOverPortrait), findsNWidgets(3));
    expect(find.text('Braum'), findsOneWidget);
    expect(find.text('UNDERCOVER'), findsOneWidget);
    expect(find.text('CIVILIAN'), findsNWidgets(2));
    expect(find.text('ELIMINATED'), findsOneWidget);
    // An Undercover without a decoy held nothing.
    expect(find.text('No word'), findsOneWidget);

    // The host gets both actions.
    expect(find.text('PLAY AGAIN'), findsOneWidget);
    expect(find.text('BACK TO LOBBY'), findsOneWidget);
  });

  testWidgets('the Undercover sees a defeat and, as a guest, only the wait', (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Undercover'), 'Braum'));
    await tester.pump();

    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    expect(find.text('CIVILIANS WIN'), findsOneWidget);

    expect(find.text('PLAY AGAIN'), findsNothing);
    expect(find.text('BACK TO LOBBY'), findsNothing);
    expect(find.textContaining('Waiting for the host'), findsOneWidget);
  });

  testWidgets('the impostors winning is their victory and a civilian defeat', (tester) async {
    await tester.pumpWidget(
      _host(
        _gameOver(myRole: 'Undercover', winner: 'Undercover'),
        'Braum',
        winReason: 'outnumbered',
      ),
    );
    await tester.pump();
    expect(find.text('VICTORY'), findsOneWidget);
    expect(find.text('UNDERCOVER WINS'), findsOneWidget);
    expect(find.text('The impostors outnumber the civilians.'), findsOneWidget);

    await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian', winner: 'Undercover'), 'Ashe'));
    await tester.pump();
    expect(find.text('DEFEAT'), findsOneWidget);
  });

  testWidgets('Mr. White is unmasked with no word, the decoy is shown, and the guess is credited', (
    tester,
  ) async {
    final lobby = _gameOver(
      myRole: 'Civilian',
      winner: 'MrWhite',
      roles: const {'Ashe': 'Civilian', 'Braum': 'Undercover', 'Caitlyn': 'Civilian', 'Darius': 'MrWhite'},
      alive: const ['Ashe', 'Braum', 'Caitlyn'],
    );
    await tester.pumpWidget(
      _host(
        lobby,
        'Ashe',
        winReason: 'guess',
        decoyWord: 'Sona',
        lastGuess: (player: 'Darius', word: 'Ahri', correct: true),
      ),
    );
    await tester.pump();

    expect(find.text('MR. WHITE WINS'), findsOneWidget);
    expect(find.text('Darius guessed the word: Ahri.'), findsOneWidget);
    expect(find.text('MR. WHITE'), findsOneWidget);
    expect(find.text('UNDERCOVER'), findsOneWidget);
    expect(find.text('“Sona”'), findsOneWidget);
    expect(find.text('No word'), findsOneWidget);
    expect(find.text('DEFEAT'), findsOneWidget);
  });

  testWidgets('a spectator is shown the result without a side', (tester) async {
    await tester.pumpWidget(_host(_gameOver(myRole: 'Spectator'), 'Zoe'));
    await tester.pump();

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('VICTORY'), findsNothing);
    expect(find.text('DEFEAT'), findsNothing);
    expect(find.text('CIVILIANS WIN'), findsOneWidget);
  });

  testWidgets('Play again prefers its own callback and falls back to Back to lobby', (tester) async {
    var again = 0;
    var back = 0;
    await tester.pumpWidget(
      _host(
        _gameOver(myRole: 'Civilian'),
        'Ashe',
        onPlayAgain: () => again++,
        onBackToLobby: () => back++,
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('PLAY AGAIN'));
    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(again, 1);
    expect(back, 0);

    await tester.ensureVisible(find.text('BACK TO LOBBY'));
    await tester.tap(find.text('BACK TO LOBBY'));
    await tester.pump();
    expect(back, 1);

    await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian'), 'Ashe', onBackToLobby: () => back++));
    await tester.pump();
    await tester.ensureVisible(find.text('PLAY AGAIN'));
    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(back, 2);
  });

  group('the sequenced reveal', () {
    double opacityOf(WidgetTester tester, Finder finder) => tester
        .widgetList<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)))
        .map((f) => f.opacity.value)
        .fold<double>(1, (a, b) => a < b ? a : b);

    testWidgets('holds the winner and the actions back until the end', (tester) async {
      await tester.pumpWidget(_host(_gameOver(myRole: 'Civilian'), 'Ashe', animate: true));
      await tester.pump();

      // Everything is in the tree from the first frame, but the winner and
      // the footer are the last beats and still fully hidden.
      expect(opacityOf(tester, find.text('CIVILIANS WIN')), 0);
      expect(opacityOf(tester, find.text('PLAY AGAIN')), 0);
      expect(opacityOf(tester, find.text('GAME OVER')), 0);

      // The word turns before the table does.
      await tester.pump(const Duration(milliseconds: 2000));
      expect(opacityOf(tester, find.text('THE WORD WAS')), 1);
      expect(opacityOf(tester, find.text('CIVILIANS WIN')), 0);

      // Past every beat, a frame at a time.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(opacityOf(tester, find.text('CIVILIANS WIN')), 1);
      expect(opacityOf(tester, find.text('VICTORY')), 1);
      expect(opacityOf(tester, find.text('GAME OVER')), 0);
      expect(opacityOf(tester, find.text('PLAY AGAIN')), 1);
    });

    testWidgets('a tap anywhere runs it to the end, and only then do the buttons work', (tester) async {
      var again = 0;
      await tester.pumpWidget(
        _host(_gameOver(myRole: 'Civilian'), 'Ashe', animate: true, onPlayAgain: () => again++),
      );
      await tester.pump();

      // While the reveal runs, a tap anywhere — even on the still-hidden
      // button — is a skip, not a press.
      await tester.ensureVisible(find.text('PLAY AGAIN'));
      await tester.tap(find.text('PLAY AGAIN'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(again, 0);
      expect(opacityOf(tester, find.text('CIVILIANS WIN')), 1);
      expect(opacityOf(tester, find.text('PLAY AGAIN')), 1);

      await tester.ensureVisible(find.text('PLAY AGAIN'));
      await tester.tap(find.text('PLAY AGAIN'));
      await tester.pump();
      expect(again, 1);
    });
  });
}
