import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

enum PhaseTone { neutral, accent, danger }

/// States what is happening right now: a small grey eyebrow ("ROUND 2 ·
/// DESCRIBING"), a Cinzel title, an optional subtitle. Keyed on [title] so a
/// change in phase fades and slides instead of snapping. [trailing] sits on
/// the right of the eyebrow line, outside the swap — the turn timer lives
/// there and must not fade with every title change.
class PhaseHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final PhaseTone tone;
  final Widget? trailing;

  const PhaseHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.tone = PhaseTone.neutral,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final titleColour = switch (tone) {
      PhaseTone.neutral => hextech.accent,
      PhaseTone.accent => hextech.accentGlow,
      PhaseTone.danger => HextechColors.dangerBright,
    };

    final content = Column(
      key: ValueKey('$eyebrow|$title|$subtitle'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title.toUpperCase(),
          style: textTheme.headlineSmall?.copyWith(color: titleColour),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary)),
        ],
      ],
    );

    final switcher = AnimatedSwitcher(
      duration: Motion.of(context, Motion.base),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [...previousChildren, ?currentChild],
      ),
      child: content,
    );

    if (trailing == null) return switcher;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: switcher),
        const SizedBox(width: 12),
        trailing!,
      ],
    );
  }
}
