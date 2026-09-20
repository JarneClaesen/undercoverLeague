import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/ready_meter.dart';
import 'package:undercoverleague/widgets/turn_order_strip.dart';

/// What an eliminated player sees for the rest of the game.
///
/// Being out is not the same as being gone: the round keeps running and the
/// spectator still wants to watch it, so the panel keeps following the live
/// turn order and vote count rather than parking on a dead end screen.
class EliminatedView extends StatefulWidget {
  final Lobby lobby;
  final String playerName;

  const EliminatedView({super.key, required this.lobby, required this.playerName});

  @override
  State<EliminatedView> createState() => _EliminatedViewState();
}

class _EliminatedViewState extends State<EliminatedView> with SingleTickerProviderStateMixin {
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(vsync: this, duration: Motion.slow);

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
    final describing = lobby.gamePhase == 'playing' && !lobby.roundFinished;
    final voting = lobby.gamePhase == 'playing' && lobby.roundFinished;
    final votesCast = lobby.alivePlayers.where(lobby.votes.containsKey).length;

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HextechPanel(
            tone: PanelTone.danger,
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ELIMINATED',
                  style: textTheme.headlineMedium?.copyWith(color: HextechColors.dangerBright),
                ),
                const SizedBox(height: 10),
                Text(
                  remaining == 1
                      ? '1 summoner remains'
                      : '$remaining summoners remain',
                  style: textTheme.bodyLarge?.copyWith(color: hextech.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          HextechPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  describing ? 'STILL DESCRIBING' : voting ? 'THE TABLE IS VOTING' : 'FOLLOWING ALONG',
                  style: textTheme.labelSmall
                      ?.copyWith(color: hextech.textSecondary, letterSpacing: 3),
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
                else
                  Text(
                    'Waiting for the game to move on…',
                    style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
                  ),
              ],
            ),
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
}
