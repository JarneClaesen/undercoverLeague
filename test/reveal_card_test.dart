import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/reveal_card.dart';

Widget _host(Widget child) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('the card starts face-down, showing nothing but the invitation', (tester) async {
    await tester.pumpWidget(_host(
      const RevealCard(
        role: 'Civilian',
        word: 'Ahri',
        icon: 'assets/default_icon.jpg',
        isChampion: true,
      ),
    ));
    await tester.pump();

    expect(find.text('HOLD TO REVEAL'), findsOneWidget);
    expect(find.text('Ahri'), findsNothing);

    // Let the one-shot "press me" shimmer finish so no timer outlives the test.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('pressing flips it up and reports the reveal; releasing hides it again',
      (tester) async {
    var revealed = 0;
    await tester.pumpWidget(_host(
      RevealCard(
        role: 'Civilian',
        word: 'Ahri',
        icon: 'assets/default_icon.jpg',
        isChampion: true,
        onRevealed: () => revealed++,
      ),
    ));
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(find.byType(RevealCard)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(revealed, 1);
    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('HOLD TO REVEAL'), findsNothing);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Ahri'), findsNothing);
    expect(find.text('HOLD TO REVEAL'), findsOneWidget);
    // The invitation only fires once, however many times the card is peeked.
    expect(revealed, 1);
  });

  testWidgets('a non-peekable card that starts revealed shows the word immediately',
      (tester) async {
    await tester.pumpWidget(_host(
      const RevealCard(
        role: 'Civilian',
        word: 'Ahri',
        icon: 'assets/default_icon.jpg',
        isChampion: true,
        peekable: false,
        initiallyRevealed: true,
      ),
    ));
    await tester.pump();

    expect(find.text('Ahri'), findsOneWidget);
    expect(find.text('HOLD TO REVEAL'), findsNothing);
  });

  testWidgets('the Undercover face never names a word', (tester) async {
    await tester.pumpWidget(_host(
      const RevealCard(
        role: 'Undercover',
        word: '',
        icon: 'assets/default_icon.jpg',
        isChampion: true,
        peekable: false,
        initiallyRevealed: true,
      ),
    ));
    await tester.pump();

    expect(find.text('UNDERCOVER'), findsOneWidget);
    expect(find.text("You don't know the word. Blend in."), findsOneWidget);
  });
}
