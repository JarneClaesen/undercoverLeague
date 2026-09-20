import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/models/game_settings.dart';
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
import 'package:undercoverleague/widgets/turn_timer.dart';

/// What a wordless player sees the moment the table votes them out: one
/// last chance to name the word and steal the game.
///
/// Everything the guesser has to go on is what was said at the table, so the
/// clue log (when it exists) sits right under the field. The pack is public
/// — impostors could always tell champion from item — and narrows the guess
/// to something typeable.
class LastGuessScreen extends StatefulWidget {
  final String playerName;

  /// The player's role: Mr. White or a wordless Undercover.
  final String role;

  /// The pack the word was drawn from, see [WordPack].
  final String pack;

  /// Unix ms deadline for the guess, 0 = no timer.
  final int deadline;

  /// Public clue log so far; empty when the clue log is off.
  final List<Clue> clues;

  /// Sends the guess; defaults to [LobbyService.submitGuess].
  final ValueChanged<String>? onSubmit;

  const LastGuessScreen({
    super.key,
    required this.playerName,
    required this.role,
    required this.pack,
    required this.deadline,
    this.clues = const [],
    this.onSubmit,
  });

  /// The field's placeholder per pack.
  static String placeholder(String pack) => switch (pack) {
        WordPack.champions => 'Which champion was it?',
        WordPack.items => 'Which item was it?',
        WordPack.spells => 'Which summoner spell was it?',
        WordPack.runes => 'Which rune was it?',
        WordPack.abilities => 'Which ability was it?',
        WordPack.skinLines => 'Which skin line was it?',
        WordPack.monsters => 'Which monster was it?',
        _ => 'What was the word?',
      };

  @override
  State<LastGuessScreen> createState() => _LastGuessScreenState();
}

class _LastGuessScreenState extends State<LastGuessScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    HapticFeedback.heavyImpact().catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _word => _controller.text.trim();

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _submit([String? _]) {
    if (_submitted || _word.isEmpty) return;
    try {
      (widget.onSubmit ?? LobbyService().submitGuess)(_word);
    } catch (e) {
      debugPrint('Could not submit guess: $e');
      if (mounted) showHextechSnack(context, 'Could not send your guess. Please try again.', tone: SnackTone.error);
      return;
    }
    // The server answers with the next view (game over or the next round);
    // until then the guess is in and the field is done.
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final packLabel = WordPack.label(widget.pack);
    final isMrWhite = widget.role == Role.mrWhite;

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
                  eyebrow: 'Last guess',
                  title: "You've been caught",
                  subtitle: 'Name the word and you still win the game.',
                  tone: PhaseTone.danger,
                  trailing: TurnTimer(deadline: widget.deadline),
                ),
                const SizedBox(height: 20),
                HextechPanel(
                  tone: PanelTone.danger,
                  accent: true,
                  glow: !Motion.reduced(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isMrWhite ? 'MR. WHITE, ONE LAST WORD' : 'UNDERCOVER, ONE LAST WORD',
                        style: textTheme.labelSmall?.copyWith(color: HextechColors.dangerBright, letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The table voted you out. Guess the word they were describing: '
                        'get it right and you take the win from them.',
                        style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(WordPack.icon(widget.pack), size: 16, color: hextech.accent),
                          const SizedBox(width: 8),
                          Text(
                            'THE WORD IS ONE OF THE $packLabel'.toUpperCase(),
                            style: textTheme.labelSmall?.copyWith(color: hextech.accent, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      HextechTextField(
                        controller: _controller,
                        label: _capitalize(WordPack.noun(widget.pack, 1)),
                        hint: LastGuessScreen.placeholder(widget.pack),
                        prefixIcon: Icons.psychology_alt_outlined,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        onSubmitted: _submit,
                      ),
                    ],
                  ),
                ),
                if (widget.clues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ClueLog(clues: widget.clues, you: widget.playerName),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _submitted
              ? const StatusNotice(
                  message: 'Guess sent. Waiting for the verdict…',
                  tone: NoticeTone.warning,
                  pulse: true,
                )
              : HextechButton(
                  label: 'Submit guess',
                  icon: Icons.bolt_outlined,
                  variant: HextechButtonVariant.danger,
                  disabledReason: _word.isEmpty ? 'Type your guess first' : null,
                  onPressed: _word.isEmpty ? null : _submit,
                ),
        ),
      ],
    );
  }
}
