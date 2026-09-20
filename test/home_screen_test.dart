import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/models/daily_theme.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/screens/home_screen.dart';
import 'package:undercoverleague/theme/app_theme.dart';
import 'package:undercoverleague/widgets/home_theme_banner.dart';
import 'package:undercoverleague/widgets/home_wordmark.dart';

const _theme = DailyTheme(
  id: 'shurima',
  title: 'Shurima Day',
  description: 'Only champions from Shurima and their abilities.',
  filter: GameSettings(packs: {WordPack.champions, WordPack.abilities}, champRegions: {'Shurima'}),
);

Widget _host(Future<DailyTheme?> Function() load) {
  return MaterialApp(
    theme: hextechTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: HomeScreen(loadDailyTheme: load),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("shows today's theme once it arrives, under the wordmark", (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final completer = Completer<DailyTheme?>();
    await tester.pumpWidget(_host(() => completer.future));
    await tester.pump();

    // Nothing while loading: no banner, no spinner, and the form is usable.
    expect(find.byType(HomeThemeBanner), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('CREATE LOBBY'), findsOneWidget);
    expect(find.text('JOIN LOBBY'), findsOneWidget);

    completer.complete(_theme);
    await tester.pumpAndSettle();

    expect(find.byType(HomeThemeBanner), findsOneWidget);
    expect(find.text('Shurima Day'), findsOneWidget);
    expect(find.text('Only champions from Shurima and their abilities.'), findsOneWidget);
    expect(find.text('Hosts can apply it in the lobby'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(HomeThemeBanner)).dy,
      greaterThan(tester.getBottomLeft(find.byType(HomeWordmark)).dy),
    );
    expect(find.text('CREATE LOBBY'), findsOneWidget);
  });

  testWidgets('stays quiet when the server has no theme or fails', (tester) async {
    await tester.pumpWidget(_host(() async => null));
    await tester.pumpAndSettle();
    expect(find.byType(HomeThemeBanner), findsNothing);
    expect(find.text('CREATE LOBBY'), findsOneWidget);

    await tester.pumpWidget(_host(() async => throw Exception('offline')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeThemeBanner), findsNothing);
    expect(find.text('CREATE LOBBY'), findsOneWidget);
  });
}
