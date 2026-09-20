import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Floats every reaction in the room up from the bottom of the screen.
///
/// Mounted once by the game shell over whatever phase is showing, so a
/// reaction thrown during a vote is still on screen when the tally lands.
/// Each emoji rises for about two seconds with the sender's name in a small
/// chip under it, at a random column so a burst of them does not stack into
/// one pillar. Reactions are ephemeral: they are never in the view and never
/// replayed, so a listener that misses one simply misses it.
class ReactionOverlay extends StatefulWidget {
  /// Where reactions come from; defaults to the live connection.
  final Stream<Reaction>? reactions;

  /// The most floating at once; the oldest is dropped past this.
  static const int maxConcurrent = 12;

  /// How long one emoji takes to rise and fade.
  static const Duration flight = Duration(milliseconds: 1800);

  /// Under reduced motion the chip simply appears, holds, and vanishes.
  static const Duration hold = Duration(milliseconds: 1200);

  const ReactionOverlay({super.key, this.reactions});

  @override
  State<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _ReactionOverlayState extends State<ReactionOverlay> {
  StreamSubscription<Reaction>? _subscription;
  final List<_Floating> _floating = [];
  final math.Random _random = math.Random();
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ReactionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reactions != oldWidget.reactions) _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = (widget.reactions ?? GameConnection.instance.reactions).listen(_onReaction);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onReaction(Reaction reaction) {
    if (!mounted) return;
    setState(() {
      while (_floating.length >= ReactionOverlay.maxConcurrent) {
        _floating.removeAt(0);
      }
      _floating.add(_Floating(
        id: _nextId++,
        reaction: reaction,
        // Kept off the very edges so the name chip never clips.
        x: 0.1 + _random.nextDouble() * 0.8,
        drift: (_random.nextDouble() - 0.5) * 0.08,
      ));
    });
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _floating.removeWhere((f) => f.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              // Laid out but never painted: on the web the emoji come from a
              // fallback font that is only fetched the first time a glyph is
              // needed, and a reaction is gone before that finishes. Shaping
              // the whole set once here has the font ready for the real one.
              Positioned(
                left: 0,
                top: 0,
                child: Offstage(
                  child: Text(reactionEmoji.join(), style: textTheme.displaySmall),
                ),
              ),
              for (final f in _floating)
                _FloatingReaction(
                  key: ValueKey(f.id),
                  floating: f,
                  size: constraints.biggest,
                  onDone: () => _remove(f.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Floating {
  final int id;
  final Reaction reaction;

  /// Horizontal position as a fraction of the width, and how far it drifts
  /// sideways on the way up.
  final double x;
  final double drift;

  const _Floating({required this.id, required this.reaction, required this.x, required this.drift});
}

/// One rising emoji. Built as a [Positioned] straight under the overlay's
/// [Stack], with the stack's [size] passed in rather than measured here, since
/// a layout widget in between would break the positioning.
class _FloatingReaction extends StatefulWidget {
  final _Floating floating;
  final Size size;
  final VoidCallback onDone;

  const _FloatingReaction({super.key, required this.floating, required this.size, required this.onDone});

  @override
  State<_FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<_FloatingReaction> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hold;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: ReactionOverlay.flight)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      // No flight: the chip sits where it appeared and is gone after a beat.
      _hold = Timer(ReactionOverlay.hold, widget.onDone);
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final reduced = Motion.reduced(context);
    final f = widget.floating;

    final chip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(f.reaction.emoji, style: textTheme.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: hextech.panel.withValues(alpha: 0.9),
            border: Border.all(color: hextech.panelBorder),
          ),
          child: Text(
            f.reaction.playerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(color: hextech.textPrimary),
          ),
        ),
      ],
    );

    final width = widget.size.width;
    final height = widget.size.height;
    final chipWidth = math.min(140.0, width * 0.4);

    return AnimatedBuilder(
      animation: _controller,
      child: SizedBox(width: chipWidth, child: chip),
      builder: (context, child) {
        final t = reduced ? 0.0 : Motion.enter.transform(_controller.value);
        // Rises through the lower two thirds of the screen and fades out over
        // the last stretch; a touch of sideways drift keeps a burst of the
        // same emoji from looking like one.
        final bottom = 24 + t * height * 0.6;
        final left = (f.x + f.drift * t) * width - chipWidth / 2;
        final opacity = reduced ? 1.0 : (t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3);
        return Positioned(
          left: left.clamp(0.0, math.max(0.0, width - chipWidth)),
          bottom: reduced ? height * 0.25 : bottom,
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        );
      },
    );
  }
}
