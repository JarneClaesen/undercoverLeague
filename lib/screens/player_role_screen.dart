import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/ready_meter.dart';
import 'package:undercoverleague/widgets/reveal_card.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

/// Body of the role-reveal phase. Rendered inside GameScreen's scaffold.
///
/// Acknowledging is gated on actually having looked: the card has to have been
/// flipped once before "I know my role" becomes tappable, otherwise it is far
/// too easy to tap through the phase and then have no idea what your word is.
///
/// Everything role-specific — the Mr. White face, the decoy's word under an
/// UNDERCOVER chip — is on the card and only readable while it is held. What
/// sits permanently on screen is the same for every role: a reminder of the
/// rules this lobby plays with, so nobody looking over a shoulder learns
/// anything from the screen itself.
class PlayerRoleScreen extends StatefulWidget {
  final String playerName;
  final String role;
  final String word;
  final String icon;
  final bool isChampion;

  /// The pack the word came from, for the card's eyebrow.
  final String pack;
  final Map<String, bool> rolesAcknowledged;

  /// The lobby's rules, for the reminder under the card.
  final GameSettings settings;

  const PlayerRoleScreen({
    super.key,
    required this.playerName,
    required this.role,
    required this.word,
    required this.icon,
    required this.isChampion,
    this.pack = '',
    required this.rolesAcknowledged,
    this.settings = const GameSettings(),
  });

  /// The rules reminder shown to everybody in this phase. Derived from the
  /// settings alone so it is identical on every phone at the table.
  static String rulesNote(GameSettings settings) {
    final many = settings.undercovers > 1;
    final who = many ? 'The Undercovers' : 'The Undercover';
    if (settings.mrWhites > 0) {
      return '$who hold${many ? '' : 's'} a look-alike word and Mr. White holds none. '
          'Whoever is caught without the word gets one guess at it.';
    }
    if (settings.decoyWord) {
      return '$who hold${many ? '' : 's'} a look-alike word: if the clues do not quite fit yours, it may be you.';
    }
    return '$who ha${many ? 've' : 's'} no word. Caught, they get one guess at it to steal the game.';
  }

  @override
  State<PlayerRoleScreen> createState() => _PlayerRoleScreenState();
}

class _PlayerRoleScreenState extends State<PlayerRoleScreen> with SingleTickerProviderStateMixin {
  bool _hasRevealed = false;
  Timer? _hintTimer;
  late final AnimationController _hint;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

    // If the card is still face-down after a moment, nudge it once. A card
    // that never moves reads as decoration.
    _hintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || _hasRevealed || Motion.reduced(context)) return;
      _hint.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _hint.dispose();
    super.dispose();
  }

  void _onRevealed() {
    _hintTimer?.cancel();
    if (_hasRevealed) return;
    setState(() => _hasRevealed = true);
  }

  void _acknowledge() {
    HapticFeedback.mediumImpact().catchError((Object _) {});
    LobbyService().acknowledgeRole();
  }

  @override
  Widget build(BuildContext context) {
    final readyCount = widget.rolesAcknowledged.values.where((v) => v).length;
    final totalPlayers = widget.rolesAcknowledged.length;
    final hasAcknowledged = widget.rolesAcknowledged[widget.playerName] ?? false;
    final isSpectator = widget.role == Role.spectator;
    final waitingOn = (totalPlayers - readyCount).clamp(0, totalPlayers);

    Widget card = RevealCard(
      role: widget.role,
      word: widget.word,
      icon: widget.icon,
      isChampion: widget.isChampion,
      pack: widget.pack,
      onRevealed: _onRevealed,
    );

    if (!Motion.reduced(context)) {
      card = card
          .animate()
          .fadeIn(duration: Motion.slow, curve: Motion.enter)
          .slideY(begin: 0.2, end: 0, duration: Motion.slow, curve: Motion.enter);
    }

    // The hint wrapper stays in the tree at all times: inserting it later would
    // re-parent the card and throw away the flip it is holding.
    card = AnimatedBuilder(
      animation: _hint,
      child: card,
      builder: (context, child) {
        final t = _hint.value;
        final swing = t == 0 ? 0.0 : math.sin(t * math.pi * 6) * 5 * (1 - t);
        return Transform.translate(offset: Offset(swing, 0), child: child);
      },
    );

    // The card scrolls; the meter and the acknowledge button do not. On a
    // small phone the button is otherwise below the fold, and nobody thinks to
    // scroll on a screen whose only job is one tap.
    Widget action;
    if (isSpectator) {
      action = const StatusNotice(
        message: 'You are spectating this game. Sit tight while the summoners get ready.',
        tone: NoticeTone.info,
      );
    } else if (!hasAcknowledged) {
      action = HextechButton(
        label: 'I know my role',
        onPressed: _hasRevealed ? _acknowledge : null,
        disabledReason: _hasRevealed ? null : 'Reveal your card first',
      );
    } else {
      action = StatusNotice(
        message: waitingOn > 0 ? 'Locked in. Waiting for $waitingOn more…' : 'Locked in. Everyone is ready.',
        tone: NoticeTone.success,
        pulse: waitingOn > 0,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PhaseHeader(
                  eyebrow: 'ROLE REVEAL',
                  title: 'Your identity',
                  subtitle: "Hold the card. Don't let anyone see.",
                ),
                const SizedBox(height: 20),
                card,
                const SizedBox(height: 16),
                StatusNotice(
                  message: PlayerRoleScreen.rulesNote(widget.settings),
                  icon: Icons.menu_book_outlined,
                  tone: NoticeTone.info,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReadyMeter(ready: readyCount, total: totalPlayers, label: 'Summoners ready'),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      ],
    );
  }
}
