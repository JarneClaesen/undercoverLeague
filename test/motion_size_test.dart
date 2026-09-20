import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/hextech_expander.dart';
import 'package:undercoverleague/widgets/lobby_pool_toggles.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

Widget _host(Widget child, {required bool reduced}) => MaterialApp(
      theme: hextechTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );

class _Toggle extends StatefulWidget {
  const _Toggle();

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(onPressed: () => setState(() => _open = !_open), child: const Text('toggle')),
        MotionSize(
          child: _open ? const SizedBox(height: 120, child: Text('body')) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('swaps the child outright under reduced motion', (tester) async {
    await tester.pumpWidget(_host(const _Toggle(), reduced: true));
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text('body'), findsNothing);

    await tester.tap(find.text('toggle'));
    await tester.pump();
    expect(find.text('body'), findsOneWidget);
    expect(tester.getSize(find.text('body').hitTestable()).height, 120);

    await tester.tap(find.text('toggle'));
    await tester.pump();
    expect(find.text('body'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animates when motion is not reduced', (tester) async {
    await tester.pumpWidget(_host(const _Toggle(), reduced: false));
    expect(find.byType(AnimatedSize), findsOneWidget);

    await tester.tap(find.text('toggle'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expander and pool toggles open under reduced motion without asserting', (tester) async {
    await tester.pumpWidget(_host(
      Column(
        children: [
          const HextechExpander(title: 'Rules', child: Text('inside')),
          LobbyPoolToggles(packs: const {'champions'}, onChanged: (_) {}),
        ],
      ),
      reduced: true,
    ));
    expect(find.text('inside'), findsNothing);

    await tester.tap(find.text('Rules'));
    await tester.pump();
    expect(find.text('inside'), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
