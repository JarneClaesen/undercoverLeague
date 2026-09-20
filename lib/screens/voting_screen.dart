import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/models/lobby.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';
import 'package:undercoverleague/widgets/clue_log.dart';
import 'package:undercoverleague/widgets/hextech_button.dart';
import 'package:undercoverleague/widgets/hextech_panel.dart';
import 'package:undercoverleague/widgets/hextech_snack.dart';
import 'package:undercoverleague/widgets/phase_header.dart';
import 'package:undercoverleague/widgets/ready_meter.dart';
import 'package:undercoverleague/widgets/status_notice.dart';
import 'package:undercoverleague/widgets/turn_timer.dart';
import 'package:undercoverleague/widgets/vote_tile.dart';

/// Body of the voting phase. Rendered inside GameScreen's scaffold, which owns
/// the lobby stream. The server tallies once everyone has voted.
///
/// The server broadcasts the entire votes map to everybody while voting is
/// open, so this screen is careful to read it only two ways: `containsKey` for
/// "they have voted", and the viewer's own entry for "this is what you picked".
/// Rendering anybody else's target would give the table the answer for free.
class VotingScreen extends StatefulWidget {
  final List<String> alivePlayers;
  final Map<String, String> votes;
  final String playerName;

  /// 1-based round whose clues are being judged; 0 when unknown.
  final int round;

  /// Unix ms deadline for the vote; 0 = no timer. Whoever has not voted by
  /// then abstains.
  final int deadline;

  /// Shows the public clue log under the ballot when on.
  final bool clueLog;
  final List<Clue> clues;

  const VotingScreen({
    super.key,
    required this.alivePlayers,
    required this.votes,
    required this.playerName,
    this.round = 0,
    this.deadline = 0,
    this.clueLog = false,
    this.clues = const [],
  });

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  String? selectedPlayer;
  bool _submitting = false;
  bool _lockedHapticFired = false;

  bool get _hasVoted => widget.votes.containsKey(widget.playerName);

  @override
  void initState() {
    super.initState();
    _lockedHapticFired = _hasVoted;
  }

  @override
  void didUpdateWidget(VotingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasVoted && !_lockedHapticFired) {
      _lockedHapticFired = true;
      HapticFeedback.mediumImpact().catchError((Object _) {});
    }
  }

  Future<void> _lockInVote() async {
    if (_submitting || selectedPlayer == null) return;
    setState(() => _submitting = true);
    try {
      LobbyService().castVote(selectedPlayer!);
      // The lobby view with our vote arrives shortly; hold the button until then.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Error casting vote: $e');
      if (mounted) {
        showHextechSnack(context, 'Could not submit your vote. Please try again.', tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAlive = widget.alivePlayers.contains(widget.playerName);
    // Locked state comes from the server view, so it survives rebuilds and
    // reconnects rather than living only in this widget.
    final hasVoted = _hasVoted;
    final votesCast = widget.alivePlayers.where(widget.votes.containsKey).length;
    final totalAlivePlayers = widget.alivePlayers.length;
    final canVote = isAlive && !hasVoted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhaseHeader(
                eyebrow: widget.round > 0 ? 'ROUND ${widget.round} · VOTING' : 'ROUND · VOTING',
                title: 'Who is the Undercover?',
                subtitle: '$votesCast of $totalAlivePlayers votes in',
                trailing: TurnTimer(deadline: widget.deadline),
              ),
              const SizedBox(height: 16),
              ReadyMeter(ready: votesCast, total: totalAlivePlayers, label: 'Votes locked'),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.base),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            child: canVote
                ? _ballot(context)
                : KeyedSubtree(
                    key: const ValueKey('locked'),
                    child: isAlive ? _locked(context) : _eliminated(context),
                  ),
          ),
        ),
        if (canVote)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: HextechButton(
              label: 'Lock in vote',
              busy: _submitting,
              disabledReason: selectedPlayer == null ? 'Pick a summoner or abstain' : null,
              onPressed: selectedPlayer != null && !_submitting ? _lockInVote : null,
            ),
          ),
      ],
    );
  }

  /// The clue log, when it is on, or nothing.
  Widget? _log() => widget.clueLog ? ClueLog(clues: widget.clues, you: widget.playerName) : null;

  Widget _ballot(BuildContext context) {
    final candidates = widget.alivePlayers.where((p) => p != widget.playerName).toList();
    final reduced = Motion.reduced(context);
    final log = _log();
    // The ballot first, the log after it: what to decide, then what to
    // decide it on.
    final rows = candidates.length + 1 + (log == null ? 0 : 1);

    return ListView.separated(
      key: const ValueKey('ballot'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (log != null && index == rows - 1) {
          return Padding(padding: const EdgeInsets.only(top: 6), child: log);
        }
        final isSkipRow = index == candidates.length;
        final name = isSkipRow ? skipVoteValue : candidates[index];

        Widget tile = VoteTile(
          label: isSkipRow ? 'Abstain — eliminate nobody' : name,
          avatarName: isSkipRow ? null : name,
          isSkip: isSkipRow,
          selected: selectedPlayer == name,
          hasVoted: !isSkipRow && widget.votes.containsKey(name),
          onTap: _submitting
              ? null
              : () => setState(() => selectedPlayer = selectedPlayer == name ? null : name),
        );

        if (!reduced) {
          tile = tile
              .animate()
              .fadeIn(
                duration: Motion.base,
                delay: Duration(milliseconds: index * 50),
                curve: Motion.enter,
              )
              .slideY(begin: 0.12, end: 0, duration: Motion.base, curve: Motion.enter);
        }
        return tile;
      },
    );
  }

  Widget _locked(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hextech = context.hextech;
    final target = widget.votes[widget.playerName];
    final waitingOn =
        (widget.alivePlayers.length - widget.alivePlayers.where(widget.votes.containsKey).length)
            .clamp(0, widget.alivePlayers.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HextechPanel(
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'YOUR VOTE',
                  style: textTheme.labelSmall
                      ?.copyWith(color: hextech.textSecondary, letterSpacing: 3),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      target == skipVoteValue ? Icons.block : Icons.how_to_vote_outlined,
                      size: 22,
                      color: hextech.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        target == null || target.isEmpty
                            ? 'Locked in'
                            : target == skipVoteValue
                                ? 'Abstained'
                                : target,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(color: hextech.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StatusNotice(
            message: waitingOn > 0
                ? 'Locked in. Waiting for $waitingOn more…'
                : 'Locked in. Counting the votes…',
            tone: NoticeTone.success,
            pulse: true,
          ),
          if (widget.clueLog) ...[
            const SizedBox(height: 16),
            ClueLog(clues: widget.clues, you: widget.playerName),
          ],
        ],
      ),
    );
  }

  Widget _eliminated(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StatusNotice(
            message: 'You have been eliminated. Waiting for the vote to end…',
            tone: NoticeTone.info,
            pulse: true,
          ),
          if (widget.clueLog) ...[
            const SizedBox(height: 16),
            ClueLog(clues: widget.clues, you: widget.playerName),
          ],
        ],
      ),
    );
  }
}
