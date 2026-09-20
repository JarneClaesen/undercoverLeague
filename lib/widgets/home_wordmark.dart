import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// The home screen's hero: the wordmark and the game's one-line pitch.
///
/// "UNDERCOVER" is filled with a gold gradient rather than a flat swatch so the
/// title reads as engraved metal; "LEAGUE" sits under it in hextech blue with
/// the wide tracking the League client uses for its secondary display type.
class HomeWordmark extends StatelessWidget {
  const HomeWordmark({super.key});

  /// Tracking for "LEAGUE". Also used to re-centre the word: letter spacing is
  /// appended after the final glyph, which otherwise pushes it off-centre.
  static const double _leagueTracking = 12;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scales down rather than overflowing on a narrow phone.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [HextechColors.gold, HextechColors.goldBright],
            ).createShader(bounds),
            child: Text(
              'UNDERCOVER',
              textAlign: TextAlign.center,
              style: textTheme.displayLarge,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.only(left: _leagueTracking),
            child: Text(
              'LEAGUE',
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(
                color: hextech.accentGlow,
                letterSpacing: _leagueTracking,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Find the impostor among the champions.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
        ),
      ],
    );
  }
}
