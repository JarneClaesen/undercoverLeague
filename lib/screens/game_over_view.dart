import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/game_settings.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/game_over_portrait.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/reveal_sequence.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/word_card.dart';

/// The end of a game as a reveal, not a summary.
///
/// The lights drop, the word everyone has been circling is turned face up,
/// then the table is turned over one seat at a time — civilians settle,
/// impostors are unmasked — and only then does the winner land, with the
/// reason. Everything sits on one [RevealSequence] clock: a tap anywhere runs
/// it to the end, and reduced motion starts it there.
class GameOverView extends StatefulWidget {
  final Lobby lobby;
  final String playerName;
  final bool isHost;
  final VoidCallback onBackToLobby;

  /// `eliminated`, `outnumbered` or `guess`; null derives a reason from the
  /// winner alone.
  final String? winReason;

  /// The Undercover's word, when the game dealt one; shown under their name.
  final String? decoyWord;

  /// The last guess of the game, named in the reason when it decided it.
  final ({String player, String word, bool correct})? lastGuess;

  /// Host action for a rematch; falls back to [onBackToLobby].
  final VoidCallback? onPlayAgain;

  const GameOverView({
    super.key,
    required this.lobby,
    required this.playerName,
    required this.isHost,
    required this.onBackToLobby,
    this.winReason,
    this.decoyWord,
    this.lastGuess,
    this.onPlayAgain,
  });

  @override
  State<GameOverView> createState() => _GameOverViewState();
}

class _GameOverViewState extends State<GameOverView> {
  static const String _civilian = 'Civilian';
  static const String _spectator = 'Spectator';

  // ---------------------------------------------------------------------------
  // Timeline (wall time from the start of the sequence)
  // ---------------------------------------------------------------------------

  /// A beat of darkness before anything is shown.
  static const Duration _veilAt = Duration(milliseconds: 250);
  static const Duration _veil = Duration(milliseconds: 650);
  static const Duration _eyebrowAt = Duration(milliseconds: 350);
  static const Duration _wordLabelAt = Duration(milliseconds: 550);
  static const Duration _wordAt = Duration(milliseconds: 800);
  static const Duration _wordFlip = Motion.reveal;
  static const Duration _wordGlowAt = Duration(milliseconds: 700);
  static const Duration _wordGlow = Duration(milliseconds: 700);
  static const Duration _rosterGap = Duration(milliseconds: 350);
  static const Duration _stagger = Duration(milliseconds: 160);
  static const Duration _bannerGap = Duration(milliseconds: 400);
  static const Duration _banner = Motion.reveal;
  static const Duration _footerOffset = Duration(milliseconds: 450);
  static const Duration _footerLength = Motion.slow;
  static const Duration _label = Duration(milliseconds: 400);

  Lobby get _lobby => widget.lobby;

  String get _winner => _lobby.winner ?? '';

  bool get _civiliansWon => _winner == 'Civilians';

  bool get _isSpectator => _lobby.myRole == _spectator || _lobby.myRole.isEmpty;

  bool get _viewerImpostor => GameOverPortrait.isImpostorRole(_lobby.myRole);

  bool get _viewerWon => _civiliansWon ? !_viewerImpostor : _viewerImpostor;

  /// The pack the word came from. The only place the view reads it, so the
  /// server's pack id can replace the boolean in one edit.
  bool get _isChampion => _lobby.selectedIsChampion;

  String _roleOf(String name) => _lobby.roles[name] ?? _civilian;

  late final Duration _rosterAt = _wordAt + _wordFlip + _rosterGap;

  late final List<Duration> _portraitAt = () {
    final starts = <Duration>[];
    var at = _rosterAt + _label;
    for (final name in _lobby.players) {
      starts.add(at);
      final impostor = GameOverPortrait.isImpostorRole(_roleOf(name));
      // Impostors are given their full unmasking before the next seat turns;
      // civilians overlap so the table does not drag.
      at += impostor ? GameOverPortrait.revealLength(impostor: true) - _stagger : _stagger;
    }
    return starts;
  }();

  late final Duration _bannerAt = () {
    var end = _rosterAt + _label;
    for (final (i, name) in _lobby.players.indexed) {
      final length = GameOverPortrait.revealLength(impostor: GameOverPortrait.isImpostorRole(_roleOf(name)));
      final done = _portraitAt[i] + length;
      if (done > end) end = done;
    }
    return end + _bannerGap;
  }();

  late final Duration _footerAt = _bannerAt + _footerOffset;

  late final Duration _length = _footerAt + _footerLength;

  @override
  void initState() {
    super.initState();
    // One heavy tap the moment the result lands. Web and most desktops have
    // no haptics engine; failing there must not take the screen down.
    try {
      HapticFeedback.heavyImpact().catchError((Object _) {});
    } catch (_) {
      // No haptics here.
    }
  }

  /// Wraps [child] in an effect chain on [window], or returns it untouched
  /// under reduced motion so the static layout has no animation scaffolding.
  Widget _on(
    BuildContext context,
    RevealClock clock,
    Duration start,
    Duration length,
    Animate Function(Animate step) effects,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    return effects(child.animate(adapter: clock.window(start, length).adapter()));
  }

  /// The plain entrance most text steps use.
  Widget _rise(
    BuildContext context,
    RevealClock clock,
    Duration start,
    Widget child, {
    Duration length = _label,
  }) {
    return _on(
      context,
      clock,
      start,
      length,
      (step) => step
          .fadeIn(duration: length, curve: Motion.enter)
          .slideY(begin: 0.25, end: 0, duration: length, curve: Motion.enter),
      child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RevealSequence(
      length: _length,
      builder: (context, clock) {
        final content = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, clock),
                  const SizedBox(height: 28),
                  _word(context, clock),
                  const SizedBox(height: 28),
                  _roster(context, clock),
                  const SizedBox(height: 28),
                  _footerStep(context, clock),
                ],
              ),
            ),
          ),
        );

        if (Motion.reduced(context)) return content;

        // The darkness the reveal starts from: a plain colour, faded out, so
        // it costs nothing per frame.
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned.fill(
              child: IgnorePointer(
                child: _on(
                  context,
                  clock,
                  _veilAt,
                  _veil,
                  (step) => step.fadeOut(duration: _veil, curve: Motion.exit),
                  const ColoredBox(color: HextechColors.abyss),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Header: the eyebrow is there from the start, the winner lands last.
  // ---------------------------------------------------------------------------

  Widget _header(BuildContext context, RevealClock clock) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;

    final (String verdict, Color verdictColour) = _isSpectator
        ? ('GAME OVER', hextech.textSecondary)
        : _viewerWon
        ? ('VICTORY', hextech.accent)
        : ('DEFEAT', HextechColors.dangerBright);

    final eyebrowStyle = textTheme.labelSmall?.copyWith(letterSpacing: 3);

    final verdictText = Text(
      verdict,
      textAlign: TextAlign.center,
      style: eyebrowStyle?.copyWith(color: verdictColour),
    );

    // Two eyebrows in one slot: "GAME OVER" holds the space until the verdict
    // takes it over with the banner. At rest only the verdict is drawn, and a
    // spectator's verdict *is* "GAME OVER", so theirs simply stays.
    final Widget headerEyebrow = Motion.reduced(context)
        ? verdictText
        : _isSpectator
        ? _rise(context, clock, _eyebrowAt, verdictText)
        : Stack(
            alignment: Alignment.center,
            children: [
              _on(
                context,
                clock,
                _eyebrowAt,
                _bannerAt - _eyebrowAt,
                // Gone just before the verdict arrives, so the two never
                // overlap mid-fade.
                (step) => step
                    .fadeIn(duration: _label, curve: Motion.enter)
                    .fadeOut(delay: _bannerAt - _label - _eyebrowAt, duration: _label, curve: Motion.exit),
                Text(
                  'GAME OVER',
                  textAlign: TextAlign.center,
                  style: eyebrowStyle?.copyWith(color: hextech.textSecondary),
                ),
              ),
              _on(
                context,
                clock,
                _bannerAt,
                _label,
                (step) => step.fadeIn(duration: _label, curve: Motion.enter),
                verdictText,
              ),
            ],
          );

    final banner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _winnerTitle,
          textAlign: TextAlign.center,
          style: textTheme.displayMedium?.copyWith(
            color: _civiliansWon ? hextech.accent : HextechColors.dangerBright,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _reason,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: hextech.textSecondary),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        headerEyebrow,
        const SizedBox(height: 12),
        _on(
          context,
          clock,
          _bannerAt,
          _banner,
          (step) => step
              .fadeIn(duration: Motion.slow, curve: Motion.enter)
              .scaleXY(begin: 1.25, end: 1, duration: _banner, curve: Motion.emphasized),
          banner,
        ),
      ],
    );
  }

  String get _winnerTitle => switch (_winner) {
    'Civilians' => 'CIVILIANS WIN',
    'Undercover' => 'UNDERCOVER WINS',
    'MrWhite' => 'MR. WHITE WINS',
    '' => 'GAME OVER',
    final other => '${other.toUpperCase()} WINS',
  };

  /// One line on *why*, from [GameOverView.winReason] when the server sent
  /// one and from the winner alone otherwise.
  String get _reason {
    final guess = widget.lastGuess;
    switch (widget.winReason) {
      case 'eliminated':
        return 'Every impostor was voted out.';
      case 'outnumbered':
        return 'The impostors outnumber the civilians.';
      case 'guess':
        if (guess != null) return '${guess.player} guessed the word: ${guess.word}.';
        return 'The last guess was right.';
    }
    return switch (_winner) {
      'Civilians' => 'The Undercover was voted out.',
      'Undercover' => 'Too few civilians were left to tell.',
      'MrWhite' => 'Mr. White was never found out.',
      _ => 'The table has been turned over.',
    };
  }

  // ---------------------------------------------------------------------------
  // The word: turned face up for everyone.
  // ---------------------------------------------------------------------------

  Widget _word(BuildContext context, RevealClock clock) {
    final word = _lobby.selectedWord ?? _lobby.myWord ?? '';

    final card = WordCard(
      icon: _lobby.myIcon,
      word: word,
      isChampion: _isChampion,
      width: 220,
      eyebrow: _lobby.selectedPack.isNotEmpty
          ? WordPack.noun(_lobby.selectedPack, 1).toUpperCase()
          : (_isChampion ? 'CHAMPION' : 'ITEM'),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rise(context, clock, _wordLabelAt, _SectionLabel(label: 'The word was')),
        const SizedBox(height: 16),
        _on(
          context,
          clock,
          _wordAt,
          _wordGlowAt + _wordGlow,
          (step) => step
              .custom(
                duration: _wordFlip,
                curve: Motion.emphasized,
                begin: -math.pi / 2,
                end: 0,
                builder: (_, value, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(value),
                  child: child,
                ),
              )
              .slideY(begin: 0.06, end: 0, duration: _wordFlip, curve: Motion.emphasized)
              // A single pulse of gold as the card lands, then it rests.
              .custom(
                delay: _wordGlowAt,
                duration: _wordGlow,
                curve: Curves.easeOut,
                builder: (_, value, child) => _Halo(strength: math.sin(value * math.pi), child: child),
              ),
          card,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // The roster: every seat turned over, impostors unmasked.
  // ---------------------------------------------------------------------------

  Widget _roster(BuildContext context, RevealClock clock) {
    final players = _lobby.players;
    final reduced = Motion.reduced(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rise(context, clock, _rosterAt, _SectionLabel(label: 'The table')),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (i, name) in players.indexed)
              GameOverPortrait(
                name: name,
                role: _roleOf(name),
                isHost: name == _lobby.host,
                isYou: name == widget.playerName,
                eliminated: !_lobby.alivePlayers.contains(name) && _roleOf(name) != _spectator,
                subtitle: _subtitleFor(_roleOf(name)),
                reveal: reduced
                    ? null
                    : clock.window(
                        // The timeline is fixed at first build; a seat that
                        // appears after that simply turns with the banner.
                        i < _portraitAt.length ? _portraitAt[i] : _bannerAt,
                        GameOverPortrait.revealLength(
                          impostor: GameOverPortrait.isImpostorRole(_roleOf(name)),
                        ),
                      ),
              ),
          ],
        ),
      ],
    );
  }

  String? _subtitleFor(String role) => switch (role) {
    'Undercover' =>
      widget.decoyWord == null || widget.decoyWord!.isEmpty ? 'No word' : '“${widget.decoyWord}”',
    'MrWhite' => 'No word',
    _ => null,
  };

  // ---------------------------------------------------------------------------
  // What happens next, and who decides it.
  // ---------------------------------------------------------------------------

  Widget _footerStep(BuildContext context, RevealClock clock) {
    // Until the sequence has run its course a tap anywhere is "skip", so the
    // buttons must not also fire underneath it.
    final footer = IgnorePointer(ignoring: !clock.done, child: _footer(context));
    return _rise(context, clock, _footerAt, footer, length: _footerLength);
  }

  Widget _footer(BuildContext context) {
    if (!widget.isHost) {
      return const StatusNotice(
        message: 'Waiting for the host to start the next game…',
        tone: NoticeTone.info,
        pulse: true,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HextechButton(
          label: 'Play again',
          icon: Icons.replay,
          onPressed: widget.onPlayAgain ?? widget.onBackToLobby,
        ),
        const SizedBox(height: 10),
        HextechButton(
          label: 'Back to lobby',
          variant: HextechButtonVariant.secondary,
          onPressed: widget.onBackToLobby,
        ),
      ],
    );
  }
}

/// The small uppercase rule that heads each section.
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    return Text(
      label.toUpperCase(),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: hextech.accent, letterSpacing: 2.4),
    );
  }
}

/// A gold bloom behind the word card. Plain box shadows, no filters. Always
/// a [DecoratedBox] so the tree keeps its shape while the card animates.
class _Halo extends StatelessWidget {
  final double strength;
  final Widget child;

  const _Halo({required this.strength, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: strength <= 0.01
            ? const []
            : [
                BoxShadow(
                  color: HextechColors.gold.withValues(alpha: 0.5 * strength),
                  blurRadius: 36 * strength,
                  spreadRadius: 4 * strength,
                ),
              ],
      ),
      child: child,
    );
  }
}
