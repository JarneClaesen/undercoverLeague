package game

import (
	"maps"
	"slices"
)

// View is what one player is allowed to see. Secrets stay server-side:
// only the player's own role is sent, the word is withheld from the
// Undercover, and the full roles map only appears once the game is over.
type View struct {
	ID                 string            `json:"id"`
	Host               string            `json:"host"`
	Players            []string          `json:"players"`
	GameStarted        bool              `json:"gameStarted"`
	GamePhase          Phase             `json:"gamePhase"`
	AlivePlayers       []string          `json:"alivePlayers"`
	RoundOrder         []string          `json:"roundOrder"`
	CurrentPlayerIndex int               `json:"currentPlayerIndex"`
	RoundFinished      bool              `json:"roundFinished"`
	Votes              map[string]string `json:"votes"`
	// LastVotes is the ballot of the round that just ended. It only ever has
	// entries after a tally, so showing everyone who voted for whom reveals
	// nothing that is still in play.
	LastVotes          map[string]string `json:"lastVotes"`
	RolesAcknowledged  map[string]bool   `json:"rolesAcknowledged"`
	Winner             string            `json:"winner,omitempty"`
	LastEliminated     *string           `json:"lastEliminated"`
	SelectedIsChampion bool              `json:"selectedIsChampion"`

	MyRole string  `json:"myRole"` // Civilian | Undercover | Spectator
	MyWord *string `json:"myWord"` // nil unless the player may know the word
	MyIcon string  `json:"myIcon"` // DefaultIcon when MyWord is nil

	// Revealed to everyone at game over only.
	Roles        map[string]string `json:"roles,omitempty"`
	SelectedWord string            `json:"selectedWord,omitempty"`

	// Connected is false for players inside their disconnect grace window.
	Connected map[string]bool `json:"connected"`
	Version   int64           `json:"version"`
}

func (l *Lobby) ViewFor(player string, connected map[string]bool) View {
	v := View{
		ID:                 l.ID,
		Host:               l.Host,
		Players:            slices.Clone(l.Players),
		GameStarted:        l.GameStarted,
		GamePhase:          l.GamePhase,
		AlivePlayers:       slices.Clone(l.AlivePlayers),
		RoundOrder:         slices.Clone(l.RoundOrder),
		CurrentPlayerIndex: l.CurrentPlayerIndex,
		RoundFinished:      l.RoundFinished,
		Votes:              maps.Clone(l.Votes),
		LastVotes:          maps.Clone(l.LastVotes),
		RolesAcknowledged:  maps.Clone(l.RolesAcknowledged),
		Winner:             l.Winner,
		LastEliminated:     l.LastEliminated,
		SelectedIsChampion: l.SelectedIsChampion,
		MyRole:             RoleSpectator,
		MyIcon:             DefaultIcon,
		Connected:          connected,
		Version:            l.Version,
	}
	if v.Connected == nil {
		v.Connected = map[string]bool{}
	}
	if role, ok := l.Roles[player]; ok {
		v.MyRole = role
	}
	gameOver := l.GamePhase == PhaseGameOver
	if l.GameStarted && (v.MyRole == RoleCivilian || gameOver) {
		word := l.SelectedWord
		v.MyWord = &word
		v.MyIcon = l.SelectedIcon
	}
	if gameOver {
		v.Roles = maps.Clone(l.Roles)
		v.SelectedWord = l.SelectedWord
	}
	return v
}
