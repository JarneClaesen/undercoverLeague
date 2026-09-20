// Package game is the Undercover state machine: one Lobby, mutated by the
// methods below, with no I/O. Every rule here is a port of the Firestore
// transactions the Flutter app used to run client-side, so the JSON field
// names deliberately match the old document.
package game

import (
	"maps"
	"math/rand/v2"
	"slices"
	"strings"
	"time"
)

type Phase string

const (
	PhaseLobby     Phase = "lobby"
	PhaseRevealing Phase = "revealingRoles"
	PhasePlaying   Phase = "playing"
	PhaseGameOver  Phase = "gameOver"
)

const (
	RoleCivilian   = "Civilian"
	RoleUndercover = "Undercover"
	RoleSpectator  = "Spectator"

	WinnerCivilians  = "Civilians"
	WinnerUndercover = "Undercover"

	// SkipVote is the vote value meaning "no elimination this round".
	SkipVote    = "skip"
	DefaultIcon = "assets/default_icon.jpg"

	MinPlayers = 3
)

// Error is a rejected command. Code is what the client switches on.
type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

var (
	ErrNotFound   = &Error{"notFound", "lobby does not exist"}
	ErrExists     = &Error{"exists", "lobby ID already exists"}
	ErrInProgress = &Error{"inProgress", "game in progress"}
	ErrNameTaken  = &Error{"nameTaken", "name already taken"}
	ErrNotHost    = &Error{"notHost", "only the host can do that"}
	ErrExpired    = &Error{"expired", "session expired"}
	ErrInvalid    = &Error{"invalid", "invalid command"}
)

func invalid(msg string) error { return &Error{"invalid", msg} }

// Lobby is persisted whole as JSON. Collections are never nil so the JSON
// the client sees always has [] / {} rather than null.
type Lobby struct {
	ID                 string            `json:"id"`
	Host               string            `json:"host"`
	Players            []string          `json:"players"`
	GameStarted        bool              `json:"gameStarted"`
	GamePhase          Phase             `json:"gamePhase"`
	CreatedAt          int64             `json:"createdAt"` // unix ms
	Roles              map[string]string `json:"roles"`
	SelectedWord       string            `json:"selectedWord"`
	SelectedIcon       string            `json:"selectedIcon"`
	SelectedIsChampion bool              `json:"selectedIsChampion"`
	AlivePlayers       []string          `json:"alivePlayers"`
	RoundOrder         []string          `json:"roundOrder"`
	CurrentPlayerIndex int               `json:"currentPlayerIndex"`
	// RoundFinished distinguishes describing (false) from voting (true)
	// within PhasePlaying.
	RoundFinished bool              `json:"roundFinished"`
	Votes         map[string]string `json:"votes"`
	// LastVotes is the tally of the round that just ended: voter -> target,
	// snapshotted before Votes is cleared so the client can show who voted
	// for whom. Empty until the first tally.
	LastVotes         map[string]string `json:"lastVotes"`
	RolesAcknowledged map[string]bool   `json:"rolesAcknowledged"`
	Winner            string            `json:"winner"` // "" while undecided
	// LastEliminated is nil before the first vote, "" when a vote eliminated
	// nobody (tie or skip), else the eliminated player's name.
	LastEliminated *string `json:"lastEliminated"`
	// Settings is the host's word-pool filter, kept between games. Zero
	// values mean "everything" (see Filter) so rows saved before filters
	// existed behave as before.
	Settings Filter `json:"settings"`

	// Sessions maps resume token -> player. Never included in a View.
	Sessions map[string]string `json:"sessions"`
	// Version increases on every mutation so a client can drop a stale view
	// that arrives around a reconnect.
	Version int64 `json:"version"`
}

func New(id, host string, now time.Time) *Lobby {
	l := &Lobby{
		ID:        id,
		Host:      host,
		Players:   []string{host},
		GamePhase: PhaseLobby,
		CreatedAt: now.UnixMilli(),
		Settings:  DefaultFilter(),
		Sessions:  map[string]string{},
	}
	l.clearGame()
	return l
}

// Normalize fills in nil collections, e.g. after loading older JSON.
func (l *Lobby) Normalize() {
	if l.Players == nil {
		l.Players = []string{}
	}
	if l.Roles == nil {
		l.Roles = map[string]string{}
	}
	if l.AlivePlayers == nil {
		l.AlivePlayers = []string{}
	}
	if l.RoundOrder == nil {
		l.RoundOrder = []string{}
	}
	if l.Votes == nil {
		l.Votes = map[string]string{}
	}
	if l.LastVotes == nil {
		l.LastVotes = map[string]string{}
	}
	if l.RolesAcknowledged == nil {
		l.RolesAcknowledged = map[string]bool{}
	}
	if l.Sessions == nil {
		l.Sessions = map[string]string{}
	}
	// Rows from before filters existed have both categories off, which
	// Validate would reject; they meant "everything".
	if !l.Settings.UseChampions && !l.Settings.UseItems {
		l.Settings = DefaultFilter()
	}
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

func ValidatePlayerName(name string) error {
	switch {
	case name == "":
		return invalid("Please enter your name.")
	case len([]rune(name)) > 24:
		return invalid("Names must be 24 characters or fewer.")
	case strings.EqualFold(name, SkipVote):
		return invalid("That name is reserved.")
	}
	return nil
}

// NormalizeLobbyID is the canonical spelling of a code: codes are not case
// sensitive, so "abc12", "Abc12" and "ABC12" all name the same lobby.
func NormalizeLobbyID(id string) string {
	return strings.ToUpper(strings.TrimSpace(id))
}

// ValidateLobbyID checks an already normalized id.
func ValidateLobbyID(id string) error {
	switch {
	case id == "":
		return invalid("Please enter a lobby ID.")
	case len([]rune(id)) > 64:
		return invalid("Lobby IDs must be 64 characters or fewer.")
	case strings.Contains(id, "/"):
		return invalid(`Lobby IDs cannot contain "/".`)
	case id == "." || id == "..":
		return invalid("Invalid lobby ID.")
	}
	return nil
}

// ---------------------------------------------------------------------------
// Lobby
// ---------------------------------------------------------------------------

func (l *Lobby) Join(name string) error {
	if l.GameStarted {
		return ErrInProgress
	}
	if slices.Contains(l.Players, name) {
		return ErrNameTaken
	}
	l.Players = append(l.Players, name)
	return nil
}

// Leave removes a player from every piece of game state they appear in and,
// if that changes the outcome of the game, resolves it. Returns true when the
// host left, which closes the lobby: the caller is expected to delete it.
func (l *Lobby) Leave(name string) (closed bool) {
	if name == l.Host {
		return true
	}
	l.Players = remove(l.Players, name)
	for token, p := range l.Sessions {
		if p == name {
			delete(l.Sessions, token)
		}
	}
	if !l.GameStarted {
		return false
	}

	delete(l.RolesAcknowledged, name)
	delete(l.Votes, name)
	if i := slices.Index(l.RoundOrder, name); i != -1 && i < l.CurrentPlayerIndex {
		l.CurrentPlayerIndex--
	}
	l.AlivePlayers = remove(l.AlivePlayers, name)
	l.RoundOrder = remove(l.RoundOrder, name)

	// The leaver was the last in the round order: the round is over.
	if l.GamePhase == PhasePlaying && l.CurrentPlayerIndex >= len(l.RoundOrder) {
		l.RoundFinished = true
	}
	if w := l.resolveWinner(); l.GamePhase != PhaseGameOver && w != "" {
		l.GamePhase = PhaseGameOver
		l.Winner = w
	}
	return false
}

// ---------------------------------------------------------------------------
// Game flow
// ---------------------------------------------------------------------------

// SetSettings replaces the word-pool filter. Only the host may, and only
// while no game is running: the pool is drawn at Start.
func (l *Lobby) SetSettings(caller string, f Filter) error {
	if caller != l.Host {
		return ErrNotHost
	}
	if l.GameStarted {
		return invalid("Settings can only be changed in the lobby.")
	}
	if err := f.Validate(); err != nil {
		return err
	}
	l.Settings = f
	return nil
}

func (l *Lobby) Start(caller string, rng *rand.Rand, c *Catalog) error {
	if caller != l.Host {
		return ErrNotHost
	}
	if err := l.Settings.Validate(); err != nil {
		return err
	}
	// A double tap on "Start Game" is not an error.
	if l.GameStarted {
		return nil
	}
	if len(l.Players) < MinPlayers {
		return invalid("Need at least 3 players.")
	}

	word, isChampion, err := DrawWord(l.Settings.Normalized(c), rng, c)
	if err != nil {
		return err
	}
	order, undercover := DrawRoles(l.Players, rng)

	l.clearGame()
	l.GameStarted = true
	l.GamePhase = PhaseRevealing
	l.SelectedWord = word.Name
	l.SelectedIcon = word.Icon
	if l.SelectedIcon == "" {
		l.SelectedIcon = DefaultIcon
	}
	l.SelectedIsChampion = isChampion
	l.Players = slices.Clone(order)
	l.AlivePlayers = slices.Clone(order)
	l.RoundOrder = slices.Clone(order)
	for _, p := range order {
		l.Roles[p] = RoleCivilian
		l.RolesAcknowledged[p] = false
	}
	l.Roles[undercover] = RoleUndercover
	return nil
}

func (l *Lobby) Acknowledge(name string) error {
	if l.GamePhase != PhaseRevealing {
		return nil
	}
	if _, ok := l.RolesAcknowledged[name]; !ok {
		return invalid("You are not in this game.")
	}
	l.RolesAcknowledged[name] = true
	return nil
}

// NextPlayer ends the turn of the player at expectedIndex. A stale or
// duplicate call (e.g. a double tap) is ignored; a call from anyone but the
// current player is rejected.
func (l *Lobby) NextPlayer(caller string, expectedIndex int) error {
	if l.GamePhase != PhasePlaying || l.RoundFinished {
		return nil
	}
	if l.CurrentPlayerIndex != expectedIndex {
		return nil
	}
	if l.CurrentPlayerIndex >= len(l.RoundOrder) || l.RoundOrder[l.CurrentPlayerIndex] != caller {
		return invalid("It is not your turn.")
	}
	if l.CurrentPlayerIndex < len(l.RoundOrder)-1 {
		l.CurrentPlayerIndex++
	} else {
		l.RoundFinished = true
	}
	return nil
}

func (l *Lobby) Vote(voter, votedFor string) error {
	if l.GamePhase != PhasePlaying || !l.RoundFinished {
		return invalid("Voting is not open.")
	}
	if !slices.Contains(l.AlivePlayers, voter) {
		return invalid("Only alive players can vote.")
	}
	if votedFor != SkipVote && (votedFor == voter || !slices.Contains(l.AlivePlayers, votedFor)) {
		return invalid("Invalid vote target.")
	}
	l.Votes[voter] = votedFor
	return nil
}

// Reset ends the game (whether finished or aborted by the host) and returns
// the lobby to its pre-game state with the same players.
func (l *Lobby) Reset(caller string) error {
	if caller != l.Host {
		return ErrNotHost
	}
	l.clearGame()
	return nil
}

// Advance applies the transitions that need no player action: role reveal
// -> first round once everyone acknowledged, and voting -> tally once every
// alive player voted. Call it after every mutation. Returns whether the
// lobby changed.
func (l *Lobby) Advance(rng *rand.Rand) bool {
	changed := false
	for l.startRounds() || l.endVotingRound(rng) {
		changed = true
	}
	return changed
}

func (l *Lobby) startRounds() bool {
	if l.GamePhase != PhaseRevealing || len(l.RolesAcknowledged) == 0 {
		return false
	}
	for _, acked := range l.RolesAcknowledged {
		if !acked {
			return false
		}
	}
	l.GamePhase = PhasePlaying
	l.RoundFinished = false
	l.CurrentPlayerIndex = 0
	return true
}

// endVotingRound tallies once every alive player has voted. Ties and skips
// eliminate nobody.
func (l *Lobby) endVotingRound(rng *rand.Rand) bool {
	if l.GamePhase != PhasePlaying || !l.RoundFinished {
		return false
	}
	for _, p := range l.AlivePlayers {
		if _, ok := l.Votes[p]; !ok {
			return false
		}
	}

	voteCount := map[string]int{}
	skipVotes := 0
	for _, voter := range l.AlivePlayers {
		vote := l.Votes[voter]
		switch {
		case vote == SkipVote:
			skipVotes++
		case slices.Contains(l.AlivePlayers, vote):
			voteCount[vote]++
		}
	}
	maxVotes := 0
	for _, n := range voteCount {
		maxVotes = max(maxVotes, n)
	}
	var leaders []string
	for p, n := range voteCount {
		if n == maxVotes {
			leaders = append(leaders, p)
		}
	}
	hasClearWinner := len(leaders) == 1 && maxVotes > 0 && maxVotes > skipVotes

	// Snapshot the ballot before clearing it: the client replays it as the
	// vote-result interstitial, and by now the round is decided so who voted
	// for whom is no longer a secret.
	l.LastVotes = maps.Clone(l.Votes)
	l.Votes = map[string]string{}
	l.RoundFinished = false
	l.CurrentPlayerIndex = 0
	eliminated := ""
	if hasClearWinner {
		eliminated = leaders[0]
		l.AlivePlayers = remove(l.AlivePlayers, eliminated)
	}
	l.LastEliminated = &eliminated

	l.RoundOrder = slices.Clone(l.AlivePlayers)
	rng.Shuffle(len(l.RoundOrder), func(i, j int) {
		l.RoundOrder[i], l.RoundOrder[j] = l.RoundOrder[j], l.RoundOrder[i]
	})

	if w := l.resolveWinner(); w != "" {
		l.GamePhase = PhaseGameOver
		l.Winner = w
	}
	return true
}

// Civilians win when the Undercover is gone; the Undercover wins when they
// are one of the last two players (a 1v1 vote can never remove them).
func (l *Lobby) resolveWinner() string {
	undercoverAlive := false
	for _, p := range l.AlivePlayers {
		if l.Roles[p] == RoleUndercover {
			undercoverAlive = true
			break
		}
	}
	if !undercoverAlive {
		return WinnerCivilians
	}
	if len(l.AlivePlayers) <= 2 {
		return WinnerUndercover
	}
	return ""
}

func (l *Lobby) clearGame() {
	l.GameStarted = false
	l.GamePhase = PhaseLobby
	l.Roles = map[string]string{}
	l.SelectedWord = ""
	l.SelectedIcon = ""
	l.SelectedIsChampion = false
	l.AlivePlayers = []string{}
	l.RoundOrder = []string{}
	l.CurrentPlayerIndex = 0
	l.RoundFinished = false
	l.Votes = map[string]string{}
	l.LastVotes = map[string]string{}
	l.RolesAcknowledged = map[string]bool{}
	l.Winner = ""
	l.LastEliminated = nil
}

func remove(list []string, name string) []string {
	out := make([]string, 0, len(list))
	for _, p := range list {
		if p != name {
			out = append(out, p)
		}
	}
	return out
}
