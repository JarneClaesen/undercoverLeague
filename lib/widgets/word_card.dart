import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/word_image.dart';

/// Data Dragon loading art is 308×560; the card keeps that ratio so the
/// champion is never cropped.
const double wordCardAspect = 560 / 308;

/// The drawn word as a trading card: full-bleed art inside a gold double
/// frame, the name set on a scrim along the bottom edge, an eyebrow along the
/// top. Champions fill the card with their loading-screen art; items are
/// 64 px sprites, so they sit centred on a glow at twice their size.
///
/// Sized by [width] alone; the height follows [wordCardAspect].
class WordCard extends StatelessWidget {
  final String icon;
  final String word;
  final bool isChampion;
  final double width;

  /// Small uppercase label in the top-left corner, e.g. `YOUR CHAMPION`.
  final String? eyebrow;

  /// Pill under the name, e.g. `CIVILIAN`. Drawn in [chipColour].
  final String? chip;
  final Color? chipColour;

  const WordCard({
    super.key,
    required this.icon,
    required this.word,
    required this.isChampion,
    required this.width,
    this.eyebrow,
    this.chip,
    this.chipColour,
  });

  double get height => width * wordCardAspect;

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final textTheme = Theme.of(context).textTheme;
    // Everything inside scales with the card so the compact and large
    // versions are the same design, not two layouts.
    final unit = width / 260;
    final frame = 5.0 * unit;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HextechColors.abyss,
          border: Border.all(color: hextech.accent, width: math.max(1.5, 2 * unit)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18 * unit,
              offset: Offset(0, 8 * unit),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(frame),
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _art(context, unit),
                // Top scrim + eyebrow.
                if (eyebrow != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(12 * unit, 10 * unit, 12 * unit, 26 * unit),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            HextechColors.abyss.withValues(alpha: 0.85),
                            HextechColors.abyss.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: Text(
                        eyebrow!,
                        style: textTheme.labelSmall?.copyWith(
                          color: hextech.textSecondary,
                          letterSpacing: 2.5 * unit,
                          fontSize: (textTheme.labelSmall?.fontSize ?? 11) * unit,
                        ),
                      ),
                    ),
                  ),
                // Bottom scrim + name plate.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(12 * unit, 44 * unit, 12 * unit, 14 * unit),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HextechColors.abyss.withValues(alpha: 0),
                          HextechColors.abyss.withValues(alpha: 0.88),
                          HextechColors.abyss.withValues(alpha: 0.97),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Hairline(colour: hextech.accent, unit: unit),
                        SizedBox(height: 8 * unit),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            word,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(
                              color: HextechColors.goldBright,
                              letterSpacing: 1.5 * unit,
                              fontSize: (textTheme.titleLarge?.fontSize ?? 22) * unit,
                            ),
                          ),
                        ),
                        if (chip != null) ...[
                          SizedBox(height: 8 * unit),
                          _Chip(label: chip!, colour: chipColour ?? hextech.accent, unit: unit),
                        ],
                      ],
                    ),
                  ),
                ),
                // Inner hairline frame, like the second border on a printed card.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: hextech.accent.withValues(alpha: 0.55), width: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(BuildContext context, double unit) {
    if (isChampion) {
      return wordImage(
        context,
        icon,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fallbackSize: 64 * unit,
      );
    }

    // Item sprites are 64 px: two times up is as far as they go before they
    // smear, so they float on a hextech glow instead of filling the card.
    final side = math.min(128.0, width * 0.5);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 0.75,
          colors: [HextechColors.blueDeep, HextechColors.navy, HextechColors.abyss],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Center(
        child: wordImage(
          context,
          icon,
          width: side,
          height: side,
          fit: BoxFit.contain,
          fallbackSize: side * 0.5,
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  final Color colour;
  final double unit;

  const _Hairline({required this.colour, required this.unit});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colour.withValues(alpha: 0), colour, colour.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color colour;
  final double unit;

  const _Chip({required this.label, required this.colour, required this.unit});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * unit, vertical: 4 * unit),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        border: Border.all(color: colour.withValues(alpha: 0.65)),
      ),
      child: Text(
        label,
        style: style?.copyWith(
          color: colour,
          letterSpacing: 2 * unit,
          fontSize: (style.fontSize ?? 11) * unit,
        ),
      ),
    );
  }
}
