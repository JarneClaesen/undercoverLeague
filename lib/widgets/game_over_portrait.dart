import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/reveal_sequence.dart';

/// One player in the game-over roster, turned face up.
///
/// Civilians simply flip over and settle. Impostors (the Undercover and
/// Mr. White) are *unmasked*: the card flips, jolts as if caught, takes on a
/// red-and-gold rim, and the role chip slams down onto it. The whole thing is
/// driven by [reveal] so it sits on the game-over clock; with no [reveal] the
/// portrait is drawn at rest, which is also what reduced motion gets.
class GameOverPortrait extends StatelessWidget {
  final String name;

  /// `Civilian`, `Undercover`, `MrWhite` or `Spectator`.
  final String role;
  final bool isHost;
  final bool isYou;
  final bool eliminated;

  /// The line under the name: an Undercover's decoy word, Mr. White's
  /// "No word", nothing for a civilian.
  final String? subtitle;

  /// The window on the reveal clock this card turns over in. Null renders
  /// the final state.
  final RevealWindow? reveal;

  const GameOverPortrait({
    super.key,
    required this.name,
    required this.role,
    this.isHost = false,
    this.isYou = false,
    this.eliminated = false,
    this.subtitle,
    this.reveal,
  });

  static const double width = 150;

  /// How long a card takes from face-down to at rest, so the roster can lay
  /// portraits end to end on the clock.
  static Duration revealLength({required bool impostor}) => impostor ? _unmaskLength : _calmLength;

  static const Duration _calmLength = Duration(milliseconds: 600);
  static const Duration _unmaskLength = Duration(milliseconds: 1300);

  // The unmasking, in wall time from the start of the window.
  static const Duration _flip = Duration(milliseconds: 520);
  static const Duration _jolt = Duration(milliseconds: 380);
  static const Duration _glow = Duration(milliseconds: 780);
  static const Duration _chipAt = Duration(milliseconds: 640);
  static const Duration _chip = Duration(milliseconds: 260);

  static bool isImpostorRole(String role) => role == 'Undercover' || role == 'MrWhite';

  static String roleLabel(String role) => switch (role) {
    'Undercover' => 'UNDERCOVER',
    'MrWhite' => 'MR. WHITE',
    'Spectator' => 'SPECTATOR',
    _ => 'CIVILIAN',
  };

  bool get _impostor => isImpostorRole(role);

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final animated = reveal != null && !Motion.reduced(context);

    final roleColour = switch (role) {
      'Undercover' || 'MrWhite' => HextechColors.dangerBright,
      'Spectator' => hextech.textSecondary,
      _ => hextech.accent,
    };

    Widget chip = _RoleChip(label: roleLabel(role), colour: roleColour);
    if (animated && _impostor) {
      chip = chip
          .animate(adapter: reveal!.adapter())
          .scale(
            delay: _chipAt,
            duration: _chip,
            begin: const Offset(2.4, 2.4),
            end: const Offset(1, 1),
            curve: Curves.easeInCubic,
          )
          .fadeIn(delay: _chipAt, duration: _chip, curve: Curves.easeInCubic);
    }

    Widget card = SizedBox(
      width: width,
      child: HextechPanel(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        tone: _impostor ? PanelTone.danger : PanelTone.neutral,
        accent: _impostor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _medallion(context, roleColour),
            const SizedBox(height: 10),
            _name(context),
            const SizedBox(height: 8),
            chip,
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _impostor ? hextech.textPrimary : hextech.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (eliminated) ...[
              const SizedBox(height: 8),
              Text(
                'ELIMINATED',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: hextech.danger, letterSpacing: 2),
              ),
            ],
          ],
        ),
      ),
    );

    // The rim is part of the final state for impostors, so it is drawn even
    // when nothing animates.
    if (_impostor) {
      card = animated
          ? card
                .animate(adapter: reveal!.adapter())
                .custom(
                  delay: _flip,
                  duration: _glow,
                  curve: Motion.enter,
                  builder: (_, value, child) => _Rim(strength: value, child: child),
                )
          : _Rim(strength: 1, child: card);
    }

    if (!animated) return card;

    final chain = card
        .animate(adapter: reveal!.adapter())
        .custom(
          duration: _flip,
          curve: Motion.emphasized,
          begin: -math.pi / 2,
          end: 0,
          builder: (_, value, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(value),
            child: child,
          ),
        );

    if (!_impostor) return chain;

    // Caught: a short, fast jolt the instant the face is readable.
    return chain.shake(
      delay: _flip,
      duration: _jolt,
      hz: 16,
      offset: const Offset(4, 0),
      rotation: 0.012,
      curve: Curves.easeOut,
    );
  }

  Widget _medallion(BuildContext context, Color ring) {
    final hextech = context.hextech;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HextechColors.navyLight,
              border: Border.all(color: isYou ? hextech.accentGlow : ring, width: 2),
            ),
            child: _impostor
                ? Icon(role == 'MrWhite' ? Icons.help_outline : Icons.theater_comedy, size: 28, color: ring)
                : Text(
                    _initials,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: eliminated ? hextech.textDisabled : hextech.textPrimary),
                  ),
          ),
          if (isHost)
            Positioned(top: -4, child: Icon(Icons.workspace_premium, size: 18, color: hextech.accent)),
        ],
      ),
    );
  }

  Widget _name(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            color: eliminated ? hextech.textSecondary : hextech.textPrimary,
            decoration: eliminated ? TextDecoration.lineThrough : null,
            decorationColor: hextech.danger,
          ),
        ),
        if (isYou) Text('(you)', style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary)),
      ],
    );
  }
}

/// The red-and-gold halo an unmasked impostor's card wears. Two plain box
/// shadows: cheap enough to animate on the web.
///
/// Always a [DecoratedBox], even at zero strength: the subtree under it holds
/// live `flutter_animate` adapters, and changing the tree's shape mid-reveal
/// would re-mount them.
class _Rim extends StatelessWidget {
  final double strength;
  final Widget child;

  const _Rim({required this.strength, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: strength <= 0
            ? const []
            : [
                BoxShadow(
                  color: HextechColors.dangerBright.withValues(alpha: 0.45 * strength),
                  blurRadius: 22 * strength,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: HextechColors.gold.withValues(alpha: 0.28 * strength),
                  blurRadius: 8 * strength,
                ),
              ],
      ),
      child: child,
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color colour;

  const _RoleChip({required this.label, required this.colour});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        border: Border.all(color: colour.withValues(alpha: 0.65)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colour, letterSpacing: 2),
      ),
    );
  }
}
