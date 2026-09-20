// Package game is the Undercover state machine: one Lobby, mutated by the
// methods below, with no I/O. Every rule here is a port of the Firestore
// transactions the Flutter app used to run client-side, so the JSON field
// names deliberately match the old document.
package game

import (
	"maps"
	"math/rand/v2"
	"slices"
	"strconv"
	"strings"
	"time"
)

type Phase string

const (
	PhaseLobby     Phase = "lobby"
	PhaseRevealing Phase = "revealingRoles"
	PhasePlaying   Phase = "playing"
	PhaseLastGuess Phase = "lastGuess"
	PhaseGameOver  Phase = "gameOver"
)

const (
	RoleCivilian   = "Civilian"
	RoleUndercover = "Undercover" // gets a decoy word, or nothing
	RoleMrWhite    = "MrWhite"    // never gets a word; only exists with decoy words on
	RoleSpectator  = "Spectator"  // seated, sees the word, never plays

	WinnerCivilians  = "Civilians"
	WinnerUndercover = "Undercover"
	WinnerMrWhite    = "MrWhite" // only through a correct last guess

	// WinReason says how Winner came about.
	WinEliminated  = "eliminated"  // every impostor voted out
	WinOutnumbered = "outnumbered" // impostors alive >= civilians alive
	WinGuess       = "guess"       // a wordless impostor guessed the word

	// SkipVote is the vote value meaning "no elimination this round".
	SkipVote    = "skip"
	DefaultIcon = "assets/default_icon.jpg"

	MinPlayers = 3
	// MaxClueRunes bounds a typed clue; MaxGuessRunes a last guess.
	MaxClueRunes  = 40
	MaxGuessRunes = 64
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

// Clue is one entry of the public clue log.
type Clue struct {
	Round  int    `json:"round"`
	Player string `json:"player"`
	Text   string `json:"text"` // "" when the turn timed out
}

// Guess is a last guess by an eliminated wordless player.
type Guess struct {
	Player  string `json:"player"`
	Word    string `json:"word"` // "" when the guesser timed out or left
	Correct bool   `json:"correct"`
}

// PlayerStats accumulates across the games of one lobby.
type PlayerStats struct {
	CivilianSurvivals int `json:"civilianSurvivals"` // alive civilian at a civilian win
	ImpostorGames     int `json:"impostorGames"`
	Games             int `json:"games"`
}

// Lobby is persisted whole as JSON. Collections are never nil so the JSON
// the client sees always has [] / {} rather than null.
type Lobby struct {
	ID          string   `json:"id"`
	Host        string   `json:"host"`
	Players     []string `json:"players"`
	Spectators  []string `json:"spectators"` // subset of Players who sit a game out
	GameStarted bool     `json:"gameStarted"`
	GamePhase   Phase    `json:"gamePhase"`
	CreatedAt   int64    `json:"createdAt"` // unix ms
	// Round is 1-based and counts describing rounds; 0 outside a game.
	Round        int               `json:"round"`
	Roles        map[string]string `json:"roles"`
	SelectedWord string            `json:"selectedWord"`
	SelectedIcon string            `json:"selectedIcon"`
	SelectedPack Pack              `json:"selectedPack"`
	// DecoyWord is what the Undercovers were told, "" when they got nothing.
	DecoyWord          string   `json:"decoyWord"`
	DecoyIcon          string   `json:"decoyIcon"`
	AlivePlayers       []string `json:"alivePlayers"`
	RoundOrder         []string `json:"roundOrder"`
	CurrentPlayerIndex int      `json:"currentPlayerIndex"`
	// RoundFinished distinguishes describing (false) from voting (true)
	// within PhasePlaying.
	RoundFinished bool              `json:"roundFinished"`
	Votes         map[string]string `json:"votes"`
	// LastVotes is the tally of the round that just ended: voter -> target,
	// snapshotted before Votes is cleared so the client can show who voted
	// for whom. Empty until the first tally.
	LastVotes map[string]string `json:"lastVotes"`
	// Ballots keeps every tally of this game in order, for the vote history
	// and the achievements.
	Ballots           []map[string]string `json:"ballots"`
	Clues             []Clue              `json:"clues"`
	RolesAcknowledged map[string]bool     `json:"rolesAcknowledged"`
	// Deadline is when the current turn, vote or last guess times out, unix
	// ms; 0 when nothing is timed.
	Deadline int64 `json:"deadline"`
	// Guesser is the player making a last guess while GamePhase is
	// PhaseLastGuess, "" otherwise.
	Guesser   string `json:"guesser"`
	LastGuess *Guess `json:"lastGuess"` // nil until the first guess of the game
	Winner    string `json:"winner"`    // "" while undecided
	WinReason string `json:"winReason,omitempty"`
	// LastEliminated is nil before the first vote, "" when a vote eliminated
	// nobody (tie or skip), else the eliminated player's name.
	LastEliminated *string `json:"lastEliminated"`
	// Settings is the host's word-pool filter and rules, kept between games.
	Settings Settings `json:"settings"`

	// Scores, Stats and Achievements accumulate over the games of this
	// lobby; a player who leaves keeps their rows. GamesPlayed counts the
	// games that reached game over.
	Scores       map[string]int         `json:"scores"`
	GamesPlayed  int                    `json:"gamesPlayed"`
	Achievements map[string][]string    `json:"achievements"` // player -> sorted ids
	Stats        map[string]PlayerStats `json:"stats"`

	// Sessions maps resume token -> player. Never included in a View.
	Sessions map[string]string `json:"sessions"`
	// Version increases on every mutation so a client can drop a stale view
	// that arrives around a reconnect.
	Version int64 `json:"version"`
}

func New(id, host string, now time.Time) *Lobby {
	l := &Lobby{
		ID:           id,
		Host:         host,
		Players:      []string{host},
		Spectators:   []string{},
		GamePhase:    PhaseLobby,
		CreatedAt:    now.UnixMilli(),
		Settings:     DefaultSettings(),
		Scores:       map[string]int{},
		Achievements: map[string][]string{},
		Stats:        map[string]PlayerStats{},
		Sessions:     map[string]string{},
	}
	l.clearGame()
	return l
}

// Normalize fills in nil collections, e.g. after loading older JSON.
func (l *Lobby) Normalize() {
	if l.Players == nil {
		l.Players = []string{}
	}
	if l.Spectators == nil {
		l.Spectators = []string{}
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
	if l.Ballots == nil {
		l.Ballots = []map[string]string{}
	}
	if l.Clues == nil {
		l.Clues = []Clue{}
	}
	if l.RolesAcknowledged == nil {
		l.RolesAcknowledged = map[string]bool{}
	}
	if l.Scores == nil {
		l.Scores = map[string]int{}
	}
	if l.Achievements == nil {
		l.Achievements = map[string][]string{}
	}
	if l.Stats == nil {
		l.Stats = map[string]PlayerStats{}
	}
	if l.Sessions == nil {
		l.Sessions = map[string]string{}
	}
	// Rows from before filters existed have no packs, which Validate would
	// reject; they meant "everything" and predate every other setting too.
	if len(l.Settings.Packs) == 0 {
		l.Settings = DefaultSettings()
	}
	if l.Settings.Undercovers < 1 {
		l.Settings.Undercovers = 1
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

// Spectate seats the caller in or out of the next game. Anyone may, for
// themselves, in the lobby phase only.
func (l *Lobby) Spectate(caller string, spectating bool) error {
	if l.GameStarted {
		return invalid("Seats can only be changed in the lobby.")
	}
	if !slices.Contains(l.Players, caller) {
		return invalid("You are not in this lobby.")
	}
	l.Spectators = remove(l.Spectators, caller)
	if spectating {
		l.Spectators = append(l.Spectators, caller)
	}
	return nil
}

// active lists the players who take part in a game: everyone not spectating.
func (l *Lobby) active() []string {
	out := make([]string, 0, len(l.Players))
	for _, p := range l.Players {
		if !slices.Contains(l.Spectators, p) {
			out = append(out, p)
		}
	}
	return out
}

// Leave removes a player from every piece of game state they appear in and,
// if that changes the outcome of the game, resolves it. Returns true when the
// host left, which closes the lobby: the caller is expected to delete it.
// Scores and achievements are kept so a returning player finds them again.
func (l *Lobby) Leave(name string, now time.Time, rng *rand.Rand) (closed bool) {
	if name == l.Host {
		return true
	}
	l.Players = remove(l.Players, name)
	l.Spectators = remove(l.Spectators, name)
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
	i := slices.Index(l.RoundOrder, name)
	if i != -1 && i < l.CurrentPlayerIndex {
		l.CurrentPlayerIndex--
	}
	l.AlivePlayers = remove(l.AlivePlayers, name)
	l.RoundOrder = remove(l.RoundOrder, name)

	if l.GamePhase == PhasePlaying && !l.RoundFinished {
		switch {
		case l.CurrentPlayerIndex >= len(l.RoundOrder):
			// The leaver was the last in the round order: the round is over.
			l.openVoting(now)
		case i == l.CurrentPlayerIndex:
			// The leaver was speaking: the next player starts a fresh turn.
			l.Deadline = l.deadline(now, 1)
		}
	}
	if l.GamePhase == PhaseLastGuess {
		// Nobody else can be decided while the guess is pending; the
		// guesser walking out forfeits it.
		if name == l.Guesser {
			l.resolveGuess(name, "", false, now, rng)
		}
		return false
	}
	if w, reason := l.resolveWinner(); l.GamePhase != PhaseGameOver && w != "" {
		l.finish(w, reason)
	}
	return false
}

// CanKick says whether caller may remove name on the host's behalf, in any
// phase; the removal itself is a Leave. The host cannot kick themselves:
// that would close the lobby, which is what leaving is for.
func (l *Lobby) CanKick(caller, name string) error {
	if caller != l.Host {
		return ErrNotHost
	}
	if name == caller {
		return invalid("You cannot remove yourself.")
	}
	if !slices.Contains(l.Players, name) {
		return invalid("That player is not in this lobby.")
	}
	return nil
}

// ---------------------------------------------------------------------------
// Game flow
// ---------------------------------------------------------------------------

// SetSettings replaces the word-pool filter and rules. Only the host may,
// and only while no game is running: the pool is drawn at Start.
func (l *Lobby) SetSettings(caller string, s Settings) error {
	if caller != l.Host {
		return ErrNotHost
	}
	if l.GameStarted {
		return invalid("Settings can only be changed in the lobby.")
	}
	if err := s.Validate(); err != nil {
		return err
	}
	l.Settings = s
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
	active := l.active()
	if len(active) < MinPlayers {
		return invalid("Need at least 3 players.")
	}
	if 2*l.Settings.Impostors() >= len(active) {
		return invalid("Too many undercovers for " + strconv.Itoa(len(active)) + " players.")
	}

	f := l.Settings.Filter.Normalized(c)
	word, pack, err := DrawWord(f, rng, c)
	if err != nil {
		return err
	}
	var decoy Word
	if l.Settings.DecoyWord {
		d, ok := c.Decoy(pack, word, f, rng)
		if !ok {
			return invalid("No decoy word available among " + pack.Label() + "; widen the filters or turn decoy words off.")
		}
		decoy = d
	}
	order, roles := DrawCast(active, l.Settings.Undercovers, l.Settings.MrWhites, rng)

	l.clearGame()
	l.GameStarted = true
	l.GamePhase = PhaseRevealing
	l.SelectedWord = word.Name
	l.SelectedIcon = iconOrDefault(word.Icon)
	l.SelectedPack = pack
	if l.Settings.DecoyWord {
		l.DecoyWord = decoy.Name
		l.DecoyIcon = iconOrDefault(decoy.Icon)
	}
	// Players is reordered to match the round order, spectators last.
	l.Players = append(slices.Clone(order), l.Spectators...)
	l.AlivePlayers = slices.Clone(order)
	l.RoundOrder = slices.Clone(order)
	for _, p := range order {
		l.Roles[p] = roles[p]
		l.RolesAcknowledged[p] = false
	}
	for _, p := range l.Spectators {
		l.Roles[p] = RoleSpectator
	}
	return nil
}

func iconOrDefault(icon string) string {
	if icon == "" {
		return DefaultIcon
	}
	return icon
}

func (l *Lobby) Acknowledge(name string) error {
	if l.GamePhase != PhaseRevealing {
		return nil
	}
	if l.Roles[name] == RoleSpectator {
		return nil // nothing to acknowledge, and never waited for
	}
	if _, ok := l.RolesAcknowledged[name]; !ok {
		return invalid("You are not in this game.")
	}
	l.RolesAcknowledged[name] = true
	return nil
}

// NextPlayer ends the turn of the player at expectedIndex. A stale or
// duplicate call (e.g. a double tap) is ignored; a call from anyone but the
// current player is rejected, as is any call while the clue log is on: a
// turn then ends with Clue.
func (l *Lobby) NextPlayer(caller string, expectedIndex int, now time.Time) error {
	return l.takeTurn(caller, expectedIndex, now, nil)
}

// Clue ends the caller's turn with a typed clue that goes into the public
// log. Only valid when the clue log is on.
func (l *Lobby) Clue(caller, text string, expectedIndex int, now time.Time) error {
	if !l.Settings.ClueLog {
		return invalid("The clue log is off in this lobby.")
	}
	text = strings.TrimSpace(text)
	switch {
	case text == "":
		return invalid("Type a clue to end your turn.")
	case len([]rune(text)) > MaxClueRunes:
		return invalid("Clues must be " + strconv.Itoa(MaxClueRunes) + " characters or fewer.")
	}
	return l.takeTurn(caller, expectedIndex, now, &text)
}

func (l *Lobby) takeTurn(caller string, expectedIndex int, now time.Time, clue *string) error {
	if l.GamePhase != PhasePlaying || l.RoundFinished {
		return nil
	}
	if l.CurrentPlayerIndex != expectedIndex {
		return nil
	}
	if l.Settings.ClueLog && clue == nil {
		return invalid("Submit a clue to end your turn.")
	}
	if l.CurrentPlayerIndex >= len(l.RoundOrder) || l.RoundOrder[l.CurrentPlayerIndex] != caller {
		return invalid("It is not your turn.")
	}
	if clue != nil {
		l.Clues = append(l.Clues, Clue{Round: l.Round, Player: caller, Text: *clue})
	}
	l.endTurn(now)
	return nil
}

// endTurn passes to the next speaker or, after the last one, opens voting.
func (l *Lobby) endTurn(now time.Time) {
	if l.CurrentPlayerIndex < len(l.RoundOrder)-1 {
		l.CurrentPlayerIndex++
		l.Deadline = l.deadline(now, 1)
		return
	}
	l.openVoting(now)
}

func (l *Lobby) openVoting(now time.Time) {
	l.RoundFinished = true
	l.Deadline = l.deadline(now, 2)
}

// beginRound starts describing: the first speaker of RoundOrder is up.
func (l *Lobby) beginRound(now time.Time) {
	l.GamePhase = PhasePlaying
	l.Round++
	l.RoundFinished = false
	l.CurrentPlayerIndex = 0
	l.Deadline = l.deadline(now, 1)
}

// deadline is now + TurnSeconds * factor in unix ms, 0 with the timer off.
func (l *Lobby) deadline(now time.Time, factor int) int64 {
	if l.Settings.TurnSeconds <= 0 {
		return 0
	}
	return now.UnixMilli() + int64(l.Settings.TurnSeconds*factor)*1000
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

// Guess is the eliminated wordless player's one shot at the word. Right
// ends the game in their favour; wrong resumes it as if the tally had just
// happened.
func (l *Lobby) Guess(caller, word string, now time.Time, rng *rand.Rand) error {
	if l.GamePhase != PhaseLastGuess {
		return invalid("There is no guess to make right now.")
	}
	if caller != l.Guesser {
		return invalid("Only the eliminated player can guess.")
	}
	word = strings.TrimSpace(word)
	if len([]rune(word)) > MaxGuessRunes {
		return invalid("Guesses must be " + strconv.Itoa(MaxGuessRunes) + " characters or fewer.")
	}
	l.resolveGuess(caller, word, WordMatches(l.SelectedWord, word, l.SelectedPack), now, rng)
	return nil
}

func (l *Lobby) resolveGuess(player, word string, correct bool, now time.Time, rng *rand.Rand) {
	l.LastGuess = &Guess{Player: player, Word: word, Correct: correct}
	l.Guesser = ""
	l.Deadline = 0
	if correct {
		winner := WinnerUndercover
		if l.Roles[player] == RoleMrWhite {
			winner = WinnerMrWhite
		}
		l.finish(winner, WinGuess)
		return
	}
	l.afterTally(now, rng)
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

// PlayAgain is Reset from the game-over screen and, when the host seat
// rotates, hands it to the next non-spectator in seat order.
func (l *Lobby) PlayAgain(caller string) error {
	if caller != l.Host {
		return ErrNotHost
	}
	if l.GamePhase != PhaseGameOver {
		return invalid("The game is not over yet.")
	}
	if l.Settings.RotateHost {
		l.Host = l.nextHost()
	}
	l.clearGame()
	return nil
}

func (l *Lobby) nextHost() string {
	i := slices.Index(l.Players, l.Host)
	for step := 1; step < len(l.Players); step++ {
		p := l.Players[(i+step)%len(l.Players)]
		if !slices.Contains(l.Spectators, p) {
			return p
		}
	}
	return l.Host
}

// Advance applies the transitions that need no player action: role reveal
// -> first round once everyone acknowledged, and voting -> tally once every
// alive player voted. Call it after every mutation. Returns whether the
// lobby changed.
func (l *Lobby) Advance(now time.Time, rng *rand.Rand) bool {
	changed := false
	for l.startRounds(now) || l.endVotingRound(now, rng) {
		changed = true
	}
	return changed
}

// Expire applies what the timer does when nobody acted before Deadline: the
// speaker's turn ends (with an empty clue when the log is on), missing votes
// become skips, a pending last guess is forfeited. Returns whether anything
// changed; the caller runs Advance afterwards as after any mutation.
func (l *Lobby) Expire(now time.Time, rng *rand.Rand) bool {
	if l.Deadline == 0 || now.UnixMilli() < l.Deadline {
		return false
	}
	switch {
	case l.GamePhase == PhasePlaying && !l.RoundFinished:
		if l.Settings.ClueLog && l.CurrentPlayerIndex < len(l.RoundOrder) {
			l.Clues = append(l.Clues, Clue{Round: l.Round, Player: l.RoundOrder[l.CurrentPlayerIndex]})
		}
		l.endTurn(now)
	case l.GamePhase == PhasePlaying && l.RoundFinished:
		for _, p := range l.AlivePlayers {
			if _, ok := l.Votes[p]; !ok {
				l.Votes[p] = SkipVote
			}
		}
		l.Deadline = 0
	case l.GamePhase == PhaseLastGuess:
		l.resolveGuess(l.Guesser, "", false, now, rng)
	default:
		// A stale deadline (e.g. a row saved mid-turn by an older build).
		l.Deadline = 0
	}
	return true
}

func (l *Lobby) startRounds(now time.Time) bool {
	if l.GamePhase != PhaseRevealing || len(l.RolesAcknowledged) == 0 {
		return false
	}
	for _, acked := range l.RolesAcknowledged {
		if !acked {
			return false
		}
	}
	l.beginRound(now)
	return true
}

// endVotingRound tallies once every alive player has voted. Ties and skips
// eliminate nobody. Eliminating a player who never had the word gives them
// a last guess before the game goes on.
func (l *Lobby) endVotingRound(now time.Time, rng *rand.Rand) bool {
	if l.GamePhase != PhasePlaying || !l.RoundFinished {
		return false
	}
	for _, p := range l.AlivePlayers {
		if _, ok := l.Votes[p]; !ok {
			return false
		}
	}

	// Snapshot the ballot before clearing it: the client replays it as the
	// vote-result interstitial, and by now the round is decided so who voted
	// for whom is no longer a secret.
	l.LastVotes = maps.Clone(l.Votes)
	l.Ballots = append(l.Ballots, maps.Clone(l.Votes))
	eliminated := tallyBallot(l.Votes, l.AlivePlayers)
	l.Votes = map[string]string{}
	l.RoundFinished = false
	l.CurrentPlayerIndex = 0
	l.Deadline = 0
	if eliminated != "" {
		l.AlivePlayers = remove(l.AlivePlayers, eliminated)
	}
	l.LastEliminated = &eliminated

	if eliminated != "" && l.wordless(eliminated) {
		l.GamePhase = PhaseLastGuess
		l.Guesser = eliminated
		l.Deadline = l.deadline(now, 2)
		return true
	}
	l.afterTally(now, rng)
	return true
}

// tallyBallot is the elimination a ballot decides: the single most voted
// player, provided votes for them outnumber skips. Only votes for alive
// players count; alive nil means everyone (recounting a stored ballot).
func tallyBallot(ballot map[string]string, alive []string) string {
	voteCount := map[string]int{}
	skipVotes := 0
	for _, vote := range ballot {
		switch {
		case vote == SkipVote:
			skipVotes++
		case alive == nil || slices.Contains(alive, vote):
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
	if len(leaders) == 1 && maxVotes > 0 && maxVotes > skipVotes {
		return leaders[0]
	}
	return ""
}

// wordless reports whether a player was told no word at all.
func (l *Lobby) wordless(player string) bool {
	switch l.Roles[player] {
	case RoleMrWhite:
		return true
	case RoleUndercover:
		return l.DecoyWord == ""
	}
	return false
}

// afterTally is what follows a decided elimination (or a wrong guess): the
// next round's order, then either game over or a new round.
func (l *Lobby) afterTally(now time.Time, rng *rand.Rand) {
	if l.Settings.RandomOrder {
		l.RoundOrder = slices.Clone(l.AlivePlayers)
		rng.Shuffle(len(l.RoundOrder), func(i, j int) {
			l.RoundOrder[i], l.RoundOrder[j] = l.RoundOrder[j], l.RoundOrder[i]
		})
	} else {
		// Keep the order, drop the eliminated, and let last round's first
		// speaker go last.
		order := slices.DeleteFunc(slices.Clone(l.RoundOrder), func(p string) bool {
			return !slices.Contains(l.AlivePlayers, p)
		})
		if len(order) > 1 {
			order = append(order[1:], order[0])
		}
		l.RoundOrder = order
	}
	if w, reason := l.resolveWinner(); w != "" {
		l.finish(w, reason)
		return
	}
	l.beginRound(now)
}

// resolveWinner: civilians win once every impostor is gone; the impostors
// win when they are at least as many as the civilians (a vote can then
// never remove them).
func (l *Lobby) resolveWinner() (winner, reason string) {
	impostors, civilians := 0, 0
	for _, p := range l.AlivePlayers {
		if l.isImpostor(p) {
			impostors++
		} else {
			civilians++
		}
	}
	switch {
	case impostors == 0:
		return WinnerCivilians, WinEliminated
	case impostors >= civilians:
		return WinnerUndercover, WinOutnumbered
	}
	return "", ""
}

func (l *Lobby) isImpostor(player string) bool {
	r := l.Roles[player]
	return r == RoleUndercover || r == RoleMrWhite
}

// finish ends the game once: the scoreboard and achievements are awarded
// here and nowhere else, so a second call (Leave after a tally, a repeated
// Advance) changes nothing.
func (l *Lobby) finish(winner, reason string) {
	if l.GamePhase == PhaseGameOver {
		return
	}
	l.GamePhase = PhaseGameOver
	l.Winner = winner
	l.WinReason = reason
	l.Guesser = ""
	l.Deadline = 0
	l.award()
}

func (l *Lobby) clearGame() {
	l.GameStarted = false
	l.GamePhase = PhaseLobby
	l.Round = 0
	l.Roles = map[string]string{}
	l.SelectedWord = ""
	l.SelectedIcon = ""
	l.SelectedPack = ""
	l.DecoyWord = ""
	l.DecoyIcon = ""
	l.AlivePlayers = []string{}
	l.RoundOrder = []string{}
	l.CurrentPlayerIndex = 0
	l.RoundFinished = false
	l.Votes = map[string]string{}
	l.LastVotes = map[string]string{}
	l.Ballots = []map[string]string{}
	l.Clues = []Clue{}
	l.RolesAcknowledged = map[string]bool{}
	l.Deadline = 0
	l.Guesser = ""
	l.LastGuess = nil
	l.Winner = ""
	l.WinReason = ""
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
