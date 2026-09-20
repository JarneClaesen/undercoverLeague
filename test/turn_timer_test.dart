import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';

/// A clock the test moves by hand; the widget's ticker only triggers
/// rebuilds, the time itself comes from here.
class _Clock {
  DateTime now = DateTime(2026, 9, 20, 12, 0, 0);

  void advance(Duration d) => now = now.add(d);
}

Widget _host(Widget child, {bool reduced = true}) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Center(child: child),
          ),
        ),
      ),
    );

double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(of: find.byType(TurnTimer), matching: find.byType(Transform)),
  );
  return transform.transform.getMaxScaleOnAxis();
}

void main() {
  test('formats minutes and seconds', () {
    expect(TurnTimer.format(const Duration(seconds: 65)), '1:05');
    expect(TurnTimer.format(const Duration(seconds: 9)), '0:09');
    expect(TurnTimer.format(Duration.zero), '0:00');
    expect(TurnTimer.format(const Duration(seconds: -4)), '0:00');
  });

  testWidgets('draws nothing without a deadline', (tester) async {
    await tester.pumpWidget(_host(const TurnTimer(deadline: 0)));
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('counts down against the clock and sits at zero when overdue', (tester) async {
    final clock = _Clock();
    final deadline = clock.now.add(const Duration(seconds: 30)).millisecondsSinceEpoch;

    await tester.pumpWidget(_host(TurnTimer(deadline: deadline, now: () => clock.now)));
    expect(find.text('0:30'), findsOneWidget);

    clock.advance(const Duration(seconds: 12));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0:18'), findsOneWidget);

    clock.advance(const Duration(seconds: 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('0:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not pulse in the last seconds under reduced motion', (tester) async {
    final clock = _Clock();
    final deadline = clock.now.add(const Duration(seconds: 5)).millisecondsSinceEpoch;

    await tester.pumpWidget(_host(TurnTimer(deadline: deadline, now: () => clock.now)));
    expect(find.text('0:05'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      expect(_scaleOf(tester), 1.0);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pulses in the last seconds when motion is allowed', (tester) async {
    final clock = _Clock();
    final deadline = clock.now.add(const Duration(seconds: 5)).millisecondsSinceEpoch;

    await tester.pumpWidget(_host(TurnTimer(deadline: deadline, now: () => clock.now), reduced: false));
    await tester.pump(const Duration(milliseconds: 350));
    expect(_scaleOf(tester), greaterThan(1.0));

    await tester.pumpWidget(const SizedBox());
  });
}
