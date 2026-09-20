import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

enum HextechButtonVariant { primary, secondary, danger }

/// Fires a light tap, swallowing the failure on platforms that have no
/// haptics engine (web, most desktops).
void hextechLightHaptic() {
  try {
    HapticFeedback.lightImpact().catchError((Object _) {});
  } catch (_) {
    // No haptics here; the tap is still handled.
  }
}

/// The app's only button.
///
/// A disabled button never explains itself with its own label (the old
/// "Need at least 3 players" trick): pass [disabledReason] and the reason is
/// rendered underneath, so the label keeps saying what the button does.
class HextechButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final HextechButtonVariant variant;

  /// Swaps the label for a spinner without changing the button's width.
  final bool busy;

  /// Shown as small grey text under the button while it is disabled.
  final String? disabledReason;
  final IconData? icon;

  /// Stretch to the available width (the default) or hug the label.
  final bool expand;

  const HextechButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = HextechButtonVariant.primary,
    this.busy = false,
    this.disabledReason,
    this.icon,
    this.expand = true,
  });

  @override
  State<HextechButton> createState() => _HextechButtonState();
}

class _HextechButtonState extends State<HextechButton> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _handleTap() {
    if (!_enabled) return;
    hextechLightHaptic();
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final textTheme = Theme.of(context).textTheme;
    final reduced = Motion.reduced(context);

    final (Color border, Color foreground, double borderWidth, Gradient? borderGradient) = switch (widget.variant) {
      HextechButtonVariant.primary => (
          hextech.accent,
          hextech.accent,
          1.5,
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HextechColors.gold, HextechColors.goldDark],
          ),
        ),
      HextechButtonVariant.secondary => (hextech.panelBorder, hextech.accent, 1.0, null),
      HextechButtonVariant.danger => (hextech.danger, HextechColors.dangerBright, 1.0, null),
    };

    final effectiveBorder = _enabled ? border : HextechColors.goldDeep;
    final effectiveForeground = _enabled ? foreground : hextech.textDisabled;
    final fill = _enabled && _hovered ? HextechColors.navyLight : hextech.panel;

    final label = Text(
      widget.label.toUpperCase(),
      textAlign: TextAlign.center,
      style: textTheme.labelLarge?.copyWith(color: effectiveForeground, letterSpacing: 1.6),
    );

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: effectiveForeground),
          const SizedBox(width: 10),
        ],
        Flexible(child: label),
      ],
    );

    // The label stays in the tree at zero opacity while busy so the button
    // keeps exactly the width it had.
    final body = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: widget.busy ? 0 : 1, child: content),
        if (widget.busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
      ],
    );

    Widget surface = AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.enter,
      decoration: BoxDecoration(
        gradient: _enabled ? borderGradient : null,
        color: borderGradient == null || !_enabled ? effectiveBorder : null,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.enter,
        color: fill,
        constraints: const BoxConstraints(minHeight: 48 - 3),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        alignment: Alignment.center,
        child: body,
      ),
    );

    surface = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: _enabled ? _handleTap : null,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onHover: (value) => setState(() => _hovered = value),
        hoverColor: Colors.transparent,
        splashColor: HextechColors.gold.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        child: surface,
      ),
    );

    surface = AnimatedScale(
      scale: !reduced && _pressed && _enabled ? 0.97 : 1.0,
      duration: Motion.of(context, Motion.fast),
      curve: Motion.enter,
      child: surface,
    );

    final showReason = widget.onPressed == null && widget.disabledReason != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.expand ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          enabled: _enabled,
          label: widget.label,
          child: widget.expand ? surface : IntrinsicWidth(child: surface),
        ),
        if (showReason)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.disabledReason!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
            ),
          ),
      ],
    );
  }
}
