package game

import (
	"encoding/json"
	"errors"
	"maps"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
	"time"
)

func testRNG() *rand.Rand { return rand.New(rand.NewPCG(1, 2)) }

// t0 is "now" for tests that do not care about the clock.
var t0 = time.Date(2026, 9, 20, 12, 0, 0, 0, time.UTC)

func newStarted(t *testing.T, players ...string) *Lobby {
	t.Helper()
	l := New("L", players[0], time.Now())
	for _, p := range players[1:] {
		if err := l.Join(p); err != nil {
			t.Fatal(err)
		}
	}
	if err := l.Start(players[0], testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	return l
}

// toPlaying acknowledges for everyone and advances into the first round.
func toPlaying(t *testing.T, l *Lobby) {
	t.Helper()
	for p := range l.RolesAcknowledged {
		if err := l.Acknowledge(p); err != nil {
			t.Fatal(err)
		}
	}
	if !l.Advance(t0, testRNG()) || l.GamePhase != PhasePlaying {
		t.Fatalf("expected playing, got %s", l.GamePhase)
	}
}

func undercoverOf(l *Lobby) string {
	for p, r := range l.Roles {
		if r == RoleUndercover {
			return p
		}
	}
	return ""
}

func errCode(err error) string {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestValidate(t *testing.T) {
	for _, name := range []string{"", "SKIP", "skip", "abcdefghijklmnopqrstuvwxy"} {
		if ValidatePlayerName(name) == nil {
			t.Errorf("name %q should be rejected", name)
		}
	}
	if err := ValidatePlayerName("Bel'Veth"); err != nil {
		t.Error(err)
	}
	for _, id := range []string{"", ".", "..", "a/b"} {
		if ValidateLobbyID(id) == nil {
			t.Errorf("id %q should be rejected", id)
		}
	}
}

func TestJoin(t *testing.T) {
	l := New("L", "A", time.Now())
	if err := l.Join("B"); err != nil {
		t.Fatal(err)
	}
	if err := l.Join("B"); errCode(err) != "nameTaken" {
		t.Errorf("duplicate join: %v", err)
	}
	if err := l.Join("A"); errCode(err) != "nameTaken" {
		t.Errorf("join as host: %v", err)
	}
	l.Join("C")
	if err := l.Start("A", testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	if err := l.Join("D"); errCode(err) != "inProgress" {
		t.Errorf("join in progress: %v", err)
	}
}

func TestStart(t *testing.T) {
	l := New("L", "A", time.Now())
	l.Join("B")
	if err := l.Start("B", testRNG(), testCatalog()); errCode(err) != "notHost" {
		t.Errorf("non-host start: %v", err)
	}
	if err := l.Start("A", testRNG(), testCatalog()); errCode(err) != "invalid" {
		t.Errorf("start with 2 players: %v", err)
	}
	l.Join("C")
	if err := l.SetSettings("B", DefaultSettings()); errCode(err) != "notHost" {
		t.Errorf("non-host settings: %v", err)
	}
	if err := l.SetSettings("A", Settings{}); errCode(err) != "invalid" {
		t.Errorf("settings with no categories: %v", err)
	}
	// Filters that match nothing are rejected at Start and leave the lobby untouched.
	if err := l.SetSettings("A", Settings{Filter: Filter{Packs: []Pack{PackChampions}, ChampSeasons: [2]int{2, 2}}, Undercovers: 1}); err != nil {
		t.Fatal(err)
	}
	if err := l.Start("A", testRNG(), testCatalog()); errCode(err) != "invalid" || l.GameStarted {
		t.Errorf("start with empty pool: %v started=%v", err, l.GameStarted)
	}
	if err := l.SetSettings("A", DefaultSettings()); err != nil {
		t.Fatal(err)
	}
	if err := l.Start("A", testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	if !l.GameStarted || l.GamePhase != PhaseRevealing {
		t.Fatalf("phase %s", l.GamePhase)
	}
	undercovers := 0
	for _, r := range l.Roles {
		if r == RoleUndercover {
			undercovers++
		}
	}
	if undercovers != 1 {
		t.Errorf("want exactly one undercover, got %d", undercovers)
	}
	if len(l.RolesAcknowledged) != 3 || l.RolesAcknowledged["A"] {
		t.Errorf("acks %v", l.RolesAcknowledged)
	}
	if !slices.Equal(l.Players, l.RoundOrder) || !slices.Equal(l.Players, l.AlivePlayers) {
		t.Errorf("order mismatch: %v %v %v", l.Players, l.RoundOrder, l.AlivePlayers)
	}
	if l.SelectedWord == "" || l.SelectedIcon == "" {
		t.Error("no word drawn")
	}

	word := l.SelectedWord
	// Double tap: no-op, word unchanged.
	if err := l.Start("A", testRNG(), testCatalog()); err != nil || l.SelectedWord != word {
		t.Errorf("double start changed state: %v", err)
	}
	if err := l.SetSettings("A", DefaultSettings()); errCode(err) != "invalid" {
		t.Errorf("settings mid-game: %v", err)
	}
}

func TestSettingsInView(t *testing.T) {
	c := testCatalog()
	l := New("L", "A", time.Now())
	l.Join("B")
	l.Join("C")
	f := Settings{Filter: Filter{Packs: []Pack{PackChampions, PackItems}, ChampSeasons: [2]int{15, 16}, ItemTiers: []Tier{TierLegendary}}, Undercovers: 1, RandomOrder: true}
	if err := l.SetSettings("A", f); err != nil {
		t.Fatal(err)
	}
	v := l.ViewFor("B", nil, c, t0)
	if v.Settings.ChampSeasons != [2]int{15, 16} || v.Settings.ItemSeasons != [2]int{3, 16} {
		t.Errorf("view settings not normalized: %+v", v.Settings)
	}
	if v.PoolSize == nil || (*v.PoolSize)[PackChampions] != 2 || (*v.PoolSize)[PackItems] != 4 {
		t.Errorf("pool size %+v", v.PoolSize)
	}
	if v.SeasonRange == nil || v.SeasonRange.Champions != [2]int{1, 16} || v.SeasonRange.Items != [2]int{3, 16} {
		t.Errorf("season range %+v", v.SeasonRange)
	}
	// Without a catalog the view still works, just without counts.
	if v := l.ViewFor("B", nil, nil, t0); v.PoolSize != nil || v.SeasonRange != nil {
		t.Errorf("nil catalog view %+v %+v", v.PoolSize, v.SeasonRange)
	}

	if err := l.Start("A", testRNG(), c); err != nil {
		t.Fatal(err)
	}
	if v := l.ViewFor("A", nil, c, t0); v.PoolSize != nil || v.SeasonRange != nil {
		t.Error("pool size should only be sent in the lobby phase")
	}
	if l.SelectedPack == PackChampions && l.SelectedWord != "Mel" && l.SelectedWord != "Yunara" {
		t.Errorf("drew %s outside the filter", l.SelectedWord)
	}

	// Settings survive a JSON round trip, and an old row without them
	// normalizes to "everything".
	b, _ := json.Marshal(l)
	var back Lobby
	if err := json.Unmarshal(b, &back); err != nil {
		t.Fatal(err)
	}
	back.Normalize()
	if back.Settings.ChampSeasons != [2]int{15, 16} || len(back.Settings.ItemTiers) != 1 {
		t.Errorf("round trip lost settings: %+v", back.Settings)
	}
	var old Lobby
	json.Unmarshal([]byte(`{"id":"x","host":"A"}`), &old)
	old.Normalize()
	if !slices.Equal(old.Settings.Packs, DefaultFilter().Packs) || old.Settings.ItemTiers != nil {
		t.Errorf("old row settings %+v", old.Settings)
	}
}

func TestAcknowledgeAdvances(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	if err := l.Acknowledge("Z"); errCode(err) != "invalid" {
		t.Errorf("unknown player ack: %v", err)
	}
	l.Acknowledge("A")
	l.Acknowledge("B")
	if l.Advance(t0, testRNG()) {
		t.Error("advanced before everyone acknowledged")
	}
	l.Acknowledge("C")
	if !l.Advance(t0, testRNG()) || l.GamePhase != PhasePlaying || l.CurrentPlayerIndex != 0 {
		t.Errorf("phase %s idx %d", l.GamePhase, l.CurrentPlayerIndex)
	}
}

func TestNextPlayer(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	toPlaying(t, l)
	first, second, third := l.RoundOrder[0], l.RoundOrder[1], l.RoundOrder[2]

	if err := l.NextPlayer(second, 0, t0); errCode(err) != "invalid" {
		t.Errorf("wrong caller: %v", err)
	}
	if err := l.NextPlayer(first, 0, t0); err != nil || l.CurrentPlayerIndex != 1 {
		t.Fatalf("idx %d err %v", l.CurrentPlayerIndex, err)
	}
	// Stale double tap is ignored.
	if err := l.NextPlayer(first, 0, t0); err != nil || l.CurrentPlayerIndex != 1 {
		t.Fatalf("stale call changed idx to %d (%v)", l.CurrentPlayerIndex, err)
	}
	l.NextPlayer(second, 1, t0)
	if err := l.NextPlayer(third, 2, t0); err != nil || !l.RoundFinished || l.CurrentPlayerIndex != 2 {
		t.Fatalf("round not finished: %+v", l)
	}
}

func TestVoteGuards(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	toPlaying(t, l)
	if err := l.Vote("A", "B"); errCode(err) != "invalid" {
		t.Errorf("vote while describing: %v", err)
	}
	l.RoundFinished = true
	if err := l.Vote("A", "A"); errCode(err) != "invalid" {
		t.Errorf("self vote: %v", err)
	}
	if err := l.Vote("A", "Z"); errCode(err) != "invalid" {
		t.Errorf("vote for stranger: %v", err)
	}
	if err := l.Vote("Z", "A"); errCode(err) != "invalid" {
		t.Errorf("stranger votes: %v", err)
	}
	if err := l.Vote("A", SkipVote); err != nil {
		t.Error(err)
	}
	if err := l.Vote("A", "B"); err != nil || l.Votes["A"] != "B" {
		t.Errorf("re-vote: %v", err)
	}
}

func TestTally(t *testing.T) {
	cases := []struct {
		name       string
		votes      map[string]string // voter -> target
		eliminated string
	}{
		{"clear majority", map[string]string{"A": "B", "C": "B", "D": "B", "B": "A"}, "B"},
		{"three-way tie with a skip", map[string]string{"A": "B", "B": SkipVote, "C": "D", "D": "A"}, ""},
		{"tie", map[string]string{"A": "B", "B": "A", "C": "D", "D": "C"}, ""},
		{"skip beats max", map[string]string{"A": "B", "B": SkipVote, "C": SkipVote, "D": SkipVote}, ""},
		{"skip equals max", map[string]string{"A": "B", "C": "B", "B": SkipVote, "D": SkipVote}, ""},
		{"all skip", map[string]string{"A": SkipVote, "B": SkipVote, "C": SkipVote, "D": SkipVote}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			l := newStarted(t, "A", "B", "C", "D")
			toPlaying(t, l)
			// Pin the Undercover to D, who is never eliminated here, so the
			// tally itself is what ends (or does not end) the round.
			for p := range l.Roles {
				l.Roles[p] = RoleCivilian
			}
			l.Roles["D"] = RoleUndercover
			l.RoundFinished = true
			for voter, target := range tc.votes {
				if err := l.Vote(voter, target); err != nil {
					t.Fatal(err)
				}
			}
			if !l.Advance(t0, testRNG()) {
				t.Fatal("tally did not run")
			}
			if l.LastEliminated == nil || *l.LastEliminated != tc.eliminated {
				t.Fatalf("lastEliminated = %v, want %q", l.LastEliminated, tc.eliminated)
			}
			if tc.eliminated != "" && slices.Contains(l.AlivePlayers, tc.eliminated) {
				t.Error("eliminated player still alive")
			}
			if len(l.Votes) != 0 || l.RoundFinished || l.CurrentPlayerIndex != 0 {
				t.Errorf("round not reset: %+v", l)
			}
			if len(l.RoundOrder) != len(l.AlivePlayers) {
				t.Errorf("roundOrder %v alive %v", l.RoundOrder, l.AlivePlayers)
			}
		})
	}
}

func TestLastVotesSnapshot(t *testing.T) {
	l := newStarted(t, "A", "B", "C", "D")
	toPlaying(t, l)
	// Pin the Undercover to D so eliminating B does not end the game.
	for p := range l.Roles {
		l.Roles[p] = RoleCivilian
	}
	l.Roles["D"] = RoleUndercover
	l.RoundFinished = true

	if len(l.LastVotes) != 0 {
		t.Fatalf("lastVotes before the first tally: %v", l.LastVotes)
	}
	cast := map[string]string{"A": "B", "B": SkipVote, "C": "B", "D": "B"}
	for voter, target := range cast {
		if err := l.Vote(voter, target); err != nil {
			t.Fatal(err)
		}
	}
	if !l.Advance(t0, testRNG()) {
		t.Fatal("tally did not run")
	}

	if !maps.Equal(l.LastVotes, cast) {
		t.Errorf("lastVotes = %v, want %v", l.LastVotes, cast)
	}
	if len(l.Votes) != 0 {
		t.Errorf("votes not cleared: %v", l.Votes)
	}
	// The snapshot is a copy: the next round's votes must not leak into it.
	l.RoundFinished = true
	l.Vote("A", "C")
	if len(l.LastVotes) != len(cast) {
		t.Errorf("lastVotes aliases votes: %v", l.LastVotes)
	}
	// Everyone sees the finished ballot.
	if v := l.ViewFor("C", nil, nil, t0); !maps.Equal(v.LastVotes, cast) {
		t.Errorf("view lastVotes = %v, want %v", v.LastVotes, cast)
	}

	if err := l.Reset("A"); err != nil {
		t.Fatal(err)
	}
	if len(l.LastVotes) != 0 {
		t.Errorf("lastVotes survived a reset: %v", l.LastVotes)
	}
}

func TestEmptyCollectionsSerialiseAsObjects(t *testing.T) {
	l := New("L", "A", time.Now())
	b, err := json.Marshal(l)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"lastVotes":{}`) {
		t.Errorf("fresh lobby JSON: %s", b)
	}
	b, err = json.Marshal(l.ViewFor("A", nil, nil, t0))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"lastVotes":{}`) {
		t.Errorf("fresh view JSON: %s", b)
	}
}

// A row written before lastVotes existed unmarshals with a nil map; loading
// it must normalise that away exactly as it does for the other collections.
func TestNormalizeFillsLastVotes(t *testing.T) {
	var l Lobby
	if err := json.Unmarshal([]byte(`{"id":"L","host":"A","players":["A"],"gamePhase":"lobby"}`), &l); err != nil {
		t.Fatal(err)
	}
	if l.LastVotes != nil {
		t.Fatal("old row should decode with a nil lastVotes")
	}
	l.Normalize()
	if l.LastVotes == nil {
		t.Error("Normalize left lastVotes nil")
	}
	b, err := json.Marshal(l.ViewFor("A", nil, nil, t0))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"lastVotes":{}`) {
		t.Errorf("view of a normalised old row: %s", b)
	}
}

func TestTallyWaitsForEveryone(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	toPlaying(t, l)
	l.RoundFinished = true
	l.Vote("A", "B")
	l.Vote("B", "A")
	if l.Advance(t0, testRNG()) {
		t.Error("tallied with a vote missing")
	}
}

func TestWinConditions(t *testing.T) {
	t.Run("civilians win when undercover is voted out", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C", "D")
		toPlaying(t, l)
		uc := undercoverOf(l)
		l.RoundFinished = true
		for _, p := range l.AlivePlayers {
			if p == uc {
				l.Vote(p, SkipVote)
			} else {
				l.Vote(p, uc)
			}
		}
		l.Advance(t0, testRNG())
		// A wordless Undercover gets a last guess first.
		if l.GamePhase != PhaseLastGuess || l.Guesser != uc {
			t.Fatalf("phase %s guesser %q", l.GamePhase, l.Guesser)
		}
		if err := l.Guess(uc, "not it", t0, testRNG()); err != nil {
			t.Fatal(err)
		}
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerCivilians || l.WinReason != WinEliminated {
			t.Errorf("phase %s winner %q reason %q", l.GamePhase, l.Winner, l.WinReason)
		}
	})
	t.Run("undercover wins at two alive", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C")
		toPlaying(t, l)
		uc := undercoverOf(l)
		var civ string
		for _, p := range l.AlivePlayers {
			if p != uc {
				civ = p
				break
			}
		}
		l.RoundFinished = true
		for _, p := range l.AlivePlayers {
			if p == civ {
				l.Vote(p, SkipVote)
			} else {
				l.Vote(p, civ)
			}
		}
		l.Advance(t0, testRNG())
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerUndercover {
			t.Errorf("phase %s winner %q", l.GamePhase, l.Winner)
		}
	})
}

func TestCanKick(t *testing.T) {
	l := New("L", "A", time.Now())
	l.Join("B")
	if err := l.CanKick("B", "A"); err != ErrNotHost {
		t.Errorf("non-host: %v", err)
	}
	if err := l.CanKick("A", "A"); errCode(err) != "invalid" {
		t.Errorf("self: %v", err)
	}
	if err := l.CanKick("A", "Z"); errCode(err) != "invalid" {
		t.Errorf("stranger: %v", err)
	}
	if err := l.CanKick("A", "B"); err != nil {
		t.Errorf("host kicks B: %v", err)
	}
	// Mid-game too: an absent player is removed the same way as a leaver.
	l = newStarted(t, "A", "B", "C", "D")
	if err := l.CanKick("A", "C"); err != nil {
		t.Errorf("mid-game: %v", err)
	}
}

func TestLeave(t *testing.T) {
	t.Run("host closes lobby", func(t *testing.T) {
		l := New("L", "A", time.Now())
		if !l.Leave("A", t0, testRNG()) {
			t.Error("host leave should close")
		}
	})
	t.Run("before game", func(t *testing.T) {
		l := New("L", "A", time.Now())
		l.Join("B")
		l.Sessions["tok"] = "B"
		if l.Leave("B", t0, testRNG()) || slices.Contains(l.Players, "B") || len(l.Sessions) != 0 {
			t.Errorf("%+v", l)
		}
	})
	// pinned puts four players in a known order with the host as Undercover,
	// so a non-host leaving never ends the game by itself.
	pinned := func(t *testing.T) *Lobby {
		l := newStarted(t, "A", "B", "C", "D")
		toPlaying(t, l)
		l.RoundOrder = []string{"A", "B", "C", "D"}
		l.AlivePlayers = []string{"A", "B", "C", "D"}
		for p := range l.Roles {
			l.Roles[p] = RoleCivilian
		}
		l.Roles["A"] = RoleUndercover
		return l
	}
	t.Run("leaver before current player shifts index", func(t *testing.T) {
		l := pinned(t)
		l.NextPlayer("A", 0, t0)
		l.NextPlayer("B", 1, t0) // C's turn, idx 2
		l.Leave("B", t0, testRNG())
		if l.CurrentPlayerIndex != 1 || l.RoundOrder[l.CurrentPlayerIndex] != "C" || l.RoundFinished {
			t.Errorf("idx %d order %v", l.CurrentPlayerIndex, l.RoundOrder)
		}
	})
	t.Run("leaver after current player keeps index", func(t *testing.T) {
		l := pinned(t)
		l.Leave("D", t0, testRNG())
		if l.CurrentPlayerIndex != 0 || l.RoundFinished || len(l.RoundOrder) != 3 {
			t.Errorf("idx %d finished %v order %v", l.CurrentPlayerIndex, l.RoundFinished, l.RoundOrder)
		}
	})
	t.Run("last in order leaving finishes the round", func(t *testing.T) {
		l := pinned(t)
		l.NextPlayer("A", 0, t0)
		l.NextPlayer("B", 1, t0)
		l.NextPlayer("C", 2, t0) // D's turn, idx 3
		l.Leave("D", t0, testRNG())
		if !l.RoundFinished || l.CurrentPlayerIndex != 3 {
			t.Errorf("round should be finished: idx %d finished %v", l.CurrentPlayerIndex, l.RoundFinished)
		}
	})
	t.Run("undercover leaving ends the game", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C", "D")
		toPlaying(t, l)
		uc := undercoverOf(l)
		if uc == "A" {
			t.Skip("host is undercover in this seed")
		}
		l.Leave(uc, t0, testRNG())
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerCivilians {
			t.Errorf("phase %s winner %q", l.GamePhase, l.Winner)
		}
	})
	t.Run("leave after game over keeps winner", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C")
		toPlaying(t, l)
		l.GamePhase = PhaseGameOver
		l.Winner = WinnerCivilians
		l.Leave("B", t0, testRNG())
		if l.Winner != WinnerCivilians {
			t.Error("winner overwritten")
		}
	})
}

func TestReset(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	toPlaying(t, l)
	if err := l.Reset("B"); errCode(err) != "notHost" {
		t.Errorf("non-host reset: %v", err)
	}
	if err := l.Reset("A"); err != nil {
		t.Fatal(err)
	}
	if l.GameStarted || l.GamePhase != PhaseLobby || len(l.Roles) != 0 || l.SelectedWord != "" ||
		len(l.AlivePlayers) != 0 || l.LastEliminated != nil || l.Winner != "" {
		t.Errorf("not reset: %+v", l)
	}
	if len(l.Players) != 3 {
		t.Errorf("players lost on reset: %v", l.Players)
	}
}

func TestViewHidesSecrets(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	uc := undercoverOf(l)
	for _, p := range l.Players {
		v := l.ViewFor(p, nil, nil, t0)
		if v.Roles != nil || v.SelectedWord != "" {
			t.Errorf("%s sees roles/word before game over", p)
		}
		if p == uc {
			if v.MyRole != RoleUndercover || v.MyWord != nil || v.MyIcon != DefaultIcon {
				t.Errorf("undercover view %+v", v)
			}
		} else if v.MyRole != RoleCivilian || v.MyWord == nil || *v.MyWord != l.SelectedWord || v.MyIcon != l.SelectedIcon {
			t.Errorf("civilian view %+v", v)
		}
	}
	if v := l.ViewFor("stranger", nil, nil, t0); v.MyRole != RoleSpectator || v.MyWord != nil {
		t.Errorf("spectator view %+v", v)
	}

	l.GamePhase = PhaseGameOver
	v := l.ViewFor(uc, nil, nil, t0)
	if v.Roles == nil || v.SelectedWord != l.SelectedWord || v.MyWord == nil {
		t.Errorf("game over view %+v", v)
	}
}
