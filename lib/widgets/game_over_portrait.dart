import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/word_card.dart';

/// The drawn word as it is revealed at game over: the same trading card the
/// civilians held all game, turned face up for everyone.
///
/// The flip is the point — everyone has been guessing at this card all game,
/// so it arrives by being *turned over*, not by fading in. It starts edge-on
/// (-90°) and stays there until [delay] elapses, so it can be sequenced with
/// the rest of the reveal.
class GameOverPortrait extends StatelessWidget {
  /// Image URL (or the bundled placeholder), from `Lobby.myIcon`.
  final String icon;
  final String word;
  final bool isChampion;
  final Duration delay;

  const GameOverPortrait({
    super.key,
    required this.icon,
    required this.word,
    required this.isChampion,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final card = WordCard(
      icon: icon,
      word: word,
      isChampion: isChampion,
      width: 220,
      eyebrow: isChampion ? 'CHAMPION' : 'ITEM',
    );

    if (Motion.reduced(context)) return card;

    return card.animate().custom(
          delay: delay,
          duration: Motion.reveal,
          curve: Motion.emphasized,
          begin: -math.pi / 2,
          end: 0,
          builder: (context, value, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(value),
            child: child,
          ),
        );
  }
}
