import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/rules_info.dart';

/// A page with one button that opens the sheet, animations off so the
/// dialog is up on the first pump.
Widget _host(GameSettings settings, {String? topic}) {
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showRulesInfo(context, settings, topic: topic),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, GameSettings settings, {String? topic, Size size = const Size(800, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(settings, topic: topic));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Expands the section titled [title] so its paragraphs are laid out.
Future<void> _expand(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('decoy off: Undercovers get no word and a last guess', (tester) async {
    await _open(tester, const GameSettings(undercovers: 1, decoyWord: false));

    expect(find.text('HOW THIS LOBBY PLAYS'), findsOneWidget);
    expect(find.byType(HextechExpander), findsNWidgets(8));
    // The first section starts open.
    expect(find.textContaining('Every game hides 1 Undercover among the civilians'), findsOneWidget);
    expect(find.textContaining('The Undercover is on their own'), findsOneWidget);
    expect(find.text('Off: Undercovers get no word'), findsOneWidget);

    await _expand(tester, 'Decoy word');
    expect(find.textContaining('Undercovers get no word at all'), findsOneWidget);
    expect(find.textContaining('get a last guess at the word'), findsOneWidget);

    await _expand(tester, 'Last guess');
    expect(find.textContaining('one shot at naming the word'), findsOneWidget);
    expect(find.textContaining('any Undercover who is voted out'), findsOneWidget);

    await _expand(tester, 'Winning');
    expect(find.textContaining('Civilians win when every impostor is voted out'), findsOneWidget);
    expect(find.textContaining('equal or outnumber the civilians'), findsOneWidget);
  });

  testWidgets('decoy on: the look-alike word, the ladder and the reveal', (tester) async {
    await _open(
      tester,
      const GameSettings(undercovers: 2, decoyWord: true, packs: {WordPack.champions, WordPack.items}),
      topic: RulesTopic.decoy,
    );

    expect(find.text('On: Undercovers get a look-alike word'), findsOneWidget);
    // Asked for the decoy section, so it is the one open.
    expect(find.textContaining('told a different but similar word from the same pack'), findsOneWidget);
    expect(find.textContaining('marked UNDERCOVER'), findsOneWidget);
    expect(find.textContaining('another champion of the same class first'), findsOneWidget);
    expect(find.textContaining('build from or into'), findsOneWidget);
    expect(find.textContaining('could have drawn from champions and items'), findsOneWidget);
    expect(find.text('All 2 Undercovers get the same decoy.'), findsOneWidget);
    expect(find.textContaining('both words are revealed'), findsOneWidget);
    expect(find.textContaining('Every game hides'), findsNothing);

    await _expand(tester, 'Roles');
    expect(find.textContaining('Every game hides 2 Undercovers among the civilians'), findsOneWidget);
    expect(find.textContaining('Undercovers don\'t know each other'), findsOneWidget);

    await _expand(tester, 'Last guess');
    expect(find.textContaining('nobody gets a guess in this lobby'), findsOneWidget);
  });

  testWidgets('mixed mode names Mr. White and reserves the last guess for him', (tester) async {
    await _open(
      tester,
      const GameSettings(undercovers: 1, mrWhites: 1, decoyWord: true, randomOrder: true, turnSeconds: 60, clueLog: true, rotateHost: true),
    );

    expect(find.text('1 Undercover, 1 Mr. White, the rest civilians'), findsOneWidget);
    expect(find.textContaining('Every game hides 1 Undercover and 1 Mr. White'), findsOneWidget);
    expect(find.textContaining('Nobody knows who Mr. White is'), findsOneWidget);

    await _expand(tester, 'Last guess');
    expect(find.textContaining('That means Mr. White. Undercovers hold a decoy'), findsOneWidget);

    await _expand(tester, 'Turns & order');
    expect(find.text('Random order · 60 s per turn · clue log'), findsOneWidget);
    expect(find.textContaining('reshuffled every round'), findsOneWidget);
    expect(find.textContaining('60 s per turn. Voting and the last guess get double, 120 s'), findsOneWidget);
    expect(find.textContaining('a turn ends by typing your clue'), findsOneWidget);

    await _expand(tester, 'Voting');
    expect(find.textContaining('a tie eliminates nobody'), findsOneWidget);

    await _expand(tester, 'Spectators & reactions');
    expect(find.textContaining('Sit out in the lobby'), findsOneWidget);
    expect(find.textContaining('can send emoji reactions'), findsOneWidget);

    await _expand(tester, 'Scoreboard & titles');
    expect(find.text('Points per game · host rotates'), findsOneWidget);
    expect(find.textContaining('+3 for a surviving impostor, +1 for an eliminated one'), findsOneWidget);
    expect(find.textContaining('Correct last guess: +3'), findsOneWidget);
    expect(find.textContaining('passes the host seat to the next player'), findsOneWidget);
  });

  testWidgets('fixed order and no timer read as such', (tester) async {
    await _open(tester, const GameSettings(), topic: RulesTopic.turns);

    expect(find.text('Fixed order · no timer'), findsOneWidget);
    expect(find.textContaining('the first speaker rotates each round'), findsOneWidget);
    expect(find.textContaining('No timer: take the time you need'), findsOneWidget);
    expect(find.textContaining('Clues are spoken out loud'), findsOneWidget);
  });

  testWidgets('fits a narrow phone and closes from the button', (tester) async {
    await _open(tester, const GameSettings(mrWhites: 1, decoyWord: true), size: const Size(320, 560));

    expect(tester.takeException(), isNull);
    expect(find.text('HOW THIS LOBBY PLAYS'), findsOneWidget);

    await tester.ensureVisible(find.text('GOT IT'));
    await tester.tap(find.text('GOT IT'));
    await tester.pumpAndSettle();
    expect(find.text('HOW THIS LOBBY PLAYS'), findsNothing);
  });

  test('the copy is built per section with stable ids', () {
    final ids = rulesSectionsFor(const GameSettings()).map((s) => s.id).toList();
    expect(ids, [
      RulesTopic.roles,
      RulesTopic.decoy,
      RulesTopic.lastGuess,
      RulesTopic.winning,
      RulesTopic.turns,
      RulesTopic.voting,
      RulesTopic.spectators,
      RulesTopic.scoring,
    ]);
  });
}
