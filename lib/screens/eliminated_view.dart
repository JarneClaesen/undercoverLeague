import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/reaction_bar.dart';
import 'package:undercoverleague/widgets/ready_meter.dart';
import 'package:undercoverleague/widgets/turn_order_strip.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';
import 'package:undercoverleague/widgets/word_card.dart';
import 'package:undercoverleague/widgets/word_image.dart';

/// What a player on the bench sees for the rest of the game: somebody the
/// table voted out, or a spectator who sat this one out.
///
/// Being out is not the same as being gone: the round keeps running and the
/// bench still wants to watch it, so the panel keeps following the live turn
/// order, vote count and last guess rather than parking on a dead end
/// screen — and, since the bench cannot vote, it gets the reaction bar
/// instead. A spectator additionally sees the word: they were never in the
/// game, so there is nothing to keep from them.
class EliminatedView extends StatefulWidget {
  final Lobby lobby;
  final String playerName;

  /// Sat the game out (rather than voted out of it): no red wash, the word
  /// on show, and a calmer heading.
  final bool spectator;

  const EliminatedView({super.key, required this.lobby, required this.playerName, this.spectator = false});

  @override
  State<EliminatedView> createState() => _EliminatedViewState();
}

class _EliminatedViewState extends State<EliminatedView> with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(vsync: this, duration: Motion.slow, value: widget.spectator ? 1 : 0);

    if (widget.spectator) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact().catchError((Object _) {});
      // Reduced motion skips the wash entirely rather than leaving it up.
      if (Motion.reduced(context)) {
        _flash.value = 1;
      } else {
        _flash.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final lobby = widget.lobby;
    final remaining = lobby.alivePlayers.length;
    final describing = lobby.gamePhase == GamePhase.playing && !lobby.roundFinished;
    final voting = lobby.gamePhase == GamePhase.playing && lobby.roundFinished;
    final guessing = lobby.isLastGuess;
    final votesCast = lobby.alivePlayers.where(lobby.votes.containsKey).length;
    final word = lobby.myWord;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HextechPanel(
            tone: widget.spectator ? PanelTone.neutral : PanelTone.danger,
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.spectator ? 'SPECTATING' : 'ELIMINATED',
                  style: textTheme.headlineMedium?.copyWith(
                    color: widget.spectator ? hextech.accent : HextechColors.dangerBright,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  remaining == 1 ? '1 summoner remains' : '$remaining summoners remain',
                  style: textTheme.bodyLarge?.copyWith(color: hextech.textSecondary),
                ),
              ],
            ),
          ),
          if (widget.spectator && word != null && word.isNotEmpty) ...[
            const SizedBox(height: 16),
            _wordStrip(context, word),
          ],
          const SizedBox(height: 16),
          HextechPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        describing
                            ? lobby.round > 0
                                ? 'ROUND ${lobby.round} · DESCRIBING'
                                : 'STILL DESCRIBING'
                            : voting
                                ? 'THE TABLE IS VOTING'
                                : guessing
                                    ? 'LAST GUESS'
                                    : 'FOLLOWING ALONG',
                        style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 3),
                      ),
                    ),
                    TurnTimer(deadline: lobby.deadline, compact: true),
                  ],
                ),
                const SizedBox(height: 12),
                if (describing) ...[
                  TurnOrderStrip(
                    order: lobby.roundOrder,
                    currentIndex: lobby.currentPlayerIndex,
                    you: widget.playerName,
                    compact: true,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    lobby.currentPlayer == null
                        ? 'Waiting for the next turn…'
                        : '${lobby.currentPlayer} is describing',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(color: hextech.textPrimary),
                  ),
                ] else if (voting)
                  ReadyMeter(
                    ready: votesCast,
                    total: lobby.alivePlayers.length,
                    label: 'Votes locked',
                  )
                else if (guessing)
                  Text(
                    lobby.guesser.isEmpty
                        ? 'Somebody is making a last guess at the word…'
                        : '${lobby.guesser} was caught and is making a last guess at the word…',
                    style: textTheme.bodyLarge?.copyWith(color: hextech.textPrimary),
                  )
                else
                  Text(
                    'Waiting for the game to move on…',
                    style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
                  ),
              ],
            ),
          ),
          if (lobby.settings.clueLog) ...[
            const SizedBox(height: 16),
            ClueLog(clues: lobby.clues, you: widget.playerName),
          ],
          const SizedBox(height: 16),
          const HextechPanel(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: ReactionBar(),
          ),
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        // One red wash over the whole view as the elimination lands, then gone.
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _flash,
            builder: (context, _) {
              final opacity = (1 - _flash.value).clamp(0.0, 1.0) * 0.55;
              if (opacity == 0) return const SizedBox.shrink();
              return ColoredBox(color: HextechColors.danger.withValues(alpha: opacity));
            },
          ),
        ),
      ],
    );
  }

  /// The word, face up: a sliver of the art at its own ratio next to the
  /// name. Only a spectator gets this, and only because they see it anyway.
  Widget _wordStrip(BuildContext context, String word) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final lobby = widget.lobby;
    final isChampion = lobby.selectedIsChampion;
    const width = 50.0;
    const height = width * wordCardAspect;

    return HextechPanel(
      accent: true,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: hextech.accent, width: 2)),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: wordImage(
                  context,
                  lobby.myIcon,
                  width: isChampion ? width : 40,
                  height: isChampion ? height : 40,
                  fit: isChampion ? BoxFit.cover : BoxFit.contain,
                  fallbackSize: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lobby.selectedPack.isEmpty
                      ? 'THE WORD'
                      : 'THE WORD · ${WordPack.noun(lobby.selectedPack, 1)}'.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Text(
                  word,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(color: hextech.accentGlow),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only you and the civilians know it. Keep a straight face.',
                  style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
