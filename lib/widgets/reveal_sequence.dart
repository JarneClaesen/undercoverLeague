import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/motion.dart';

/// One clock for a whole sequenced reveal.
///
/// Every step of the game-over reveal is placed on a single timeline
/// ([RevealClock]) rather than each carrying its own delay: that is what lets
/// a tap anywhere run the *whole* sequence to its end in one move, and what
/// lets reduced motion start the clock at the end so every step is already at
/// rest on the first frame. Steps ask the clock for a [RevealWindow] (a start
/// and a length) and feed it to `flutter_animate` through [RevealWindow.adapter],
/// so the effects themselves stay the ordinary `.fadeIn()` / `.shake()` chains.
class RevealSequence extends StatefulWidget {
  /// The whole timeline; windows past this are clamped.
  final Duration length;

  /// Builds the content. [RevealClock.done] flips (with a rebuild) when the
  /// clock reaches the end, so the builder can enable controls then.
  final Widget Function(BuildContext context, RevealClock clock) builder;

  /// A tap anywhere runs the clock to the end.
  final bool skipOnTap;

  const RevealSequence({super.key, required this.length, required this.builder, this.skipOnTap = true});

  @override
  State<RevealSequence> createState() => _RevealSequenceState();
}

class _RevealSequenceState extends State<RevealSequence> with SingleTickerProviderStateMixin {
  late final RevealClock _clock;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _clock = RevealClock._(vsync: this, length: widget.length);
    _clock._controller.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion is read from the MediaQuery, which is not available in
    // initState; the clock is started exactly once, on the first frame.
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _clock._controller.value = 1;
    } else {
      _clock._controller.forward();
    }
  }

  @override
  void didUpdateWidget(RevealSequence oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.length == widget.length, 'RevealSequence.length cannot change once built.');
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock._dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _clock);
    if (!widget.skipOnTap) return content;

    // The detector stays in the tree once the clock is done (with no handler)
    // so finishing does not remount everything beneath it.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _clock.done ? null : _clock.skip,
      child: content,
    );
  }
}

/// The master timeline of a [RevealSequence].
class RevealClock {
  final AnimationController _controller;
  final Duration length;
  final Map<(Duration, Duration), RevealWindow> _windows = {};

  RevealClock._({required TickerProvider vsync, required this.length})
    : _controller = AnimationController(vsync: vsync, duration: length);

  /// 0 at the start of the sequence, 1 at its end.
  Animation<double> get master => _controller.view;

  bool get done => _controller.value >= 1;

  /// The slice of the timeline from [start] for [length]. Windows are cached
  /// by their bounds so a rebuild hands back the same instance and the
  /// `flutter_animate` adapters built on them are not re-attached each frame.
  RevealWindow window(Duration start, Duration length) {
    return _windows.putIfAbsent((start, length), () => RevealWindow._(this, start, length));
  }

  /// Runs the rest of the sequence in one short move.
  void skip() {
    if (done) return;
    _controller.animateTo(1, duration: Motion.fast, curve: Motion.exit);
  }

  void _dispose() {
    for (final window in _windows.values) {
      window._progress.dispose();
    }
    _controller.dispose();
  }
}

/// A slice of the [RevealClock]: [progress] is 0 before [start], 1 after
/// `start + length`, and linear in between. Effects supply their own curves.
class RevealWindow {
  final RevealClock clock;
  final Duration start;
  final Duration length;
  final CurvedAnimation _progress;

  RevealWindow._(this.clock, this.start, this.length)
    : _progress = CurvedAnimation(parent: clock._controller, curve: _interval(clock.length, start, length));

  static Curve _interval(Duration total, Duration start, Duration length) {
    final totalMs = total.inMilliseconds;
    if (totalMs <= 0) return const Threshold(0);
    final begin = (start.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final end = ((start + length).inMilliseconds / totalMs).clamp(0.0, 1.0);
    // A zero-length window is a switch that flips at [start].
    if (end <= begin) return Threshold(begin);
    return Interval(begin, end);
  }

  Animation<double> get progress => _progress;

  bool get done => _progress.value >= 1;

  /// Drives an [Animate] from this window. The effect chain's own timeline is
  /// laid out in wall time from [start]: a chain shorter than [length] simply
  /// finishes early, so a chip that slams in at 600 ms lands at 600 ms whether
  /// the card around it takes 900 ms or 1400 ms.
  Adapter adapter() => _WindowAdapter(this);
}

class _WindowAdapter extends Adapter {
  final RevealWindow window;
  AnimationController? _target;

  _WindowAdapter(this.window) : super(animated: false);

  double _value() {
    final chainMs = _target?.duration?.inMilliseconds ?? 0;
    if (chainMs <= 0) return window.progress.value >= 1 ? 1 : 0;
    final elapsedMs = window.progress.value * window.length.inMilliseconds;
    return (elapsedMs / chainMs).clamp(0.0, 1.0);
  }

  void _onTick() => updateValue(_value());

  @override
  void attach(AnimationController controller) {
    _target = controller;
    config(controller, _value());
    window.progress.addListener(_onTick);
  }

  @override
  void detach() {
    window.progress.removeListener(_onTick);
    _target = null;
    super.detach();
  }

  // [Animate] re-attaches its adapter whenever a rebuild hands it a different
  // one; two adapters on the same window are the same adapter.
  @override
  bool operator ==(Object other) => other is _WindowAdapter && other.window == window;

  @override
  int get hashCode => window.hashCode;
}
