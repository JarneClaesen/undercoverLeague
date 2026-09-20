import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/word_image.dart';

/// The drawn champion/item portrait as it is revealed at game over: a gold
/// frame with corner accents that turns face up.
///
/// The flip is the point — everyone has been guessing at this card all game,
/// so it arrives by being *turned over*, not by fading in. It starts edge-on
/// (-90°) and stays there until [delay] elapses, so it can be sequenced with
/// the rest of the reveal.
///
/// Champion art is a tall portrait and fills the frame; item icons are 64 px
/// sprites and are drawn small enough not to smear.
class GameOverPortrait extends StatelessWidget {
  /// Image URL (or the bundled placeholder), from `Lobby.myIcon`.
  final String icon;
  final bool isChampion;
  final Duration delay;

  const GameOverPortrait({
    super.key,
    required this.icon,
    required this.isChampion,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final width = isChampion ? 200.0 : 112.0;
    final height = isChampion ? 226.0 : 112.0;

    final image = wordImage(
      context,
      icon,
      width: width,
      height: height,
      fit: isChampion ? BoxFit.cover : BoxFit.contain,
      fallbackSize: 56,
    );

    final framed = HextechPanel(
      accent: true,
      padding: const EdgeInsets.all(6),
      child: image,
    );

    if (Motion.reduced(context)) return framed;

    return framed.animate().custom(
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
