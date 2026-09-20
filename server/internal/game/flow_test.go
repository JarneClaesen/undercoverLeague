package game

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
	"time"
)

// startWith joins players, applies s and starts the game (into revealing).
func startWith(t *testing.T, s Settings, players ...string) *Lobby {
	t.Helper()
	l := New("L", players[0], t0)
	for _, p := range players[1:] {
		if err := l.Join(p); err != nil {
			t.Fatal(err)
		}
	}
	if err := l.SetSettings(players[0], s); err != nil {
		t.Fatal(err)
	}
	if err := l.Start(players[0], testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	return l
}

// pin fixes the round order and the roles (players not in roles become
// civilians) so a test can script eliminations.
func pin(l *Lobby, order []string, roles map[string]string) {
	l.RoundOrder = slices.Clone(order)
	l.AlivePlayers = slices.Clone(order)
	for _, p := range order {
		if r, ok := roles[p]; ok {
			l.Roles[p] = r
		} else {
			l.Roles[p] = RoleCivilian
		}
	}
}

// castAll opens voting, has every alive player vote as given (skip when
// absent) and advances into the tally.
func castAll(t *testing.T, l *Lobby, votes map[string]string) {
	t.Helper()
	l.RoundFinished = true
	for _, p := range l.AlivePlayers {
		v, ok := votes[p]
		if !ok {
			v = SkipVote
		}
		if err := l.Vote(p, v); err != nil {
			t.Fatalf("%s votes %s: %v", p, v, err)
		}
	}
	if !l.Advance(t0, testRNG()) {
		t.Fatal("tally did not run")
	}
}

func TestSpectate(t *testing.T) {
	l := New("L", "A", t0)
	l.Join("B")
	l.Join("C")
	if err := l.Spectate("Z", true); errCode(err) != "invalid" {
		t.Errorf("stranger: %v", err)
	}
	if err := l.Spectate("C", true); err != nil || !slices.Equal(l.Spectators, []string{"C"}) {
		t.Fatalf("spectate: %v %v", err, l.Spectators)
	}
	// Idempotent, and the host may sit out too.
	l.Spectate("C", true)
	l.Spectate("A", true)
	if !slices.Equal(l.Spectators, []string{"C", "A"}) {
		t.Errorf("spectators %v", l.Spectators)
	}
	l.Spectate("A", false)
	if !slices.Equal(l.Spectators, []string{"C"}) {
		t.Errorf("spectators %v", l.Spectators)
	}
	// Three seats but only two players: not enough.
	if err := l.Start("A", testRNG(), testCatalog()); errCode(err) != "invalid" || l.GameStarted {
		t.Errorf("start with a spectator among three: %v", err)
	}
	l.Join("D")
	if err := l.Start("A", testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	if err := l.Spectate("D", true); errCode(err) != "invalid" {
		t.Errorf("spectate mid-game: %v", err)
	}
	if l.Roles["C"] != RoleSpectator || slices.Contains(l.AlivePlayers, "C") || slices.Contains(l.RoundOrder, "C") {
		t.Errorf("spectator seated in the game: roles %v alive %v", l.Roles, l.AlivePlayers)
	}
	if _, ok := l.RolesAcknowledged["C"]; ok {
		t.Error("spectator is waited for")
	}
	if !slices.Equal(l.Players[len(l.Players)-1:], []string{"C"}) {
		t.Errorf("spectators should sit last in Players: %v", l.Players)
	}
	if err := l.Acknowledge("C"); err != nil {
		t.Errorf("spectator ack: %v", err)
	}
	// Spectators see the word but not the roles.
	v := l.ViewFor("C", nil, nil, t0)
	if v.MyRole != RoleSpectator || v.MyWord == nil || *v.MyWord != l.SelectedWord || v.MyIcon != l.SelectedIcon || v.Roles != nil {
		t.Errorf("spectator view %+v", v)
	}
	if !slices.Equal(v.Spectators, []string{"C"}) {
		t.Errorf("view spectators %v", v.Spectators)
	}
	if err := l.Vote("C", "A"); errCode(err) != "invalid" {
		t.Errorf("spectator vote: %v", err)
	}
	toPlaying(t, l)
	if len(l.RoundOrder) != 3 {
		t.Errorf("order %v", l.RoundOrder)
	}
}

func TestStartImpostorCount(t *testing.T) {
	s := DefaultSettings()
	s.Undercovers = 2
	l := New("L", "A", t0)
	for _, p := range []string{"B", "C", "D"} {
		l.Join(p)
	}
	if err := l.SetSettings("A", s); err != nil {
		t.Fatal(err)
	}
	err := l.Start("A", testRNG(), testCatalog())
	if errCode(err) != "invalid" || !strings.Contains(err.Error(), "Too many undercovers for 4 players") || l.GameStarted {
		t.Errorf("2 impostors among 4: %v", err)
	}
	l.Join("E")
	if err := l.Start("A", testRNG(), testCatalog()); err != nil {
		t.Fatal(err)
	}
	if n := countRole(l, RoleUndercover); n != 2 {
		t.Errorf("%d undercovers", n)
	}

	s = DefaultSettings()
	s.MrWhites = 1
	s.DecoyWord = true
	l = startWith(t, s, "A", "B", "C", "D", "E")
	if countRole(l, RoleUndercover) != 1 || countRole(l, RoleMrWhite) != 1 || countRole(l, RoleCivilian) != 3 {
		t.Errorf("roles %v", l.Roles)
	}
}

func countRole(l *Lobby, role string) int {
	n := 0
	for _, r := range l.Roles {
		if r == role {
			n++
		}
	}
	return n
}

func roleOf(l *Lobby, role string) string {
	for p, r := range l.Roles {
		if r == role {
			return p
		}
	}
	return ""
}

func TestDecoyWord(t *testing.T) {
	s := DefaultSettings()
	s.Packs = []Pack{PackChampions}
	s.DecoyWord = true
	s.MrWhites = 1
	l := startWith(t, s, "A", "B", "C", "D", "E")
	if l.DecoyWord == "" || l.DecoyWord == l.SelectedWord || l.DecoyIcon == "" || l.SelectedPack != PackChampions {
		t.Fatalf("decoy %q for %q (%s)", l.DecoyWord, l.SelectedWord, l.SelectedPack)
	}
	uc, mw := roleOf(l, RoleUndercover), roleOf(l, RoleMrWhite)
	v := l.ViewFor(uc, nil, nil, t0)
	if v.MyWord == nil || *v.MyWord != l.DecoyWord || v.MyIcon != l.DecoyIcon || !v.MyDecoy || v.DecoyWord != "" {
		t.Errorf("undercover view %+v", v)
	}
	if v := l.ViewFor(mw, nil, nil, t0); v.MyRole != RoleMrWhite || v.MyWord != nil || v.MyDecoy || v.MyIcon != DefaultIcon {
		t.Errorf("mr white view %+v", v)
	}
	if v := l.ViewFor(roleOf(l, RoleCivilian), nil, nil, t0); v.MyWord == nil || *v.MyWord != l.SelectedWord || v.MyDecoy {
		t.Errorf("civilian view %+v", v)
	}
	l.finish(WinnerCivilians, WinEliminated)
	for _, p := range l.Players {
		v := l.ViewFor(p, nil, nil, t0)
		if v.MyWord == nil || *v.MyWord != l.SelectedWord || v.MyDecoy || v.DecoyWord != l.DecoyWord || v.SelectedWord != l.SelectedWord {
			t.Errorf("%s game over view %+v", p, v)
		}
	}

	// Without decoys nothing leaks and no decoy is stored.
	plain := startWith(t, DefaultSettings(), "A", "B", "C")
	if plain.DecoyWord != "" || plain.DecoyIcon != "" {
		t.Errorf("decoy drawn without the setting: %q", plain.DecoyWord)
	}
	if v := plain.ViewFor(roleOf(plain, RoleUndercover), nil, nil, t0); v.MyWord != nil || v.MyDecoy {
		t.Errorf("wordless undercover view %+v", v)
	}
	plain.GamePhase = PhaseGameOver
	if v := plain.ViewFor("A", nil, nil, t0); v.DecoyWord != "" {
		t.Errorf("decoyWord at game over without decoys: %q", v.DecoyWord)
	}

	// A pool with a single member has no decoy to offer: refused at Start.
	s.MrWhites = 0
	s.ChampSeasons = [2]int{15, 15}
	l = New("L", "A", t0)
	l.Join("B")
	l.Join("C")
	if err := l.SetSettings("A", s); err != nil {
		t.Fatal(err)
	}
	if err := l.Start("A", testRNG(), testCatalog()); errCode(err) != "invalid" || !strings.Contains(err.Error(), "decoy") || l.GameStarted {
		t.Errorf("start without a decoy: %v", err)
	}
}

func TestTurnOrder(t *testing.T) {
	t.Run("random reshuffles from the alive players", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C", "D", "E")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"E": RoleUndercover})
		castAll(t, l, map[string]string{"A": "B", "C": "B", "D": "B", "E": "B"})
		if slices.Contains(l.RoundOrder, "B") || len(l.RoundOrder) != 4 {
			t.Errorf("order %v", l.RoundOrder)
		}
	})
	t.Run("fixed rotates left and drops the eliminated", func(t *testing.T) {
		s := DefaultSettings()
		s.RandomOrder = false
		l := startWith(t, s, "A", "B", "C", "D", "E")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"E": RoleUndercover})
		castAll(t, l, nil) // all skip
		if !slices.Equal(l.RoundOrder, []string{"B", "C", "D", "E", "A"}) {
			t.Errorf("after a skip round: %v", l.RoundOrder)
		}
		castAll(t, l, map[string]string{"A": "C", "B": "C", "D": "C", "E": "C"})
		if !slices.Equal(l.RoundOrder, []string{"D", "E", "A", "B"}) {
			t.Errorf("after eliminating C: %v", l.RoundOrder)
		}
	})
}

func TestRoundCounter(t *testing.T) {
	l := newStarted(t, "A", "B", "C", "D")
	if l.Round != 0 {
		t.Errorf("round before playing %d", l.Round)
	}
	toPlaying(t, l)
	if l.Round != 1 {
		t.Errorf("first round %d", l.Round)
	}
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	castAll(t, l, nil)
	if l.Round != 2 {
		t.Errorf("second round %d", l.Round)
	}
	// Eliminating a wordless undercover pauses for the guess; the round
	// only ticks when describing resumes, and never after game over.
	castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D"})
	if l.GamePhase != PhaseLastGuess || l.Round != 2 {
		t.Errorf("phase %s round %d", l.GamePhase, l.Round)
	}
	l.Guess("D", "wrong", t0, testRNG())
	if l.GamePhase != PhaseGameOver || l.Round != 2 {
		t.Errorf("phase %s round %d", l.GamePhase, l.Round)
	}
	l.Reset("A")
	if l.Round != 0 {
		t.Errorf("round after reset %d", l.Round)
	}
}

func TestDeadlines(t *testing.T) {
	ms := func(d time.Duration) int64 { return t0.Add(d).UnixMilli() }
	s := DefaultSettings()
	s.TurnSeconds = 10
	l := startWith(t, s, "A", "B", "C", "D")
	if l.Deadline != 0 {
		t.Errorf("deadline while revealing %d", l.Deadline)
	}
	toPlaying(t, l)
	if l.Deadline != ms(10*time.Second) {
		t.Errorf("first turn deadline %d", l.Deadline)
	}
	pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	later := t0.Add(3 * time.Second)
	if err := l.NextPlayer("A", 0, later); err != nil || l.Deadline != later.Add(10*time.Second).UnixMilli() {
		t.Errorf("second turn deadline %d (%v)", l.Deadline, err)
	}
	l.NextPlayer("B", 1, later)
	l.NextPlayer("C", 2, later)
	if err := l.NextPlayer("D", 3, later); err != nil || !l.RoundFinished || l.Deadline != later.Add(20*time.Second).UnixMilli() {
		t.Errorf("voting deadline %d (%v)", l.Deadline, err)
	}
	for _, p := range l.AlivePlayers {
		if p == "D" {
			l.Vote(p, SkipVote)
		} else {
			l.Vote(p, "D")
		}
	}
	l.Advance(t0, testRNG())
	if l.GamePhase != PhaseLastGuess || l.Deadline != ms(20*time.Second) {
		t.Errorf("last guess deadline %d in %s", l.Deadline, l.GamePhase)
	}
	l.Guess("D", "no", t0, testRNG())
	if l.GamePhase != PhaseGameOver || l.Deadline != 0 {
		t.Errorf("deadline after game over %d", l.Deadline)
	}

	// Timer off: never a deadline.
	off := newStarted(t, "A", "B", "C")
	toPlaying(t, off)
	off.NextPlayer(off.RoundOrder[0], 0, t0)
	if off.Deadline != 0 {
		t.Errorf("deadline with the timer off %d", off.Deadline)
	}
	if v := off.ViewFor("A", nil, nil, t0); v.Deadline != 0 {
		t.Errorf("view deadline %d", v.Deadline)
	}
}

func TestExpire(t *testing.T) {
	timed := func(t *testing.T, clueLog bool) *Lobby {
		s := DefaultSettings()
		s.TurnSeconds = 10
		s.ClueLog = clueLog
		l := startWith(t, s, "A", "B", "C", "D")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
		return l
	}
	due := t0.Add(10 * time.Second)

	t.Run("not yet", func(t *testing.T) {
		l := timed(t, false)
		if l.Expire(t0.Add(9*time.Second), testRNG()) || l.CurrentPlayerIndex != 0 {
			t.Error("expired early")
		}
	})
	t.Run("no deadline", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C")
		toPlaying(t, l)
		if l.Expire(t0.Add(time.Hour), testRNG()) {
			t.Error("expired without a deadline")
		}
	})
	t.Run("describing turn ends", func(t *testing.T) {
		l := timed(t, false)
		if !l.Expire(due, testRNG()) || l.CurrentPlayerIndex != 1 || l.Deadline != due.Add(10*time.Second).UnixMilli() {
			t.Errorf("idx %d deadline %d", l.CurrentPlayerIndex, l.Deadline)
		}
		if len(l.Clues) != 0 {
			t.Errorf("clue recorded without the log: %v", l.Clues)
		}
	})
	t.Run("describing turn ends with an empty clue", func(t *testing.T) {
		l := timed(t, true)
		l.Expire(due, testRNG())
		if len(l.Clues) != 1 || l.Clues[0] != (Clue{Round: 1, Player: "A"}) {
			t.Errorf("clues %v", l.Clues)
		}
	})
	t.Run("last speaker opens voting", func(t *testing.T) {
		l := timed(t, false)
		l.CurrentPlayerIndex = 3
		if !l.Expire(due, testRNG()) || !l.RoundFinished || l.Deadline != due.Add(20*time.Second).UnixMilli() {
			t.Errorf("finished %v deadline %d", l.RoundFinished, l.Deadline)
		}
	})
	t.Run("missing votes become skips", func(t *testing.T) {
		l := timed(t, false)
		l.openVoting(t0)
		l.Vote("A", "B")
		if !l.Expire(t0.Add(20*time.Second), testRNG()) {
			t.Fatal("did not expire")
		}
		if l.Votes["A"] != "B" || l.Votes["B"] != SkipVote || l.Votes["C"] != SkipVote || l.Votes["D"] != SkipVote {
			t.Errorf("votes %v", l.Votes)
		}
		if !l.Advance(t0, testRNG()) || *l.LastEliminated != "" || l.Round != 2 {
			t.Errorf("tally after expiry: %+v", l)
		}
	})
	t.Run("last guess forfeited", func(t *testing.T) {
		l := timed(t, false)
		castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D"})
		if l.GamePhase != PhaseLastGuess {
			t.Fatalf("phase %s", l.GamePhase)
		}
		if !l.Expire(t0.Add(20*time.Second), testRNG()) {
			t.Fatal("did not expire")
		}
		if l.LastGuess == nil || l.LastGuess.Player != "D" || l.LastGuess.Word != "" || l.LastGuess.Correct {
			t.Errorf("last guess %+v", l.LastGuess)
		}
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerCivilians {
			t.Errorf("phase %s winner %s", l.GamePhase, l.Winner)
		}
	})
}

func TestClueLog(t *testing.T) {
	plain := newStarted(t, "A", "B", "C")
	toPlaying(t, plain)
	if err := plain.Clue(plain.RoundOrder[0], "hi", 0, t0); errCode(err) != "invalid" || len(plain.Clues) != 0 {
		t.Errorf("clue with the log off: %v", err)
	}

	s := DefaultSettings()
	s.ClueLog = true
	l := startWith(t, s, "A", "B", "C")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C"}, map[string]string{"C": RoleUndercover})
	if err := l.NextPlayer("A", 0, t0); err == nil || !strings.Contains(err.Error(), "Submit a clue") || l.CurrentPlayerIndex != 0 {
		t.Errorf("nextPlayer with the log on: %v", err)
	}
	for _, text := range []string{"", "   ", strings.Repeat("x", 41)} {
		if err := l.Clue("A", text, 0, t0); errCode(err) != "invalid" {
			t.Errorf("clue %q: %v", text, err)
		}
	}
	if err := l.Clue("B", "nope", 0, t0); errCode(err) != "invalid" {
		t.Errorf("clue out of turn: %v", err)
	}
	if err := l.Clue("A", "  fluffy  ", 0, t0); err != nil || l.CurrentPlayerIndex != 1 {
		t.Fatalf("clue: %v idx %d", err, l.CurrentPlayerIndex)
	}
	// A stale duplicate is ignored, like nextPlayer.
	if err := l.Clue("A", "again", 0, t0); err != nil || len(l.Clues) != 1 {
		t.Errorf("stale clue: %v %v", err, l.Clues)
	}
	l.Clue("B", strings.Repeat("y", 40), 1, t0)
	l.Clue("C", "z", 2, t0)
	if !l.RoundFinished || len(l.Clues) != 3 || l.Clues[0] != (Clue{1, "A", "fluffy"}) || l.Clues[2].Player != "C" {
		t.Errorf("clues %v finished %v", l.Clues, l.RoundFinished)
	}
	castAll(t, l, nil)
	l.Clue("B", "round two", 0, t0)
	if l.Clues[3].Round != 2 {
		t.Errorf("clue round %+v", l.Clues[3])
	}
	// Public to everyone, including someone not in the game.
	if v := l.ViewFor("stranger", nil, nil, t0); len(v.Clues) != 4 {
		t.Errorf("view clues %v", v.Clues)
	}
	l.Reset("A")
	l.Start("A", testRNG(), testCatalog())
	if len(l.Clues) != 0 {
		t.Errorf("clues survived a new game: %v", l.Clues)
	}
}

func TestLastGuess(t *testing.T) {
	mixed := func(t *testing.T) *Lobby {
		s := DefaultSettings()
		s.DecoyWord = true
		s.MrWhites = 1
		l := startWith(t, s, "A", "B", "C", "D", "E")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"D": RoleUndercover, "E": RoleMrWhite})
		return l
	}
	t.Run("mr white guesses right", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E", "D": "E"})
		if l.GamePhase != PhaseLastGuess || l.Guesser != "E" || l.LastGuess != nil || slices.Contains(l.AlivePlayers, "E") {
			t.Fatalf("after tally: phase %s guesser %q", l.GamePhase, l.Guesser)
		}
		if len(l.Ballots) != 1 || l.Ballots[0]["A"] != "E" {
			t.Errorf("ballots %v", l.Ballots)
		}
		if err := l.Guess("A", l.SelectedWord, t0, testRNG()); errCode(err) != "invalid" {
			t.Errorf("guess by someone else: %v", err)
		}
		if err := l.Vote("A", "B"); errCode(err) != "invalid" {
			t.Errorf("vote during the guess: %v", err)
		}
		if err := l.Guess("E", strings.Repeat("x", 65), t0, testRNG()); errCode(err) != "invalid" {
			t.Errorf("overlong guess: %v", err)
		}
		if err := l.Guess("E", " "+strings.ToUpper(l.SelectedWord)+" ", t0, testRNG()); err != nil {
			t.Fatal(err)
		}
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerMrWhite || l.WinReason != WinGuess || l.Guesser != "" {
			t.Errorf("phase %s winner %s reason %s", l.GamePhase, l.Winner, l.WinReason)
		}
		if l.LastGuess == nil || !l.LastGuess.Correct || l.LastGuess.Player != "E" || l.LastGuess.Word != strings.ToUpper(l.SelectedWord) {
			t.Errorf("last guess %+v", l.LastGuess)
		}
		if err := l.Guess("E", "again", t0, testRNG()); errCode(err) != "invalid" {
			t.Errorf("guess after game over: %v", err)
		}
	})
	t.Run("wrong guess resumes the game", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E", "D": "E"})
		if err := l.Guess("E", "nope", t0, testRNG()); err != nil {
			t.Fatal(err)
		}
		// One undercover against three civilians: play on.
		if l.GamePhase != PhasePlaying || l.Round != 2 || len(l.RoundOrder) != 4 || l.RoundFinished {
			t.Errorf("phase %s round %d order %v", l.GamePhase, l.Round, l.RoundOrder)
		}
		if l.LastGuess == nil || l.LastGuess.Correct || l.LastGuess.Word != "nope" {
			t.Errorf("last guess %+v", l.LastGuess)
		}
		if v := l.ViewFor("A", nil, nil, t0); v.LastGuess == nil || v.LastGuess.Player != "E" || v.Guesser != "" {
			t.Errorf("view %+v", v.LastGuess)
		}
		// Kept until the next guess; gone with the next game.
		l.Reset("A")
		if l.LastGuess != nil || l.Guesser != "" {
			t.Error("last guess survived reset")
		}
	})
	t.Run("wordless undercover guesses right", func(t *testing.T) {
		l := newStarted(t, "A", "B", "C", "D")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
		castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D"})
		if l.GamePhase != PhaseLastGuess {
			t.Fatalf("phase %s", l.GamePhase)
		}
		l.Guess("D", l.SelectedWord, t0, testRNG())
		if l.Winner != WinnerUndercover || l.WinReason != WinGuess {
			t.Errorf("winner %s reason %s", l.Winner, l.WinReason)
		}
	})
	t.Run("undercover with a decoy gets no guess", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D", "E": "D"})
		if l.GamePhase != PhasePlaying || l.Guesser != "" || slices.Contains(l.AlivePlayers, "D") {
			t.Errorf("phase %s guesser %q alive %v", l.GamePhase, l.Guesser, l.AlivePlayers)
		}
	})
	t.Run("civilian eliminated gets no guess", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"B": "A", "C": "A", "D": "A", "E": "A"})
		// Two impostors against two civilians: decided on the spot.
		if l.GamePhase != PhaseGameOver || l.Guesser != "" || l.Winner != WinnerUndercover {
			t.Errorf("phase %s guesser %q winner %s", l.GamePhase, l.Guesser, l.Winner)
		}
	})
	t.Run("guesser leaving forfeits", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E", "D": "E"})
		if l.Leave("E", t0, testRNG()) {
			t.Fatal("closed")
		}
		if l.LastGuess == nil || l.LastGuess.Correct || l.LastGuess.Player != "E" || l.GamePhase != PhasePlaying || l.Round != 2 {
			t.Errorf("after leave: guess %+v phase %s round %d", l.LastGuess, l.GamePhase, l.Round)
		}
		if slices.Contains(l.Players, "E") {
			t.Error("leaver still seated")
		}
	})
	t.Run("someone else leaving waits for the guess", func(t *testing.T) {
		l := mixed(t)
		castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E", "D": "E"})
		l.Leave("B", t0, testRNG())
		l.Leave("C", t0, testRNG())
		// One undercover vs one civilian would be decided, but not yet.
		if l.GamePhase != PhaseLastGuess || l.Guesser != "E" {
			t.Errorf("phase %s guesser %q", l.GamePhase, l.Guesser)
		}
		l.Guess("E", "wrong", t0, testRNG())
		if l.GamePhase != PhaseGameOver || l.Winner != WinnerUndercover || l.WinReason != WinOutnumbered {
			t.Errorf("phase %s winner %s reason %s", l.GamePhase, l.Winner, l.WinReason)
		}
	})
}

func TestResolveWinnerWithSeveralImpostors(t *testing.T) {
	s := DefaultSettings()
	s.Undercovers = 2
	s.DecoyWord = true
	l := startWith(t, s, "A", "B", "C", "D", "E")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"D": RoleUndercover, "E": RoleUndercover})
	// Two impostors against three civilians: still on. One civilian gone
	// makes it two against two: the impostors can no longer be outvoted.
	castAll(t, l, map[string]string{"B": "A", "C": "A", "D": "A", "E": "A"})
	if l.GamePhase != PhaseGameOver || l.Winner != WinnerUndercover || l.WinReason != WinOutnumbered {
		t.Errorf("phase %s winner %s reason %s", l.GamePhase, l.Winner, l.WinReason)
	}

	// Both impostors out (decoys, so no guess): civilians.
	l = startWith(t, s, "A", "B", "C", "D", "E")
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"D": RoleUndercover, "E": RoleUndercover})
	castAll(t, l, map[string]string{"A": "D", "B": "D", "C": "D", "E": "D"})
	if l.GamePhase != PhasePlaying {
		t.Fatalf("phase %s after the first impostor", l.GamePhase)
	}
	castAll(t, l, map[string]string{"A": "E", "B": "E", "C": "E"})
	if l.Winner != WinnerCivilians || l.WinReason != WinEliminated {
		t.Errorf("winner %s reason %s", l.Winner, l.WinReason)
	}
}

func TestPlayAgain(t *testing.T) {
	l := newStarted(t, "A", "B", "C")
	toPlaying(t, l)
	if err := l.PlayAgain("A"); errCode(err) != "invalid" {
		t.Errorf("play again mid-game: %v", err)
	}
	l.finish(WinnerCivilians, WinEliminated)
	if err := l.PlayAgain("B"); errCode(err) != "notHost" {
		t.Errorf("non-host: %v", err)
	}
	if err := l.PlayAgain("A"); err != nil {
		t.Fatal(err)
	}
	if l.GameStarted || l.GamePhase != PhaseLobby || l.Host != "A" || len(l.Players) != 3 || l.GamesPlayed != 1 {
		t.Errorf("after play again: %+v", l)
	}

	t.Run("rotates the host past spectators and wraps", func(t *testing.T) {
		s := DefaultSettings()
		s.RotateHost = true
		l := New("L", "A", t0)
		for _, p := range []string{"B", "C", "D"} {
			l.Join(p)
		}
		l.SetSettings("A", s)
		l.Spectate("B", true)
		l.Start("A", testRNG(), testCatalog())
		l.Players = []string{"A", "B", "C", "D"}
		l.finish(WinnerCivilians, WinEliminated)
		if err := l.PlayAgain("A"); err != nil || l.Host != "C" {
			t.Fatalf("host %q err %v", l.Host, err)
		}
		if err := l.PlayAgain("A"); errCode(err) != "notHost" {
			t.Errorf("old host: %v", err)
		}
		l.Start("C", testRNG(), testCatalog())
		l.Players = []string{"A", "B", "C", "D"}
		l.finish(WinnerCivilians, WinEliminated)
		l.PlayAgain("C")
		if l.Host != "D" {
			t.Errorf("host %q", l.Host)
		}
		l.Start("D", testRNG(), testCatalog())
		l.Players = []string{"A", "B", "C", "D"}
		l.finish(WinnerCivilians, WinEliminated)
		l.PlayAgain("D")
		if l.Host != "A" {
			t.Errorf("host after wrap %q", l.Host)
		}
		// Leaving never rotates: the host walking out closes the lobby.
		if !l.Leave("A", t0, testRNG()) {
			t.Error("host leave should close")
		}
	})
	t.Run("host alone among spectators keeps the seat", func(t *testing.T) {
		l := New("L", "A", t0)
		l.Join("B")
		l.Spectate("B", true)
		l.Settings.RotateHost = true
		l.GamePhase = PhaseGameOver
		l.PlayAgain("A")
		if l.Host != "A" {
			t.Errorf("host %q", l.Host)
		}
	})
}

func TestLeaveNewState(t *testing.T) {
	t.Run("spectator leaving mid-game", func(t *testing.T) {
		l := New("L", "A", t0)
		for _, p := range []string{"B", "C", "D"} {
			l.Join(p)
		}
		l.Spectate("D", true)
		l.Start("A", testRNG(), testCatalog())
		toPlaying(t, l)
		if l.Leave("D", t0, testRNG()) || slices.Contains(l.Players, "D") || slices.Contains(l.Spectators, "D") || l.GamePhase != PhasePlaying {
			t.Errorf("after spectator leave: players %v spectators %v phase %s", l.Players, l.Spectators, l.GamePhase)
		}
	})
	t.Run("clues and ballots survive a leaver", func(t *testing.T) {
		s := DefaultSettings()
		s.ClueLog = true
		l := startWith(t, s, "A", "B", "C", "D", "E")
		toPlaying(t, l)
		pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"E": RoleUndercover})
		l.Clue("A", "one", 0, t0)
		castAll(t, l, nil)
		l.Leave("A", t0, testRNG())
		if len(l.Clues) != 1 || len(l.Ballots) != 1 || len(l.Ballots[0]) != 5 {
			t.Errorf("clues %v ballots %v", l.Clues, l.Ballots)
		}
	})
	t.Run("speaker leaving re-arms the turn", func(t *testing.T) {
		s := DefaultSettings()
		s.TurnSeconds = 10
		l := startWith(t, s, "A", "B", "C", "D", "E")
		toPlaying(t, l)
		// The host is the undercover so that leavers never end the game.
		pin(l, []string{"A", "B", "C", "D", "E"}, map[string]string{"A": RoleUndercover})
		later := t0.Add(5 * time.Second)
		l.NextPlayer("A", 0, t0)
		l.Leave("B", later, testRNG())
		if l.CurrentPlayerIndex != 1 || l.RoundOrder[1] != "C" || l.Deadline != later.Add(10*time.Second).UnixMilli() {
			t.Errorf("idx %d order %v deadline %d", l.CurrentPlayerIndex, l.RoundOrder, l.Deadline)
		}
		l.NextPlayer("C", 1, later)
		l.NextPlayer("D", 2, later)
		l.Leave("E", later, testRNG())
		if !l.RoundFinished || l.Deadline != later.Add(20*time.Second).UnixMilli() {
			t.Errorf("voting after the last speaker left: finished %v deadline %d", l.RoundFinished, l.Deadline)
		}
	})
}

func TestCanReact(t *testing.T) {
	l := New("L", "A", t0)
	for _, p := range []string{"B", "C", "D"} {
		l.Join(p)
	}
	l.Spectate("D", true)
	if err := l.CanReact("A"); err != nil {
		t.Errorf("lobby phase: %v", err)
	}
	l.Start("A", testRNG(), testCatalog())
	toPlaying(t, l)
	pin(l, []string{"A", "B", "C"}, map[string]string{"C": RoleUndercover})
	if err := l.CanReact("A"); errCode(err) != "invalid" {
		t.Errorf("alive player: %v", err)
	}
	if err := l.CanReact("D"); err != nil {
		t.Errorf("spectator: %v", err)
	}
	l.AlivePlayers = remove(l.AlivePlayers, "B")
	if err := l.CanReact("B"); err != nil {
		t.Errorf("eliminated: %v", err)
	}
	l.finish(WinnerUndercover, WinOutnumbered)
	if err := l.CanReact("A"); err != nil {
		t.Errorf("after game over: %v", err)
	}
	if !ValidReaction("🔥") || ValidReaction("🍕") || ValidReaction("") || len(Reactions) != 8 {
		t.Error("allowlist")
	}
}

func TestViewNewFields(t *testing.T) {
	c := testCatalog()
	l := New("L", "A", t0)
	l.Join("B")
	l.Join("C")
	v := l.ViewFor("A", nil, c, t0)
	if v.DailyTheme == nil || v.DailyTheme.ID == "" || len(v.Classes) == 0 || len(v.Regions) == 0 {
		t.Errorf("lobby catalog info %+v %v %v", v.DailyTheme, v.Classes, v.Regions)
	}
	if v.PoolSize == nil || (*v.PoolSize)[PackChampions] != 6 {
		t.Errorf("pool size %v", v.PoolSize)
	}
	b, _ := json.Marshal(v)
	for _, key := range []string{`"spectators":[]`, `"round":0`, `"deadline":0`, `"clues":[]`, `"guesser":""`, `"lastGuess":null`,
		`"ballots":[]`, `"scores":{}`, `"gamesPlayed":0`, `"achievements":{}`, `"stats":{}`, `"myDecoy":false`, `"selectedPack":""`,
		`"poolSize":{"champions":6,"items":9}`, `"classes":[`, `"regions":[`, `"dailyTheme":{"id":"`, `"undercovers":1`, `"randomOrder":true`} {
		if !strings.Contains(string(b), key) {
			t.Errorf("view JSON lacks %s", key)
		}
	}
	for _, key := range []string{`"winReason"`, `"decoyWord":"`, `"selectedIsChampion"`} {
		if strings.Contains(string(b), key) {
			t.Errorf("view JSON has %s in the lobby", key)
		}
	}
	// No catalog: the theme, classes and regions are simply absent.
	if v := l.ViewFor("A", nil, nil, t0); v.DailyTheme != nil || v.Classes != nil || v.Regions != nil {
		t.Error("catalog info without a catalog")
	}
	l.Start("A", testRNG(), c)
	v = l.ViewFor("A", nil, c, t0)
	if v.DailyTheme != nil || v.Classes != nil || v.Regions != nil || v.PoolSize != nil {
		t.Error("catalog info after start")
	}
	if v.SelectedPack != l.SelectedPack || v.SelectedPack == "" {
		t.Errorf("selectedPack %q", v.SelectedPack)
	}
	b, _ = json.Marshal(v)
	if strings.Contains(string(b), `"decoyIcon"`) || strings.Contains(string(b), `"sessions"`) {
		t.Errorf("view leaks lobby-only fields: %s", b)
	}
}

func TestNormalizeFillsNewCollections(t *testing.T) {
	var l Lobby
	if err := json.Unmarshal([]byte(`{"id":"L","host":"A","players":["A"],"gamePhase":"lobby","settings":{"packs":["items"]}}`), &l); err != nil {
		t.Fatal(err)
	}
	l.Normalize()
	if l.Spectators == nil || l.Ballots == nil || l.Clues == nil || l.Scores == nil || l.Achievements == nil || l.Stats == nil {
		t.Errorf("nil collections after Normalize: %+v", l)
	}
	b, err := json.Marshal(l.ViewFor("A", nil, nil, t0))
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{`"spectators":[]`, `"ballots":[]`, `"clues":[]`, `"scores":{}`, `"achievements":{}`, `"stats":{}`} {
		if !strings.Contains(string(b), key) {
			t.Errorf("view of an old row lacks %s", key)
		}
	}
	// The whole lobby survives a round trip with every new field.
	l = *newStarted(t, "A", "B", "C", "D")
	toPlaying(t, &l)
	pin(&l, []string{"A", "B", "C", "D"}, map[string]string{"D": RoleUndercover})
	l.Spectators = []string{}
	castAll(t, &l, map[string]string{"A": "D", "B": "D", "C": "D"})
	l.Guess("D", "x", t0, testRNG())
	b, _ = json.Marshal(l)
	var back Lobby
	if err := json.Unmarshal(b, &back); err != nil {
		t.Fatal(err)
	}
	if back.Round != l.Round || len(back.Ballots) != 1 || back.LastGuess == nil || back.WinReason != WinEliminated ||
		back.GamesPlayed != 1 || back.Scores["A"] != l.Scores["A"] || back.Stats["A"] != l.Stats["A"] || back.SelectedPack != l.SelectedPack {
		t.Errorf("round trip lost fields: %+v", back)
	}
}
