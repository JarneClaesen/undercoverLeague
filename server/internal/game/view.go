package game

import (
	"maps"
	"slices"
	"time"
)

// View is what one player is allowed to see. Secrets stay server-side:
// only the player's own role is sent, the word is withheld from the
// impostors (an Undercover gets the decoy instead when there is one), and
// the full roles map only appears once the game is over.
type View struct {
	ID                 string            `json:"id"`
	Host               string            `json:"host"`
	Players            []string          `json:"players"`
	Spectators         []string          `json:"spectators"`
	GameStarted        bool              `json:"gameStarted"`
	GamePhase          Phase             `json:"gamePhase"`
	Round              int               `json:"round"`
	AlivePlayers       []string          `json:"alivePlayers"`
	RoundOrder         []string          `json:"roundOrder"`
	CurrentPlayerIndex int               `json:"currentPlayerIndex"`
	RoundFinished      bool              `json:"roundFinished"`
	Deadline           int64             `json:"deadline"` // unix ms, 0 = untimed
	Votes              map[string]string `json:"votes"`
	// LastVotes is the ballot of the round that just ended. It only ever has
	// entries after a tally, so showing everyone who voted for whom reveals
	// nothing that is still in play. Ballots is every tally of this game.
	LastVotes         map[string]string   `json:"lastVotes"`
	Ballots           []map[string]string `json:"ballots"`
	Clues             []Clue              `json:"clues"`
	RolesAcknowledged map[string]bool     `json:"rolesAcknowledged"`
	Guesser           string              `json:"guesser"`
	LastGuess         *Guess              `json:"lastGuess"`
	Winner            string              `json:"winner,omitempty"`
	WinReason         string              `json:"winReason,omitempty"`
	LastEliminated    *string             `json:"lastEliminated"`
	SelectedPack      Pack                `json:"selectedPack"`

	MyRole string  `json:"myRole"` // Civilian | Undercover | MrWhite | Spectator
	MyWord *string `json:"myWord"` // nil unless the player may know a word
	MyIcon string  `json:"myIcon"` // DefaultIcon when MyWord is nil
	// MyDecoy is true when MyWord is the Undercover's decoy, not the word.
	MyDecoy bool `json:"myDecoy"`

	// Revealed to everyone at game over only.
	Roles        map[string]string `json:"roles,omitempty"`
	SelectedWord string            `json:"selectedWord,omitempty"`
	DecoyWord    string            `json:"decoyWord,omitempty"`

	// Settings is the host's pool filter and rules, normalized against the
	// catalog so clients always see concrete season bounds and an explicit
	// tier list.
	Settings Settings `json:"settings"`
	// PoolSize, SeasonRange, Classes, Regions and DailyTheme are only sent
	// in the lobby phase, where the host is choosing; they describe the
	// catalog, not the game.
	PoolSize    *PoolSize    `json:"poolSize,omitempty"`
	SeasonRange *SeasonRange `json:"seasonRange,omitempty"`
	Classes     []string     `json:"classes,omitempty"`
	Regions     []string     `json:"regions,omitempty"`
	DailyTheme  *Theme       `json:"dailyTheme,omitempty"`

	// Lobby-lifetime records, visible to everyone at all times.
	Scores       map[string]int         `json:"scores"`
	GamesPlayed  int                    `json:"gamesPlayed"`
	Achievements map[string][]string    `json:"achievements"`
	Stats        map[string]PlayerStats `json:"stats"`

	// Connected is false for players inside their disconnect grace window.
	Connected map[string]bool `json:"connected"`
	Version   int64           `json:"version"`
}

// ViewFor projects the lobby for one player. c may be nil (no catalog yet):
// the settings are then passed through unnormalized and no pool size,
// classes, regions or daily theme are sent. now picks the daily theme.
func (l *Lobby) ViewFor(player string, connected map[string]bool, c *Catalog, now time.Time) View {
	v := View{
		ID:                 l.ID,
		Host:               l.Host,
		Players:            slices.Clone(l.Players),
		Spectators:         slices.Clone(l.Spectators),
		GameStarted:        l.GameStarted,
		GamePhase:          l.GamePhase,
		Round:              l.Round,
		AlivePlayers:       slices.Clone(l.AlivePlayers),
		RoundOrder:         slices.Clone(l.RoundOrder),
		CurrentPlayerIndex: l.CurrentPlayerIndex,
		RoundFinished:      l.RoundFinished,
		Deadline:           l.Deadline,
		Votes:              maps.Clone(l.Votes),
		LastVotes:          maps.Clone(l.LastVotes),
		Ballots:            cloneBallots(l.Ballots),
		Clues:              slices.Clone(l.Clues),
		RolesAcknowledged:  maps.Clone(l.RolesAcknowledged),
		Guesser:            l.Guesser,
		LastGuess:          cloneGuess(l.LastGuess),
		Winner:             l.Winner,
		WinReason:          l.WinReason,
		LastEliminated:     l.LastEliminated,
		SelectedPack:       l.SelectedPack,
		MyRole:             RoleSpectator,
		MyIcon:             DefaultIcon,
		Settings:           l.Settings.Normalized(c),
		Scores:             maps.Clone(l.Scores),
		GamesPlayed:        l.GamesPlayed,
		Achievements:       cloneLists(l.Achievements),
		Stats:              maps.Clone(l.Stats),
		Connected:          connected,
		Version:            l.Version,
	}
	if c != nil && l.GamePhase == PhaseLobby {
		size := c.PoolSize(v.Settings.Filter)
		v.PoolSize = &size
		r := c.SeasonRange()
		v.SeasonRange = &r
		v.Classes = c.Classes()
		v.Regions = c.Regions()
		if theme := c.DailyTheme(now); theme.ID != "" {
			v.DailyTheme = &theme
		}
	}
	if v.Connected == nil {
		v.Connected = map[string]bool{}
	}
	role, seated := l.Roles[player]
	if seated {
		v.MyRole = role
	}
	gameOver := l.GamePhase == PhaseGameOver
	if l.GameStarted && seated {
		switch {
		case gameOver, role == RoleCivilian, role == RoleSpectator:
			word := l.SelectedWord
			v.MyWord = &word
			v.MyIcon = l.SelectedIcon
		case role == RoleUndercover && l.DecoyWord != "":
			word := l.DecoyWord
			v.MyWord = &word
			v.MyIcon = l.DecoyIcon
			v.MyDecoy = true
		}
	}
	if gameOver {
		v.Roles = maps.Clone(l.Roles)
		v.SelectedWord = l.SelectedWord
		v.DecoyWord = l.DecoyWord
	}
	return v
}

func cloneBallots(in []map[string]string) []map[string]string {
	out := make([]map[string]string, len(in))
	for i, b := range in {
		out[i] = maps.Clone(b)
	}
	return out
}

func cloneLists(in map[string][]string) map[string][]string {
	out := make(map[string][]string, len(in))
	for k, v := range in {
		out[k] = slices.Clone(v)
	}
	return out
}

func cloneGuess(g *Guess) *Guess {
	if g == nil {
		return nil
	}
	c := *g
	return &c
}
