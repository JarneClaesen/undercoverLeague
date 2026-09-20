/// One achievement the server can award. The server only sends ids (see
/// `Lobby.achievements`); the words live here.
class Achievement {
  final String id;
  final String title;
  final String description;

  const Achievement({required this.id, required this.title, required this.description});
}

/// The achievements the server awards, keyed by id, in display order.
class Achievements {
  static const survivor = 'survivor';
  static const mindReader = 'mind_reader';
  static const sharpEye = 'sharp_eye';
  static const publicEnemy = 'public_enemy';
  static const firstBlood = 'first_blood';
  static const ironWall = 'iron_wall';
  static const doubleAgent = 'double_agent';
  static const silentHand = 'silent_hand';
  static const veteran = 'veteran';
  static const unanimousJustice = 'unanimous_justice';

  static const List<Achievement> all = [
    Achievement(
      id: survivor,
      title: 'Survivor',
      description: 'Won as an impostor by outnumbering the civilians.',
    ),
    Achievement(
      id: mindReader,
      title: 'Mind Reader',
      description: 'Guessed the word correctly with your last breath.',
    ),
    Achievement(
      id: sharpEye,
      title: 'Sharp Eye',
      description: 'As a civilian, cast at least two votes in a game and every one hit an impostor.',
    ),
    Achievement(
      id: publicEnemy,
      title: 'Public Enemy',
      description: 'Eliminated by a unanimous ballot.',
    ),
    Achievement(
      id: firstBlood,
      title: 'First Blood',
      description: 'The first player eliminated in a game.',
    ),
    Achievement(
      id: ironWall,
      title: 'Iron Wall',
      description: 'Survived three civilian wins as a civilian.',
    ),
    Achievement(
      id: doubleAgent,
      title: 'Double Agent',
      description: 'An Undercover with a decoy word who was still standing at the end.',
    ),
    Achievement(
      id: silentHand,
      title: 'Silent Hand',
      description: 'With the clue log on, won as an impostor without ever being voted for.',
    ),
    Achievement(
      id: veteran,
      title: 'Veteran',
      description: 'Played ten games in this lobby.',
    ),
    Achievement(
      id: unanimousJustice,
      title: 'Unanimous Justice',
      description: 'As a civilian, joined a unanimous ballot that eliminated an impostor.',
    ),
  ];

  static final Map<String, Achievement> _byId = {for (final a in all) a.id: a};

  /// The achievement for [id]; an id this build does not know yet still
  /// gets a readable placeholder rather than nothing.
  static Achievement byId(String id) =>
      _byId[id] ??
      Achievement(
        id: id,
        title: id.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
        description: 'A new achievement.',
      );
}
