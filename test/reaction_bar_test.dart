import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/reaction_bar.dart';

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
  testWidgets('offers every allowed emoji and rate-limits taps', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_host(ReactionBar(onReact: sent.add)));

    for (final emoji in reactionEmoji) {
      expect(find.text(emoji), findsOneWidget);
    }

    await tester.tap(find.text(reactionEmoji[0]));
    await tester.pump();
    expect(sent, [reactionEmoji[0]]);

    // Inside the cooldown a second tap goes nowhere, whichever chip it hits.
    await tester.tap(find.text(reactionEmoji[1]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sent, [reactionEmoji[0]]);

    await tester.pump(ReactionBar.cooldown);
    await tester.tap(find.text(reactionEmoji[1]));
    await tester.pump();
    expect(sent, [reactionEmoji[0], reactionEmoji[1]]);
  });
}
