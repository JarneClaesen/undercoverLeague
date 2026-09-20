import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/clue_log.dart';

Widget _host(Widget child) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

const _clues = [
  Clue(round: 1, player: 'Ashe', text: 'Cold'),
  Clue(round: 1, player: 'Braum', text: 'Shield'),
  Clue(round: 2, player: 'Ashe', text: 'Arrows'),
  Clue(round: 2, player: 'Braum', text: ''),
];

void main() {
  testWidgets('groups clues by round with the newest open and blanks as a dash', (tester) async {
    await tester.pumpWidget(_host(const ClueLog(clues: _clues, you: 'Ashe')));

    expect(find.text('CLUE LOG'), findsOneWidget);
    expect(find.text('ROUND 2'), findsOneWidget);
    expect(find.text('ROUND 1'), findsOneWidget);
    // Round 2 is open: its clues are on screen, the timed-out one as a dash.
    expect(find.text('Arrows'), findsOneWidget);
    expect(find.text(ClueLog.blank), findsOneWidget);
    // Round 1 is folded away.
    expect(find.text('Cold'), findsNothing);
    expect(find.text('Shield'), findsNothing);
  });

  testWidgets('a folded round opens on tap and closes again', (tester) async {
    await tester.pumpWidget(_host(const ClueLog(clues: _clues)));

    await tester.tap(find.text('ROUND 1'));
    await tester.pumpAndSettle();
    expect(find.text('Cold'), findsOneWidget);
    expect(find.text('Shield'), findsOneWidget);

    await tester.tap(find.text('ROUND 2'));
    await tester.pumpAndSettle();
    expect(find.text('Arrows'), findsNothing);
  });

  testWidgets('a new round opens itself', (tester) async {
    await tester.pumpWidget(_host(const ClueLog(clues: _clues)));
    await tester.pumpWidget(_host(const ClueLog(clues: [
      ..._clues,
      Clue(round: 3, player: 'Ashe', text: 'Frost'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('ROUND 3'), findsOneWidget);
    expect(find.text('Frost'), findsOneWidget);
    expect(find.text('Arrows'), findsNothing);
  });

  testWidgets('says so when there are no clues yet', (tester) async {
    await tester.pumpWidget(_host(const ClueLog(clues: [])));
    expect(find.textContaining('No clues yet'), findsOneWidget);
  });
}
