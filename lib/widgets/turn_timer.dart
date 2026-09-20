import 'dart:async';

import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Counts down to a server deadline: a small pill with a clock glyph and the
/// time left, refreshed every quarter second so the seconds never skip.
///
/// The server owns the clock — it ends the turn, closes the vote or scores a
/// blank guess by itself when the time is up — so this widget only *shows*
/// the deadline and never sends anything. An overdue deadline sits at 0:00
/// until the next view arrives. A [deadline] of 0 means no timer is running
/// and nothing is drawn.
class TurnTimer extends StatefulWidget {
  /// Unix milliseconds, as the view carries it; 0 = no timer.
  final int deadline;

  /// Smaller pill for inline use next to a heading.
  final bool compact;

  /// The clock the countdown compares against; tests swap in a fake one.
  final DateTime Function() now;

  /// Under this many seconds the pill turns red and breathes.
  static const Duration urgent = Duration(seconds: 10);

  static const Duration _tick = Duration(milliseconds: 250);

  static DateTime _wallClock() => DateTime.now();

  const TurnTimer({
    super.key,
    required this.deadline,
    this.compact = false,
    this.now = _wallClock,
  });

  /// How the remaining time is written: `1:05`, `0:42`, `0:00`.
  static String format(Duration remaining) {
    final total = remaining.isNegative ? 0 : remaining.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  State<TurnTimer> createState() => _TurnTimerState();
}

class _TurnTimerState extends State<TurnTimer> with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _syncTicker();
  }

  @override
  void didUpdateWidget(TurnTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deadline != oldWidget.deadline) _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Duration get _remaining {
    final left = widget.deadline - widget.now().millisecondsSinceEpoch;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  /// Only tick while there is a deadline to count down; a stopped timer
  /// costs nothing.
  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.deadline == 0) return;
    _ticker = Timer.periodic(TurnTimer._tick, (_) {
      if (mounted) setState(() {});
    });
  }

  /// Breathes in the last seconds, once; stops again as soon as a new
  /// deadline lands or motion is reduced.
  void _syncPulse(bool urgent) {
    final wants = urgent && !Motion.reduced(context);
    if (wants && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!wants && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadline == 0) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final remaining = _remaining;
    final urgent = remaining <= TurnTimer.urgent;
    _syncPulse(urgent);

    final colour = urgent ? HextechColors.dangerBright : hextech.accentGlow;
    final style = (widget.compact ? textTheme.labelMedium : textTheme.labelLarge)
        ?.copyWith(color: colour, letterSpacing: 1.2, fontFeatures: const [FontFeature.tabularFigures()]);
    final glyph = widget.compact ? 14.0 : 16.0;

    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 10, vertical: widget.compact ? 3 : 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        border: Border.all(color: colour.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: glyph, color: colour),
          const SizedBox(width: 6),
          Text(TurnTimer.format(remaining), style: style),
        ],
      ),
    );

    return Semantics(
      liveRegion: urgent,
      label: '${TurnTimer.format(remaining)} left',
      child: AnimatedBuilder(
        animation: _pulse,
        child: pill,
        builder: (context, child) {
          final t = _pulse.value;
          return Transform.scale(
            scale: 1 + 0.04 * t,
            child: Opacity(opacity: 1 - 0.25 * t, child: child),
          );
        },
      ),
    );
  }
}
