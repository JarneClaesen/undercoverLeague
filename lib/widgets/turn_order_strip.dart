import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Two letters for a medallion. Shared by every strip so the abbreviation a
/// player sees for a name never changes between screens.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final word = parts.first;
    return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
  }
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

/// The speaking order, left to right: who has been, who is up, who is next.
///
/// The strip answers "how long until me?" without anybody having to count, and
/// it keeps the current speaker scrolled into view as the turn moves on.
class TurnOrderStrip extends StatefulWidget {
  final List<String> order;
  final int currentIndex;

  /// The viewer's own name, drawn with a hextech-blue ring.
  final String you;
  final bool compact;

  const TurnOrderStrip({
    super.key,
    required this.order,
    required this.currentIndex,
    required this.you,
    this.compact = false,
  });

  @override
  State<TurnOrderStrip> createState() => _TurnOrderStripState();
}

class _TurnOrderStripState extends State<TurnOrderStrip> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
  }

  @override
  void didUpdateWidget(TurnOrderStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.length != _keys.length) _rebuildKeys();
    if (widget.currentIndex != oldWidget.currentIndex ||
        !listEquals(widget.order, oldWidget.order)) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildKeys() {
    _keys = List.generate(widget.order.length, (_) => GlobalKey());
    _scrollToCurrent();
  }

  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.currentIndex;
      if (index < 0 || index >= _keys.length) return;
      final target = _keys[index].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: Motion.of(context, Motion.base),
        curve: Motion.enter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    if (widget.order.isEmpty) return const SizedBox.shrink();

    final diameter = widget.compact ? 34.0 : 44.0;
    final nextIndex = widget.currentIndex + 1;
    final hasNext = nextIndex >= 0 && nextIndex < widget.order.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: diameter + (widget.compact ? 26 : 30),
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: widget.order.length,
            separatorBuilder: (_, _) => SizedBox(width: widget.compact ? 8 : 12),
            itemBuilder: (context, index) {
              final name = widget.order[index];
              return _Medallion(
                key: _keys[index],
                name: name,
                diameter: diameter,
                isCurrent: index == widget.currentIndex,
                isPast: index < widget.currentIndex,
                isYou: name == widget.you,
              );
            },
          ),
        ),
        if (hasNext) ...[
          const SizedBox(height: 4),
          Text(
            'Up next: ${widget.order[nextIndex]}',
            style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _Medallion extends StatelessWidget {
  final String name;
  final double diameter;
  final bool isCurrent;
  final bool isPast;
  final bool isYou;

  const _Medallion({
    super.key,
    required this.name,
    required this.diameter,
    required this.isCurrent,
    required this.isPast,
    required this.isYou,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    final ring = isYou
        ? hextech.accentGlow
        : isCurrent
            ? hextech.accent
            : hextech.panelBorder;

    final circle = AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      curve: Motion.enter,
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent ? HextechColors.navyLight : HextechColors.navy,
        border: Border.all(color: ring, width: isCurrent || isYou ? 2 : 1),
        boxShadow: isCurrent
            ? [BoxShadow(color: hextech.accentGlow.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1)]
            : const [],
      ),
      alignment: Alignment.center,
      child: Text(
        initialsOf(name),
        style: textTheme.labelSmall?.copyWith(
          color: isPast ? hextech.textDisabled : hextech.textPrimary,
          letterSpacing: 0.5,
        ),
      ),
    );

    return Opacity(
      opacity: isPast ? 0.45 : 1,
      child: SizedBox(
        width: diameter + 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isCurrent && !Motion.reduced(context) ? 1.15 : 1,
              duration: Motion.of(context, Motion.base),
              curve: Motion.enter,
              child: circle,
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: isCurrent ? hextech.accent : hextech.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
