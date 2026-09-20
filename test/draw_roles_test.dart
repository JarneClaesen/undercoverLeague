import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/data/data.dart';
import 'package:undercoverleague/services/firebase_service.dart';

void main() {
  const players = ['Host', 'Second', 'Third', 'Fourth', 'Fifth'];
  const trials = 200000;

  test('every player is equally likely to be the Undercover', () {
    // Production uses Random() (entropy-seeded); a fixed seed runs the same
    // generator deterministically so the test can't flake.
    final random = Random(20260920);
    final counts = {for (final p in players) p: 0};
    for (var i = 0; i < trials; i++) {
      final undercover = FirebaseService.drawRoles(players, random).undercover;
      counts[undercover] = counts[undercover]! + 1;
    }
    // ignore: avoid_print
    print('Undercover counts over $trials draws: $counts');

    final expected = trials / players.length;
    // 4-sigma band for a binomial with p = 1/n. A bias of even one
    // percentage point (e.g. the host at 21% instead of 20%) would fail it.
    final sigma = sqrt(trials * (1 / players.length) * (1 - 1 / players.length));
    for (final entry in counts.entries) {
      expect(
        (entry.value - expected).abs(),
        lessThan(4 * sigma),
        reason: '${entry.key} was Undercover ${entry.value} times, expected ~$expected',
      );
    }
  });

  test('the Undercover is equally likely to be in any round-order position', () {
    final random = Random(20260920);
    final positionCounts = List.filled(players.length, 0);
    for (var i = 0; i < trials; i++) {
      final draw = FirebaseService.drawRoles(players, random);
      positionCounts[draw.order.indexOf(draw.undercover)]++;
    }
    final expected = trials / players.length;
    final sigma = sqrt(trials * (1 / players.length) * (1 - 1 / players.length));
    for (var pos = 0; pos < players.length; pos++) {
      expect((positionCounts[pos] - expected).abs(), lessThan(4 * sigma),
          reason: 'position $pos: ${positionCounts[pos]}');
    }
  });

  test('every player is equally likely to go first', () {
    final random = Random(20260920);
    final counts = {for (final p in players) p: 0};
    for (var i = 0; i < trials; i++) {
      final first = FirebaseService.drawRoles(players, random).order.first;
      counts[first] = counts[first]! + 1;
    }
    final expected = trials / players.length;
    final sigma = sqrt(trials * (1 / players.length) * (1 - 1 / players.length));
    for (final entry in counts.entries) {
      expect((entry.value - expected).abs(), lessThan(4 * sigma), reason: '${entry.key}: ${entry.value}');
    }
  });

  test('champions and items are drawn 50/50 when both are enabled', () {
    final random = Random(20260920);
    var championDraws = 0;
    for (var i = 0; i < trials; i++) {
      final draw = FirebaseService.drawWord(true, true, random);
      if (draw.isChampion) championDraws++;
      expect((draw.isChampion ? champions : items).contains(draw.word), isTrue);
    }
    final sigma = sqrt(trials * 0.25);
    expect((championDraws - trials / 2).abs(), lessThan(4 * sigma),
        reason: 'champions drawn $championDraws times out of $trials');
  });

  test('a single enabled category is always used', () {
    final random = Random(20260920);
    for (var i = 0; i < 1000; i++) {
      final c = FirebaseService.drawWord(true, false, random);
      expect(c.isChampion, isTrue);
      expect(champions.contains(c.word), isTrue);
      final it = FirebaseService.drawWord(false, true, random);
      expect(it.isChampion, isFalse);
      expect(items.contains(it.word), isTrue);
    }
  });
}
