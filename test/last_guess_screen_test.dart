import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/screens/last_guess_screen.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );

void main() {
  testWidgets('submits the typed word with the button', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_host(LastGuessScreen(
      playerName: 'Braum',
      role: Role.mrWhite,
      pack: WordPack.champions,
      deadline: 0,
      onSubmit: sent.add,
    )));

    expect(find.text("YOU'VE BEEN CAUGHT"), findsOneWidget);
    expect(find.text('Which champion was it?'), findsOneWidget);
    expect(find.text('MR. WHITE, ONE LAST WORD'), findsOneWidget);
    expect(find.text('THE WORD IS ONE OF THE CHAMPIONS'), findsOneWidget);

    // Nothing typed: the button explains itself and sends nothing.
    expect(find.text('Type your guess first'), findsOneWidget);
    await tester.tap(find.byType(HextechButton));
    await tester.pump();
    expect(sent, isEmpty);

    await tester.enterText(find.byType(TextField), '  Ahri ');
    await tester.pump();
    await tester.tap(find.byType(HextechButton));
    await tester.pump();

    expect(sent, ['Ahri']);
    expect(find.text('Guess sent. Waiting for the verdict…'), findsOneWidget);
    expect(find.byType(HextechButton), findsNothing);
  });

  testWidgets('submits with the keyboard action and sends only once', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_host(LastGuessScreen(
      playerName: 'Braum',
      role: Role.undercover,
      pack: WordPack.items,
      deadline: 0,
      onSubmit: sent.add,
    )));

    expect(find.text('Which item was it?'), findsOneWidget);
    expect(find.text('UNDERCOVER, ONE LAST WORD'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Infinity Edge');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(sent, ['Infinity Edge']);
  });

  testWidgets('shows the clue log when there is one', (tester) async {
    await tester.pumpWidget(_host(const LastGuessScreen(
      playerName: 'Braum',
      role: Role.mrWhite,
      pack: WordPack.abilities,
      deadline: 0,
      clues: [Clue(round: 1, player: 'Ashe', text: 'Fox')],
    )));

    expect(find.text('Which ability was it?'), findsOneWidget);
    expect(find.byType(ClueLog), findsOneWidget);
    expect(find.text('Fox'), findsOneWidget);
  });
}
