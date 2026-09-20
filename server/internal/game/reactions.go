package game

import "slices"

// Reactions is the emoji a watcher may send, in the order the client shows
// them. They are ephemeral: the hub relays them and nothing is stored.
var Reactions = []string{"🔥", "😂", "👀", "🤔", "😱", "👏", "💀", "🧠"}

func ValidReaction(emoji string) bool { return slices.Contains(Reactions, emoji) }

// CanReact rejects players who are still in the running: reactions are for
// the audience (lobby spectators, the eliminated, the Spectator role, and
// everyone once the game is over).
func (l *Lobby) CanReact(player string) error {
	if l.GameStarted && l.GamePhase != PhaseGameOver && slices.Contains(l.AlivePlayers, player) {
		return invalid("Only spectators can react.")
	}
	return nil
}
