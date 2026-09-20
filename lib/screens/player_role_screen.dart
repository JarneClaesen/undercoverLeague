import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
class PlayerRoleScreen extends StatefulWidget {
  final String playerName;
  final String role;
  final String word;
  final String icon;
  final bool isChampion;
  final Map<String, bool> rolesAcknowledged;

  const PlayerRoleScreen({
    super.key,
    required this.playerName,
    required this.role,
    required this.word,
    required this.icon,
    required this.isChampion,
    required this.rolesAcknowledged,
  });

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
    final isSpectator = widget.role == 'Spectator';
    final waitingOn = (totalPlayers - readyCount).clamp(0, totalPlayers);

    Widget card = RevealCard(
      role: widget.role,
      word: widget.word,
      icon: widget.icon,
      isChampion: widget.isChampion,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 24),
          ReadyMeter(ready: readyCount, total: totalPlayers, label: 'Summoners ready'),
          const SizedBox(height: 20),
          if (isSpectator)
            const StatusNotice(
              message: 'You are spectating this game. Sit tight while the summoners get ready.',
              tone: NoticeTone.info,
            )
          else if (!hasAcknowledged)
            HextechButton(
              label: 'I know my role',
              onPressed: _hasRevealed ? _acknowledge : null,
              disabledReason: _hasRevealed ? null : 'Reveal your card first',
            )
          else
            StatusNotice(
              message: waitingOn > 0
                  ? 'Locked in. Waiting for $waitingOn more…'
                  : 'Locked in. Everyone is ready.',
              tone: NoticeTone.success,
              pulse: waitingOn > 0,
            ),
        ],
      ),
    );
  }
}
