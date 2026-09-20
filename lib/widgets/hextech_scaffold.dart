import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/widgets/connection_banner.dart';
import 'package:undercoverleague/widgets/hextech_background.dart';

/// The page frame every routed screen sits in: animated backdrop, a custom
/// header instead of an `AppBar`, the reconnecting banner, and the 600px
/// centred column that keeps the phone-sized UI readable on desktop and web.
///
/// The width constraint lives here and nowhere else — it used to be applied by
/// hand at each `Navigator.push`, which is easy to forget.
class HextechScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? footer;
  final bool showConnection;

  /// Renders a leading icon button in the header when set.
  final VoidCallback? onLeading;
  final IconData leadingIcon;

  const HextechScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.body,
    this.footer,
    this.showConnection = true,
    this.onLeading,
    this.leadingIcon = Icons.arrow_back,
  });

  static const double maxContentWidth = 600;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Scaffold(
      backgroundColor: HextechColors.abyss,
      body: HextechBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        if (onLeading != null) ...[
                          IconButton(
                            icon: Icon(leadingIcon),
                            color: hextech.accent,
                            onPressed: onLeading,
                            tooltip: 'Back',
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleLarge?.copyWith(letterSpacing: 2),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ...actions,
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: HextechRule(),
                  ),
                  if (showConnection) const ConnectionBanner(),
                  Expanded(child: body),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: footer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline divider with a small gold diamond at its centre — the League
/// client's section rule.
class HextechRule extends StatelessWidget {
  const HextechRule({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 9,
      width: double.infinity,
      child: CustomPaint(
        painter: _RulePainter(
          line: context.hextech.panelBorder,
          diamond: context.hextech.accent,
        ),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  final Color line;
  final Color diamond;

  const _RulePainter({required this.line, required this.diamond});

  static const double _half = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final centre = size.width / 2;

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(centre - _half - 4, y), linePaint);
    canvas.drawLine(Offset(centre + _half + 4, y), Offset(size.width, y), linePaint);

    final path = Path()
      ..moveTo(centre, y - _half)
      ..lineTo(centre + _half, y)
      ..lineTo(centre, y + _half)
      ..lineTo(centre - _half, y)
      ..close();
    canvas.drawPath(path, Paint()..color = diamond);
  }

  @override
  bool shouldRepaint(_RulePainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.diamond != diamond;
}
