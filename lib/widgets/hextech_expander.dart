import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/motion_size.dart';

/// A [HextechPanel] whose body folds away under a tappable header: title,
/// optional subtitle and leading widget, and a chevron that turns as the
/// panel opens. The body's room animates so the list below does not jump.
class HextechExpander extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget child;
  final bool initiallyExpanded;

  /// Promotes the panel border, like [HextechPanel.accent].
  final bool accent;

  const HextechExpander({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.child,
    this.initiallyExpanded = false,
    this.accent = false,
  });

  @override
  State<HextechExpander> createState() => _HextechExpanderState();
}

class _HextechExpanderState extends State<HextechExpander> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final reduced = Motion.reduced(context);
    final duration = reduced ? Duration.zero : Motion.base;
    final body = _expanded
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: widget.child,
          )
        : const SizedBox(width: double.infinity);

    return HextechPanel(
      padding: EdgeInsets.zero,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(color: hextech.textPrimary),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: duration,
                    curve: Motion.enter,
                    child: Icon(Icons.expand_more, color: hextech.accent),
                  ),
                ],
              ),
            ),
          ),
          MotionSize(duration: duration, child: body),
        ],
      ),
    );
  }
}
