import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// What a panel is saying about its contents.
enum PanelTone { neutral, danger, success }

/// The app's one container: a navy plate with a hairline border and small
/// painted corner notches, in the style of the League client's frames.
///
/// [accent] promotes the border from the inactive gold to the bright one;
/// [glow] adds an outer hextech-blue halo and is how "it is your turn" is said.
class HextechPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final bool glow;
  final PanelTone tone;

  const HextechPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent = false,
    this.glow = false,
    this.tone = PanelTone.neutral,
  });

  Color _borderColor(BuildContext context) {
    final hextech = context.hextech;
    return switch (tone) {
      PanelTone.danger => accent ? HextechColors.dangerBright : hextech.danger,
      PanelTone.success => hextech.success,
      PanelTone.neutral => accent ? hextech.accent : hextech.panelBorder,
    };
  }

  Color _fillTint(BuildContext context) => switch (tone) {
        PanelTone.danger => context.hextech.danger.withValues(alpha: 0.10),
        PanelTone.success => context.hextech.success.withValues(alpha: 0.08),
        PanelTone.neutral => Colors.transparent,
      };

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final border = _borderColor(context);

    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      curve: Motion.enter,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(_fillTint(context), hextech.panel.withValues(alpha: 0.92)),
            Color.alphaBlend(_fillTint(context), HextechColors.abyss.withValues(alpha: 0.92)),
          ],
        ),
        border: Border.all(color: border),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: hextech.accentGlow.withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: CustomPaint(
        foregroundPainter: _CornerNotchPainter(color: border),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Four 10px L-shaped ticks, one per corner, drawn just inside the border.
class _CornerNotchPainter extends CustomPainter {
  final Color color;

  const _CornerNotchPainter({required this.color});

  static const double _length = 10;
  static const double _inset = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final left = _inset;
    final top = _inset;
    final right = size.width - _inset;
    final bottom = size.height - _inset;
    if (right - left < _length * 2 || bottom - top < _length * 2) return;

    final path = Path()
      // Top-left.
      ..moveTo(left, top + _length)
      ..lineTo(left, top)
      ..lineTo(left + _length, top)
      // Top-right.
      ..moveTo(right - _length, top)
      ..lineTo(right, top)
      ..lineTo(right, top + _length)
      // Bottom-right.
      ..moveTo(right, bottom - _length)
      ..lineTo(right, bottom)
      ..lineTo(right - _length, bottom)
      // Bottom-left.
      ..moveTo(left + _length, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, bottom - _length);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerNotchPainter oldDelegate) => oldDelegate.color != color;
}
