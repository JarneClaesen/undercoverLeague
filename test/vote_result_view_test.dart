import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/screens/vote_result_view.dart';
import 'package:undercoverleague/theme/app_theme.dart';

/// Hosts the view with animations disabled, so the tally is on screen at its
/// final size after a single pump and nothing is left ticking.
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
  testWidgets('shows who went out and how the ballot fell', (tester) async {
    await tester.pumpWidget(_host(VoteResultView(
      lastVotes: const {'Ahri': 'Zed', 'Yasuo': 'Zed', 'Zed': 'skip'},
      candidates: const ['Ahri', 'Yasuo', 'Zed'],
      eliminated: 'Zed',
      you: 'Ahri',
      onDone: () {},
    )));

    expect(find.text('ZED IS OUT'), findsOneWidget);
    // Counts: Zed 2, Ahri 0, Yasuo 0, one abstention.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    // Now that the vote is tallied, who voted for whom is public.
    expect(find.text('Ahri, Yasuo'), findsOneWidget);
    expect(find.text('Abstain'), findsOneWidget);
    expect(find.text('No votes'), findsNWidgets(2));
  });

  testWidgets('a tie says nobody was eliminated', (tester) async {
    await tester.pumpWidget(_host(VoteResultView(
      lastVotes: const {'Ahri': 'Zed', 'Zed': 'Ahri'},
      candidates: const ['Ahri', 'Zed'],
      eliminated: '',
      you: 'Zed',
      onDone: () {},
    )));

    expect(find.text('NO ONE ELIMINATED'), findsOneWidget);
    expect(find.text('Abstain'), findsNothing);
  });

  testWidgets('a last guess that came after the ballot is read out', (tester) async {
    await tester.pumpWidget(_host(VoteResultView(
      lastVotes: const {'Ahri': 'Zed', 'Yasuo': 'Zed', 'Zed': 'skip'},
      candidates: const ['Ahri', 'Yasuo', 'Zed'],
      eliminated: 'Zed',
      you: 'Ahri',
      lastGuess: (player: 'Zed', word: 'Ahri', correct: false),
      onDone: () {},
    )));

    expect(find.text("Zed guessed 'Ahri' — wrong"), findsOneWidget);

    await tester.pumpWidget(_host(VoteResultView(
      lastVotes: const {'Ahri': 'Zed', 'Yasuo': 'Zed', 'Zed': 'skip'},
      candidates: const ['Ahri', 'Yasuo', 'Zed'],
      eliminated: 'Zed',
      you: 'Ahri',
      lastGuess: (player: 'Zed', word: "Kai'Sa", correct: true),
      onDone: () {},
    )));

    expect(find.text("Zed guessed 'Kai'Sa' — correct!"), findsOneWidget);
  });

  testWidgets('tapping skips the interstitial', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(VoteResultView(
      lastVotes: const {'Ahri': 'Zed', 'Yasuo': 'Zed', 'Zed': 'skip'},
      candidates: const ['Ahri', 'Yasuo', 'Zed'],
      eliminated: 'Zed',
      you: 'Ahri',
      onDone: () => done++,
    )));

    await tester.tap(find.byType(VoteResultView));
    await tester.pump();

    expect(done, 1);
  });
}
