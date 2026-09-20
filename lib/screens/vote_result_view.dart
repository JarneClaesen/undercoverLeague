import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/status_notice.dart';

/// The interstitial that replays a finished vote.
///
/// The elimination used to be a single line of text, which is a poor return on
/// the most dramatic moment of the round. Here the ballot is dealt out one bar
/// at a time — who each summoner voted for, how the count landed, and only then
/// the name being struck through. The ballot is already tallied by the time the
/// server sends it, so naming the voters gives nothing away.
///
/// The caller owns how long this stays up (roughly four seconds) and calls
/// [onDone]; tapping anywhere skips ahead.
class VoteResultView extends StatefulWidget {
  /// The finished ballot: voter -> the name they voted for, or `'skip'`.
  final Map<String, String> lastVotes;

  /// Everyone who could be voted for — the players alive when the vote opened,
  /// including whoever was eliminated by it.
  final List<String> candidates;

  /// The player the vote removed. Null or empty means a tie or a skip, i.e.
  /// nobody went out.
  final String? eliminated;

  /// The viewer, so their own row is marked.
  final String you;

  /// Called when the interstitial is done, and when the viewer taps to skip it.
  final VoidCallback onDone;

  const VoteResultView({
    super.key,
    required this.lastVotes,
    required this.candidates,
    required this.eliminated,
    required this.you,
    required this.onDone,
  });

  @override
  State<VoteResultView> createState() => _VoteResultViewState();
}

class _VoteResultViewState extends State<VoteResultView> with SingleTickerProviderStateMixin {
  /// The vote value that means "eliminate nobody".
  static const String _skip = 'skip';

  /// How far each bar lags behind the one above it.
  static const Duration _stagger = Duration(milliseconds: 80);

  static const double _barHeight = 8;

  late List<_TallyRow> _rows;
  late final AnimationController _controller;

  /// True once every bar has finished growing: the point at which the
  /// eliminated row is allowed to flash and strike itself through.
  bool _barsDone = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _rows = _tally();
    _controller = AnimationController(vsync: this, duration: _barsDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted && !_barsDone) {
          setState(() => _barsDone = true);
        }
      });
    // One tap as the result lands. Web and most desktops have no haptics
    // engine; failing there must not take the screen down.
    try {
      HapticFeedback.mediumImpact().catchError((Object _) {});
    } catch (_) {
      // No haptics here.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is only readable from here, so the first run starts now
    // rather than in initState.
    if (_started) return;
    _started = true;
    _play();
  }

  @override
  void didUpdateWidget(VoteResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.lastVotes, widget.lastVotes) ||
        !listEquals(oldWidget.candidates, widget.candidates) ||
        oldWidget.eliminated != widget.eliminated) {
      _rows = _tally();
      _barsDone = false;
      _play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    _controller.duration = _barsDuration;
    if (Motion.reduced(context)) {
      // Reduced motion: the finished tally, immediately.
      _controller.value = 1;
      _barsDone = true;
    } else {
      _controller.forward(from: 0);
    }
  }

  Duration get _barsDuration =>
      Motion.slow + _stagger * (_rows.isEmpty ? 0 : _rows.length - 1);

  String get _eliminated => widget.eliminated ?? '';

  /// Counts the ballot into the rows the screen draws: one per candidate,
  /// most votes first, with the abstentions last.
  List<_TallyRow> _tally() {
    final voters = <String, List<String>>{
      for (final candidate in widget.candidates) candidate: <String>[],
    };
    final abstained = <String>[];

    for (final entry in widget.lastVotes.entries) {
      if (entry.value == _skip) {
        abstained.add(entry.key);
        continue;
      }
      // A vote for somebody outside [candidates] should not happen, but
      // dropping it silently would make the counts lie.
      voters.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }

    final rows = <_TallyRow>[];
    var index = 0;
    for (final entry in voters.entries) {
      rows.add(_TallyRow(
        name: entry.key,
        voters: entry.value..sort(),
        order: index++,
      ));
    }
    rows.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.order.compareTo(b.order);
    });
    if (abstained.isNotEmpty) {
      rows.add(_TallyRow(
        name: 'Abstain',
        voters: abstained..sort(),
        order: rows.length,
        isAbstain: true,
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = _rows.fold<int>(0, (acc, row) => row.count > acc ? row.count : acc);

    return GestureDetector(
      onTap: widget.onDone,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhaseHeader(
                  eyebrow: 'The votes are in',
                  title: _eliminated.isEmpty ? 'No one eliminated' : '$_eliminated is out',
                  tone: _eliminated.isEmpty ? PhaseTone.neutral : PhaseTone.danger,
                ),
                const SizedBox(height: 20),
                for (final (index, row) in _rows.indexed) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _row(context, index, row, maxCount),
                ],
                if (_rows.isEmpty)
                  const StatusNotice(message: 'Nobody cast a vote.', tone: NoticeTone.info),
                const SizedBox(height: 20),
                const StatusNotice(
                  message: 'Tap to continue',
                  icon: Icons.touch_app_outlined,
                  tone: NoticeTone.info,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index, _TallyRow row, int maxCount) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final isOut = !row.isAbstain && row.name == _eliminated && _eliminated.isNotEmpty;
    final struck = isOut && _barsDone;

    final barColour = isOut
        ? HextechColors.dangerBright
        : row.isAbstain
            ? hextech.textSecondary
            : hextech.accent;

    final panel = HextechPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      tone: isOut ? PanelTone.danger : PanelTone.neutral,
      accent: struck,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (row.isAbstain) ...[
                Icon(Icons.do_not_disturb_alt_outlined, size: 16, color: hextech.textSecondary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(
                          color: row.isAbstain ? hextech.textSecondary : hextech.textPrimary,
                          decoration: struck ? TextDecoration.lineThrough : null,
                          decorationColor: hextech.danger,
                        ),
                      ),
                    ),
                    if (!row.isAbstain && row.name == widget.you) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(you)',
                        style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${row.count}',
                style: textTheme.titleMedium?.copyWith(color: barColour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bar(index, maxCount == 0 ? 0 : row.count / maxCount, barColour),
          const SizedBox(height: 6),
          Text(
            row.voters.isEmpty ? 'No votes' : row.voters.join(', '),
            style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
          ),
        ],
      ),
    );

    if (!isOut) return panel;

    // The elimination lands after the bars: a single red wash over the row,
    // keyed so it replays the moment the tally finishes.
    return TweenAnimationBuilder<double>(
      key: ValueKey(_barsDone),
      tween: Tween<double>(begin: _barsDone ? 1 : 0, end: 0),
      duration: Motion.of(context, Motion.base),
      curve: Motion.exit,
      builder: (context, flash, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: HextechColors.dangerBright.withValues(alpha: 0.35 * flash),
        ),
        child: child,
      ),
      child: panel,
    );
  }

  /// One bar, growing from nothing to its share of the largest count. Row
  /// [index] starts [_stagger] later than the one above it and still takes
  /// [Motion.slow] to fill.
  Widget _bar(int index, double fraction, Color colour) {
    final total = _barsDuration.inMilliseconds;
    final begin = total == 0 ? 0.0 : (_stagger.inMilliseconds * index) / total;
    final end = total == 0 ? 1.0 : begin + Motion.slow.inMilliseconds / total;

    return SizedBox(
      height: _barHeight,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: HextechColors.goldDeep)),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = end <= begin
                    ? 1.0
                    : ((_controller.value - begin) / (end - begin)).clamp(0.0, 1.0);
                final grown = fraction * Motion.enter.transform(t);
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: grown.clamp(0.0, 1.0),
                  child: ColoredBox(color: colour),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the tally.
class _TallyRow {
  final String name;
  final List<String> voters;

  /// Position in the candidate list, used to break ties in the sort.
  final int order;
  final bool isAbstain;

  _TallyRow({
    required this.name,
    required this.voters,
    required this.order,
    this.isAbstain = false,
  });

  int get count => voters.length;
}
