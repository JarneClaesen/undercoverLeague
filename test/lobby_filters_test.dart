import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/lobby_filters.dart';

/// Hosts the filters over [settings] with animations off, feeding every
/// change straight back in so the chips reflect the last commit.
Widget _host(GameSettings settings, ValueChanged<GameSettings> onChanged, {List<String> resources = const []}) {
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Scaffold(
          body: SingleChildScrollView(
            child: LobbyFilters(
              settings: settings,
              seasonRange: const SeasonRange(champions: (1, 16), items: (3, 16)),
              poolSize: const PoolSize({'champions': 170, 'items': 210}),
              classes: const ['Assassin', 'Mage'],
              regions: const ['Ionia', 'Shurima'],
              resources: resources,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the champion filters offer range, resource, damage and difficulty chips', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    GameSettings? changed;
    await tester.pumpWidget(_host(const GameSettings(), (s) => changed = s, resources: const ['mana', 'energy', 'none', 'other']));
    await tester.pump();

    // Collapsed by default, nothing active.
    expect(find.text('CHAMPION FILTERS'), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('MELEE'), findsNothing);

    await tester.tap(find.text('CHAMPION FILTERS'));
    await tester.pumpAndSettle();

    for (final chip in ['ASSASSIN', 'IONIA', 'MELEE', 'RANGED', 'MANA', 'ENERGY', 'MANALESS', 'FURY & OTHER', 'PHYSICAL', 'MAGIC', 'MIXED', 'EASY', 'MEDIUM', 'HARD']) {
      expect(find.text(chip), findsOneWidget, reason: chip);
    }

    await tester.tap(find.text('MELEE'));
    await tester.pump();
    expect(changed!.champRanges, {'melee'});
    expect(changed!.champResources, isEmpty);

    await tester.tap(find.text('HARD'));
    await tester.pump();
    // The widget shows the settings it was given; a fresh host reflects
    // the last commit, which only carried the difficulty on top of defaults.
    expect(changed!.champDifficulty, {'hard'});
  });

  testWidgets('resource chips follow the catalog and the header counts every bucket', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const settings = GameSettings(
      champClasses: {'Mage'},
      champRanges: {ChampionRange.ranged},
      champResources: {ChampionResource.mana},
      champDamage: {ChampionDamage.magic},
      champDifficulty: {ChampionDifficulty.easy, ChampionDifficulty.medium},
    );
    GameSettings? changed;
    await tester.pumpWidget(_host(settings, (s) => changed = s, resources: const ['mana', 'other']));
    await tester.pump();

    expect(find.text('6 ACTIVE'), findsOneWidget);
    await tester.tap(find.text('CHAMPION FILTERS'));
    await tester.pumpAndSettle();

    // Only the buckets the catalog has: no energy champions, no chip.
    expect(find.text('MANA'), findsOneWidget);
    expect(find.text('FURY & OTHER'), findsOneWidget);
    expect(find.text('ENERGY'), findsNothing);
    expect(find.text('MANALESS'), findsNothing);

    // Toggling off is a commit too.
    await tester.tap(find.text('RANGED'));
    await tester.pump();
    expect(changed!.champRanges, isEmpty);
    expect(changed!.champDamage, {'magic'});
  });

  testWidgets('without a resources list the resource row is hidden and the rest stays', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const GameSettings(), (_) {}));
    await tester.tap(find.text('CHAMPION FILTERS'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Resource ·'), findsNothing);
    expect(find.textContaining('Range ·'), findsOneWidget);
    expect(find.textContaining('Damage ·'), findsOneWidget);
    expect(find.textContaining('Difficulty ·'), findsOneWidget);
  });
}
