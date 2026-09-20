import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/hextech_text_field.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/turn_order_strip.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';

/// Body of a describing round. Rendered inside GameScreen's scaffold; the peek
/// card is docked by the shell so it survives the round → voting swap.
///
/// The one thing this screen has to get across without being read is *whose
/// turn it is*, so the moment it becomes yours the panel glows, pulses once and
/// fires a haptic — a player who has put the phone down still notices.
///
/// With the clue log on, a turn ends by typing the clue instead of tapping
/// "end my turn": the server refuses a bare `nextPlayer` in that mode, and
/// everyone gets the log under the strip.
class RoundScreen extends StatefulWidget {
  final String? currentPlayer;
  final int currentPlayerIndex;
  final bool isCurrentPlayer;
  final List<String> roundOrder;
  final String playerName;
  final String? lastEliminated;

  /// 1-based describing round.
  final int round;

  /// Unix ms deadline of the current turn; 0 = no timer.
  final int deadline;

  /// Whether turns end with a typed clue.
  final bool clueLog;
  final List<Clue> clues;

  const RoundScreen({
    super.key,
    required this.currentPlayer,
    required this.currentPlayerIndex,
    required this.isCurrentPlayer,
    required this.roundOrder,
    required this.playerName,
    this.lastEliminated,
    this.round = 0,
    this.deadline = 0,
    this.clueLog = false,
    this.clues = const [],
  });

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> with SingleTickerProviderStateMixin {
  bool _ending = false;
  late final AnimationController _pulse;
  final TextEditingController _clue = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: Motion.slow);
    _clue.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(RoundScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only the false → true edge: a rebuild during your own turn is not news.
    if (widget.isCurrentPlayer && !oldWidget.isCurrentPlayer) {
      HapticFeedback.heavyImpact().catchError((Object _) {});
      if (!Motion.reduced(context)) _pulse.forward(from: 0);
    }
    if (widget.currentPlayerIndex != oldWidget.currentPlayerIndex ||
        widget.round != oldWidget.round ||
        widget.currentPlayer != oldWidget.currentPlayer) {
      // The turn moved on: the button has nothing left to wait for, and a
      // clue still in the field belonged to the turn that just ended.
      if (_clue.text.isNotEmpty) _clue.clear();
      if (_ending) setState(() => _ending = false);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _clue.dispose();
    super.dispose();
  }

  String get _clueText => _clue.text.trim();

  bool get _clueTooLong => _clueText.runes.length > maxClueLength;

  Future<void> _submitClue([String? _]) async {
    if (_ending || _clueText.isEmpty || _clueTooLong) return;
    setState(() => _ending = true);
    try {
      LobbyService().submitClue(_clueText, widget.currentPlayerIndex);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Error submitting clue: $e');
      if (mounted) {
        showHextechSnack(context, 'Could not send your clue. Please try again.', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _ending = false);
    }
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
                  eyebrow: widget.round > 0 ? 'ROUND ${widget.round} · DESCRIBING' : 'ROUND · DESCRIBING',
                  title: yours ? 'Your turn' : '${current ?? 'Waiting'}\'s turn',
                  subtitle: total > 0
                      ? 'Turn ${widget.currentPlayerIndex + 1} of $total'
                      : 'Waiting for the next turn…',
                  tone: yours ? PhaseTone.accent : PhaseTone.neutral,
                  trailing: TurnTimer(deadline: widget.deadline),
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
                              ? widget.clueLog
                                  ? 'Say your clue, then type it below: it stays in the log for everyone to weigh.'
                                  : 'Give one clue about your word. Say too much and the Undercover learns it too.'
                              : 'One clue each. Hold your card at the bottom if you need a reminder.',
                          style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
                        ),
                        if (yours && widget.clueLog) ...[
                          const SizedBox(height: 14),
                          HextechTextField(
                            controller: _clue,
                            label: 'Your clue',
                            hint: 'One word, or a few',
                            prefixIcon: Icons.edit_outlined,
                            maxLength: maxClueLength,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            errorText: _clueTooLong ? 'Clues must be $maxClueLength characters or fewer.' : null,
                            onSubmitted: _submitClue,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.clueLog) ...[
                  const SizedBox(height: 16),
                  ClueLog(clues: widget.clues, you: widget.playerName),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: yours
              ? widget.clueLog
                  ? HextechButton(
                      label: 'Submit clue',
                      icon: Icons.send_outlined,
                      busy: _ending,
                      disabledReason: _clueText.isEmpty ? 'Type your clue to end your turn' : null,
                      onPressed: _ending || _clueText.isEmpty || _clueTooLong ? null : _submitClue,
                    )
                  : HextechButton(
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
