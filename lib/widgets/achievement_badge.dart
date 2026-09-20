import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:undercoverleague/models/achievements.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// The emblem of one achievement: its icon inside a hexagonal Hextech frame.
///
/// [earned] lights the frame in gold and the icon in the primary text colour;
/// a locked badge is drawn in the disabled greys with a small padlock over
/// its corner so the two states read apart at a glance.
class AchievementBadge extends StatelessWidget {
  final String id;
  final bool earned;
  final double size;

  const AchievementBadge({
    super.key,
    required this.id,
    this.earned = true,
    this.size = 44,
  });

  /// The glyph each achievement id is drawn with. Ids this build does not
  /// know yet get a star, like [Achievements.byId] gives them a title.
  static IconData iconFor(String id) => switch (id) {
        Achievements.survivor => Icons.shield,
        Achievements.mindReader => Icons.psychology,
        Achievements.sharpEye => Icons.visibility,
        Achievements.publicEnemy => Icons.gavel,
        Achievements.firstBlood => Icons.water_drop,
        Achievements.ironWall => Icons.fort,
        Achievements.doubleAgent => Icons.theater_comedy,
        Achievements.silentHand => Icons.back_hand,
        Achievements.veteran => Icons.military_tech,
        Achievements.unanimousJustice => Icons.balance,
        _ => Icons.star,
      };

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final frame = earned ? hextech.accent : hextech.panelBorder;
    final glyph = earned ? hextech.textPrimary : hextech.textDisabled;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _HexFramePainter(
              border: frame,
              fillTop: earned ? HextechColors.navyLight : hextech.panel,
              fillBottom: HextechColors.abyss,
              innerLine: earned ? hextech.accentGlow.withValues(alpha: 0.35) : hextech.panelBorder.withValues(alpha: 0.4),
            ),
          ),
          Icon(iconFor(id), size: size * 0.46, color: glyph),
          if (!earned)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: HextechColors.abyss,
                  shape: BoxShape.circle,
                  border: Border.all(color: hextech.panelBorder),
                ),
                child: Icon(Icons.lock, size: size * 0.24, color: hextech.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// A pointy-top hexagon: gradient fill, hairline border, and a second inner
/// hexagon just inside it for the double-frame look of a League emblem.
class _HexFramePainter extends CustomPainter {
  final Color border;
  final Color fillTop;
  final Color fillBottom;
  final Color innerLine;

  const _HexFramePainter({
    required this.border,
    required this.fillTop,
    required this.fillBottom,
    required this.innerLine,
  });

  Path _hexagon(Offset centre, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 1;
    final outer = _hexagon(centre, radius);

    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fillBottom],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      _hexagon(centre, radius - 4),
      Paint()
        ..color = innerLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HexFramePainter oldDelegate) =>
      oldDelegate.border != border ||
      oldDelegate.fillTop != fillTop ||
      oldDelegate.fillBottom != fillBottom ||
      oldDelegate.innerLine != innerLine;
}
