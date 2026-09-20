import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The word list lives with the server (it draws the word); this test keeps
/// it consistent with the icon assets the app bundles.
void main() {
  final words = jsonDecode(File('server/internal/game/words.json').readAsStringSync()) as Map<String, dynamic>;

  for (final label in ['champions', 'items']) {
    final list = (words[label] as List).cast<Map<String, dynamic>>();

    group(label, () {
      test('every entry has a name and an icon', () {
        for (final entry in list) {
          expect(entry['name'], isNotEmpty, reason: '$entry');
          expect(entry['icon'], isNotEmpty, reason: '$entry');
        }
      });

      test('names are unique', () {
        final names = list.map((e) => (e['name'] as String).toLowerCase()).toList();
        expect(names.toSet().length, names.length);
      });

      test('every icon exists in assets/', () {
        final missing = list.map((e) => e['icon'] as String).where((p) => !File(p).existsSync()).toList();
        expect(missing, isEmpty);
      });
    });
  }
}
