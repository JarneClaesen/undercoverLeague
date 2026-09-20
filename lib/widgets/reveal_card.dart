import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/word_card.dart';
import 'package:undercoverleague/widgets/word_image.dart';

/// How much room the card is given: [large] is the centrepiece of the reveal
/// phase, [compact] is the peek card docked at the bottom of the game shell.
enum RevealCardSize { large, compact }

/// The player's secret, face-down.
///
/// The whole point is that the card is only readable while a finger is on it:
/// press to flip it up, release and it drops face-down again. The back face is
/// **identical for every role**, so somebody watching over your shoulder learns
/// nothing from the fact that you peeked — only from what they manage to read
/// in the half second it is up.
///
/// A [Listener] drives the flip rather than a long-press recogniser: on web and
/// desktop a long press costs 500 ms before anything happens, which reads as a
/// broken card.
class RevealCard extends StatefulWidget {
  final String role;
  final String word;
  final String icon;
  final bool isChampion;
  final RevealCardSize size;

  /// When false the card cannot be flipped by hand — it simply renders the
  /// face given by [initiallyRevealed]. Used at game over, where the word is
  /// public anyway.
  final bool peekable;
  final bool initiallyRevealed;

  /// Fires the first time the front face is shown.
  final VoidCallback? onRevealed;

  const RevealCard({
    super.key,
    required this.role,
    required this.word,
    required this.icon,
    required this.isChampion,
    this.size = RevealCardSize.large,
    this.peekable = true,
    this.initiallyRevealed = false,
    this.onRevealed,
  });

  @override
  State<RevealCard> createState() => _RevealCardState();
}

class _RevealCardState extends State<RevealCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _hasRevealed = false;

  bool get _isCivilian => widget.role == 'Civilian';
  bool get _isUndercover => widget.role == 'Undercover';
  bool get _large => widget.size == RevealCardSize.large;

  /// Half of [Motion.reveal]: the card only ever travels half a turn.
  static const Duration _flipDuration = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: _flipDuration,
      value: widget.initiallyRevealed ? 1 : 0,
    )..addListener(_watchForFront);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precache();
      if (widget.initiallyRevealed) _markRevealed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion turns the flip into a straight swap rather than removing
    // the interaction: press still shows, release still hides.
    _flip.duration = Motion.of(context, _flipDuration);
  }

  @override
  void didUpdateWidget(RevealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.icon != oldWidget.icon) _precache();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  /// Warms the portrait so the first flip is not a blank frame.
  void _precache() {
    if (!_isCivilian) return;
    precacheImage(wordImageProvider(widget.icon), context, onError: (error, _) {
      debugPrint('RevealCard could not precache ${widget.icon}: $error');
    });
  }

  void _watchForFront() {
    if (_flip.value >= 0.5) _markRevealed();
  }

  void _markRevealed() {
    if (_hasRevealed) return;
    _hasRevealed = true;
    HapticFeedback.lightImpact().catchError((Object _) {});
    widget.onRevealed?.call();
    if (mounted) setState(() {});
  }

  void _show(PointerDownEvent _) => _flip.forward();

  void _hide([PointerEvent? _]) => _flip.reverse();

  /// The large card is a real trading card: portrait, at the loading art's
  /// own ratio, capped so it fits a phone screen above the ready meter. The
  /// compact card is a full-width strip. Every face uses the same size so the
  /// flip never changes layout.
  static const double _maxLargeWidth = 260;
  static const double _compactHeight = 112;

  Size _cardSize(BoxConstraints constraints) {
    if (!_large) return Size(constraints.maxWidth, _compactHeight);
    final width = math.min(constraints.maxWidth, _maxLargeWidth);
    return Size(width, width * wordCardAspect);
  }

  @override
  Widget build(BuildContext context) {
    final card = LayoutBuilder(
      builder: (context, constraints) {
        final size = _cardSize(constraints);
        return Center(
          child: AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              final t = _flip.value;
              final showFront = t >= 0.5;
              final face = showFront
                  // The front is counter-rotated so the flip does not leave it
                  // mirrored once the card has come round.
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _front(context, size),
                    )
                  : _back(context, size);

              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(t * math.pi),
                child: face,
              );
            },
          ),
        );
      },
    );

    if (!widget.peekable) return card;

    return Listener(
      onPointerDown: _show,
      onPointerUp: _hide,
      onPointerCancel: _hide,
      child: Semantics(
        label: 'Your card. Hold to reveal.',
        child: card,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Faces
  // ---------------------------------------------------------------------------

  Widget _shell(Size size, {required Widget child, PanelTone tone = PanelTone.neutral, bool accent = false}) {
    return SizedBox.fromSize(
      size: size,
      child: HextechPanel(
        tone: tone,
        accent: accent,
        padding: EdgeInsets.all(_large ? 20 : 12),
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: constraints.maxWidth, child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _back(BuildContext context, Size size) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final emblemSize = _large ? 120.0 : 56.0;

    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: emblemSize,
          height: emblemSize,
          child: CustomPaint(
            painter: _EmblemPainter(colour: hextech.accent, glow: hextech.accentGlow),
          ),
        ),
        SizedBox(height: _large ? 22 : 10),
        Text(
          'HOLD TO REVEAL',
          textAlign: TextAlign.center,
          style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 3),
        ),
      ],
    );

    // A single sweep shortly after the card appears says "this is a thing you
    // press". Once it has been read there is nothing left to invite.
    if (!_hasRevealed && !Motion.reduced(context)) {
      body = body
          .animate(delay: const Duration(milliseconds: 600))
          .shimmer(duration: Motion.reveal, color: hextech.accentGlow.withValues(alpha: 0.6));
    }

    return _shell(size, accent: true, child: body);
  }

  Widget _front(BuildContext context, Size size) {
    if (_isCivilian) {
      if (_large) return _civilianCard(size);
      return _shell(size, accent: true, child: _civilianStrip(context));
    }
    if (_isUndercover) {
      return _shell(size, tone: PanelTone.danger, accent: true, child: _undercoverFront(context));
    }
    return _shell(size, child: _spectatorFront(context));
  }

  String get _eyebrow => widget.isChampion ? 'YOUR CHAMPION' : 'YOUR ITEM';

  /// The large civilian face is the trading card itself: art edge to edge,
  /// name on the plate, nothing cropped.
  Widget _civilianCard(Size size) {
    return WordCard(
      icon: widget.icon,
      word: widget.word,
      isChampion: widget.isChampion,
      width: size.width,
      eyebrow: _eyebrow,
      chip: 'CIVILIAN',
    );
  }

  /// The compact face keeps a sliver of the art at its true ratio next to
  /// the name, so the docked card still reads as the same card.
  Widget _civilianStrip(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final eyebrow = _eyebrow;

    return Row(
      children: [
        _portrait(context, width: 50, height: 50 * wordCardAspect),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow,
                style: textTheme.labelSmall?.copyWith(color: hextech.textSecondary, letterSpacing: 2),
              ),
              const SizedBox(height: 4),
              Text(
                widget.word,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(color: hextech.accentGlow),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Champions are tall portraits and fill the frame at their own ratio;
  /// items are 64 px squares and must never be blown up past their own
  /// resolution.
  Widget _portrait(BuildContext context, {required double width, required double height}) {
    final hextech = context.hextech;
    final side = math.min(width, height);
    final itemSide = math.min(side, 96.0);

    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: hextech.accent, width: 2)),
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: wordImage(
            context,
            widget.icon,
            width: widget.isChampion ? width : itemSide,
            height: widget.isChampion ? height : itemSide,
            fit: widget.isChampion ? BoxFit.cover : BoxFit.contain,
            fallbackSize: side * 0.5,
          ),
        ),
      ),
    );
  }

  Widget _undercoverFront(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    if (!_large) {
      return Row(
        children: [
          Icon(Icons.theater_comedy, size: 44, color: HextechColors.dangerBright),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'UNDERCOVER',
                  style: textTheme.titleMedium?.copyWith(color: HextechColors.dangerBright),
                ),
                const SizedBox(height: 4),
                Text(
                  'Blend in.',
                  style: textTheme.bodySmall?.copyWith(color: hextech.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.theater_comedy, size: 120, color: HextechColors.dangerBright),
        const SizedBox(height: 18),
        Text(
          'UNDERCOVER',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(color: HextechColors.dangerBright),
        ),
        const SizedBox(height: 10),
        Text(
          "You don't know the word. Blend in.",
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: hextech.textSecondary),
        ),
      ],
    );
  }

  Widget _spectatorFront(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.visibility_outlined,
          size: _large ? 96 : 40,
          color: hextech.textSecondary,
        ),
        SizedBox(height: _large ? 18 : 8),
        Text(
          'SPECTATING',
          textAlign: TextAlign.center,
          style: (_large ? textTheme.headlineSmall : textTheme.titleMedium)
              ?.copyWith(color: hextech.textSecondary),
        ),
      ],
    );
  }
}

/// The card back: a hexagon with an inner diamond, the hextech crest. Drawn
/// rather than shipped as an asset so it inherits the theme's gold.
class _EmblemPainter extends CustomPainter {
  final Color colour;
  final Color glow;

  const _EmblemPainter({required this.colour, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    Path hexagon(double r) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        // Flat-top hexagon: start at -90° so a vertex points up.
        final angle = -math.pi / 2 + i * math.pi / 3;
        final point = centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, radius * 0.035)
      ..color = colour;
    canvas.drawPath(hexagon(radius), outline);

    canvas.drawPath(
      hexagon(radius * 0.78),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colour.withValues(alpha: 0.45),
    );

    final d = radius * 0.4;
    final diamond = Path()
      ..moveTo(centre.dx, centre.dy - d)
      ..lineTo(centre.dx + d * 0.72, centre.dy)
      ..lineTo(centre.dx, centre.dy + d)
      ..lineTo(centre.dx - d * 0.72, centre.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = colour);
    canvas.drawPath(
      diamond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = glow.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_EmblemPainter oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.glow != glow;
}
