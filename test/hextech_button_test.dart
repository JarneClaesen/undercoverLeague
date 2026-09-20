import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('a disabled button explains itself instead of relabelling', (tester) async {
    await tester.pumpWidget(_host(
      const HextechButton(
        label: 'Start game',
        onPressed: null,
        disabledReason: 'Need at least 3 players',
      ),
    ));

    expect(find.text('START GAME'), findsOneWidget);
    expect(find.text('Need at least 3 players'), findsOneWidget);
  });

  testWidgets('no reason is shown while the button is usable', (tester) async {
    await tester.pumpWidget(_host(
      HextechButton(
        label: 'Start game',
        onPressed: () {},
        disabledReason: 'Need at least 3 players',
      ),
    ));

    expect(find.text('Need at least 3 players'), findsNothing);
  });

  testWidgets('busy shows a spinner, keeps the width, and swallows taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      HextechButton(label: 'Lock in vote', expand: false, onPressed: () => taps++),
    ));
    final idleWidth = tester.getSize(find.byType(HextechButton)).width;

    await tester.pumpWidget(_host(
      HextechButton(label: 'Lock in vote', expand: false, busy: true, onPressed: () => taps++),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The label stays in the tree (at zero opacity) so the button does not resize.
    expect(find.text('LOCK IN VOTE'), findsOneWidget);
    expect(tester.getSize(find.byType(HextechButton)).width, idleWidth);

    await tester.tap(find.byType(HextechButton));
    await tester.pump();
    expect(taps, 0);
  });
}
