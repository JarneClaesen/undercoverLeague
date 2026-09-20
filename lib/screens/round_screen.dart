import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/turn_order_strip.dart';

/// Body of a describing round. Rendered inside GameScreen's scaffold; the peek
/// card is docked by the shell so it survives the round → voting swap.
///
/// The one thing this screen has to get across without being read is *whose
/// turn it is*, so the moment it becomes yours the panel glows, pulses once and
/// fires a haptic — a player who has put the phone down still notices.
class RoundScreen extends StatefulWidget {
  final String? currentPlayer;
  final int currentPlayerIndex;
  final bool isCurrentPlayer;
  final List<String> roundOrder;
  final String playerName;
  final String? lastEliminated;

  const RoundScreen({
    super.key,
    required this.currentPlayer,
    required this.currentPlayerIndex,
    required this.isCurrentPlayer,
    required this.roundOrder,
    required this.playerName,
    this.lastEliminated,
  });

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> with SingleTickerProviderStateMixin {
  bool _ending = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: Motion.slow);
  }

  @override
  void didUpdateWidget(RoundScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only the false → true edge: a rebuild during your own turn is not news.
    if (widget.isCurrentPlayer && !oldWidget.isCurrentPlayer) {
      HapticFeedback.heavyImpact().catchError((Object _) {});
      if (!Motion.reduced(context)) _pulse.forward(from: 0);
    }
    if (widget.currentPlayerIndex != oldWidget.currentPlayerIndex && _ending) {
      // The turn moved on; the button has nothing left to wait for.
      setState(() => _ending = false);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _endTurn() async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      LobbyService().nextPlayer(widget.currentPlayerIndex);
      // The next view arrives shortly; hold the button until then so a second
      // tap cannot end somebody else's turn.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Error ending turn: $e');
      if (mounted) {
        showHextechSnack(context, 'Could not end your turn. Please try again.', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final current = widget.currentPlayer;
    final total = widget.roundOrder.length;
    final yours = widget.isCurrentPlayer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhaseHeader(
                  eyebrow: 'ROUND · DESCRIBING',
                  title: yours ? 'Your turn' : '${current ?? 'Waiting'}\'s turn',
                  subtitle: total > 0
                      ? 'Turn ${widget.currentPlayerIndex + 1} of $total'
                      : 'Waiting for the next turn…',
                  tone: yours ? PhaseTone.accent : PhaseTone.neutral,
                ),
                if (widget.lastEliminated != null) ...[
                  const SizedBox(height: 16),
                  StatusNotice(
                    message: widget.lastEliminated!.isEmpty
                        ? 'Nobody was eliminated in the last vote'
                        : '${widget.lastEliminated} was eliminated in the last vote',
                    tone: widget.lastEliminated!.isEmpty ? NoticeTone.info : NoticeTone.danger,
                  ),
                ],
                const SizedBox(height: 20),
                TurnOrderStrip(
                  order: widget.roundOrder,
                  currentIndex: widget.currentPlayerIndex,
                  you: widget.playerName,
                ),
                const SizedBox(height: 20),
                _pulsed(
                  HextechPanel(
                    accent: yours,
                    glow: yours,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          yours ? 'YOU ARE DESCRIBING' : 'NOW DESCRIBING',
                          style: textTheme.labelSmall
                              ?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          current ?? 'Waiting…',
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge
                              ?.copyWith(color: yours ? hextech.accentGlow : hextech.accent),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          yours
                              ? 'Give one clue about your word. Say too much and the Undercover learns it too.'
                              : 'One clue each. Hold your card at the bottom if you need a reminder.',
                          style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: yours
              ? HextechButton(
                  label: 'End my turn',
                  busy: _ending,
                  onPressed: _ending ? null : _endTurn,
                )
              : StatusNotice(
                  message: current == null
                      ? 'Waiting for the next turn…'
                      : 'Listen closely to $current…',
                  tone: NoticeTone.info,
                  pulse: true,
                ),
        ),
      ],
    );
  }

  /// A single scale beat, used the moment the turn lands on you.
  Widget _pulsed(Widget child) {
    return AnimatedBuilder(
      animation: _pulse,
      child: child,
      builder: (context, inner) {
        final t = _pulse.value;
        // Out to 1.03 and back, once.
        final scale = 1 + 0.03 * (t == 0 || t == 1 ? 0 : (t < 0.5 ? t * 2 : (1 - t) * 2));
        return Transform.scale(scale: scale, child: inner);
      },
    );
  }
}
