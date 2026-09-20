import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/data/data.dart';

void main() {
  for (final (label, list) in [('champions', champions), ('items', items)]) {
    group(label, () {
      test('every entry has a name and an icon', () {
        for (final entry in list) {
          expect(entry['name'], isNotEmpty, reason: '$entry');
          expect(entry['icon'], isNotEmpty, reason: '$entry');
        }
      });

      test('names are unique', () {
        final names = list.map((e) => e['name']!.toLowerCase()).toList();
        expect(names.toSet().length, names.length);
      });

      test('every icon exists in assets/', () {
        final missing = list.map((e) => e['icon']!).where((p) => !File(p).existsSync()).toList();
        expect(missing, isEmpty);
      });
    });
  }
}
