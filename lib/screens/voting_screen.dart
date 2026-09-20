import 'package:flutter/material.dart';
import 'package:undercoverleague/services/firebase_service.dart';

/// Body of the voting phase. Rendered inside GameScreen's Scaffold, which
/// owns the Firestore stream and the phase transitions.
class VotingScreen extends StatefulWidget {
  final String lobbyId;
  final List<String> alivePlayers;
  final Map<String, dynamic> votes;
  final String playerName;

  const VotingScreen({
    super.key,
    required this.lobbyId,
    required this.alivePlayers,
    required this.votes,
    required this.playerName,
  });

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  String? selectedPlayer;
  bool _submitting = false;

  Future<void> _lockInVote() async {
    if (_submitting || selectedPlayer == null) return;
    setState(() => _submitting = true);
    try {
      await FirebaseService().castVote(widget.lobbyId, widget.playerName, selectedPlayer!);
    } catch (e) {
      debugPrint('Error casting vote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit your vote. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAlive = widget.alivePlayers.contains(widget.playerName);
    // Locked state comes from the document, so it survives rebuilds and
    // reconnects rather than living only in this widget.
    final hasVoted = widget.votes.containsKey(widget.playerName);
    final votesCast = widget.alivePlayers.where(widget.votes.containsKey).length;
    final totalAlivePlayers = widget.alivePlayers.length;
    final canVote = isAlive && !hasVoted;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Voting', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Votes: $votesCast/$totalAlivePlayers',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: canVote
              ? ListView(
                  children: [
                    for (final player in widget.alivePlayers)
                      if (player != widget.playerName)
                        CheckboxListTile(
                          title: Text(player),
                          value: selectedPlayer == player,
                          onChanged: (checked) => setState(() => selectedPlayer = checked! ? player : null),
                        ),
                    CheckboxListTile(
                      title: const Text('Skip Vote'),
                      value: selectedPlayer == skipVoteValue,
                      onChanged: (checked) => setState(() => selectedPlayer = checked! ? skipVoteValue : null),
                    ),
                  ],
                )
              : Center(
                  child: Text(isAlive
                      ? 'Your vote has been locked in. Waiting for other players.'
                      : 'You have been eliminated. Waiting for voting to end.'),
                ),
        ),
        if (canVote)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: selectedPlayer != null && !_submitting ? _lockInVote : null,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Lock in Vote'),
            ),
          ),
      ],
    );
  }
}
