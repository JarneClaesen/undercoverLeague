package hub

import (
	"log/slog"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
	"github.com/JarneClaesen/underCoverLeague/server/internal/store"
)

// fakeClock stands in for h.now and h.after: time only moves when the test
// says so and armed timers are collected to be fired by hand.
type fakeClock struct {
	mu    sync.Mutex
	now   time.Time
	armed []armedTimer
}

type armedTimer struct {
	wait time.Duration
	fire func()
}

func newFakeClock(h *Hub) *fakeClock {
	fc := &fakeClock{now: time.Date(2026, 9, 20, 12, 0, 0, 0, time.UTC)}
	h.now = func() time.Time {
		fc.mu.Lock()
		defer fc.mu.Unlock()
		return fc.now
	}
	h.after = func(d time.Duration, f func()) *time.Timer {
		fc.mu.Lock()
		defer fc.mu.Unlock()
		fc.armed = append(fc.armed, armedTimer{d, f})
		return time.NewTimer(time.Hour) // never fires on its own
	}
	return fc
}

func (fc *fakeClock) advance(d time.Duration) {
	fc.mu.Lock()
	defer fc.mu.Unlock()
	fc.now = fc.now.Add(d)
}

func (fc *fakeClock) at() time.Time {
	fc.mu.Lock()
	defer fc.mu.Unlock()
	return fc.now
}

// last returns the most recently armed timer.
func (fc *fakeClock) last(t *testing.T) armedTimer {
	t.Helper()
	fc.mu.Lock()
	defer fc.mu.Unlock()
	if len(fc.armed) == 0 {
		t.Fatal("no timer armed")
	}
	return fc.armed[len(fc.armed)-1]
}

func (fc *fakeClock) count() int {
	fc.mu.Lock()
	defer fc.mu.Unlock()
	return len(fc.armed)
}

func TestTurnTimerExpires(t *testing.T) {
	h, st := newHub(t, time.Minute)
	fc := newFakeClock(h)
	ps := threePlayers(t, h)
	byName := map[string]*player{}
	for _, p := range ps {
		byName[p.name] = p
	}
	s := game.DefaultSettings()
	s.TurnSeconds = 10
	if err := h.Settings(ps[0].c, s); err != nil {
		t.Fatal(err)
	}
	if fc.count() != 0 {
		t.Fatal("timer armed before a turn started")
	}
	startAndAck(t, h, ps)

	// The first turn arms a 10 s timer and the view carries the deadline.
	v := ps[0].s.latestLobby(t)
	if v.Deadline != fc.at().Add(10*time.Second).UnixMilli() || v.CurrentPlayerIndex != 0 {
		t.Fatalf("view %+v", v)
	}
	first := fc.last(t)
	if first.wait != 10*time.Second {
		t.Errorf("armed for %v", first.wait)
	}
	// Firing before the deadline changes nothing (no broadcast) but re-arms.
	fc.advance(5 * time.Second)
	first.fire()
	if l := h.rooms["L"].state; l.CurrentPlayerIndex != 0 || l.Version != v.Version {
		t.Errorf("early fire moved the turn: idx %d version %d", l.CurrentPlayerIndex, l.Version)
	}
	if fc.last(t).wait != 5*time.Second {
		t.Errorf("re-armed for %v", fc.last(t).wait)
	}
	// Past the deadline the turn passes and the next one is timed.
	fc.advance(6 * time.Second)
	fc.last(t).fire()
	v = ps[1].s.latestLobby(t)
	if v.CurrentPlayerIndex != 1 || v.Deadline != fc.at().Add(10*time.Second).UnixMilli() {
		t.Fatalf("after expiry %+v", v)
	}
	// A stale timer (the lobby moved on) is a no-op.
	stale := fc.last(t)
	if err := h.NextPlayer(byName[v.RoundOrder[1]].c, 1); err != nil {
		t.Fatal(err)
	}
	fc.advance(time.Hour)
	stale.fire()
	if v := ps[2].s.latestLobby(t); v.CurrentPlayerIndex != 2 || v.RoundFinished {
		t.Errorf("stale timer acted: %+v", v)
	}
	// Last speaker expires into voting (2x), voting expires into a tally
	// with everyone skipping.
	fc.last(t).fire()
	v = ps[0].s.latestLobby(t)
	if !v.RoundFinished || v.Deadline != fc.at().Add(20*time.Second).UnixMilli() {
		t.Fatalf("voting %+v", v)
	}
	if err := h.Vote(byName[v.RoundOrder[0]].c, v.RoundOrder[1]); err != nil {
		t.Fatal(err)
	}
	fc.advance(21 * time.Second)
	fc.last(t).fire()
	v = ps[0].s.latestLobby(t)
	if v.RoundFinished || v.Round != 2 || v.LastEliminated == nil || *v.LastEliminated != "" || len(v.LastVotes) != 3 {
		t.Fatalf("tally after expiry %+v", v)
	}
	if l, _ := st.Load("L"); l == nil || l.Round != 2 {
		t.Error("expiry not persisted")
	}
	// Closing the room drops the pending timer; firing it later is harmless.
	pending := fc.last(t)
	h.Leave(ps[0].c)
	if len(h.rooms) != 0 {
		t.Fatal("room still live")
	}
	pending.fire()
}

func TestTurnTimerSurvivesReload(t *testing.T) {
	st, err := store.Open(filepath.Join(t.TempDir(), "r.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	h1 := New(st, time.Minute, slog.Default(), testCatalog())
	fc1 := newFakeClock(h1)
	ps := threePlayers(t, h1)
	s := game.DefaultSettings()
	s.TurnSeconds = 30
	if err := h1.Settings(ps[0].c, s); err != nil {
		t.Fatal(err)
	}
	startAndAck(t, h1, ps)
	h1.Shutdown()

	// A resume into a new process re-arms for what is left of the turn.
	h2 := New(st, time.Minute, slog.Default(), testCatalog())
	fc2 := newFakeClock(h2)
	fc2.now = fc1.at().Add(12 * time.Second)
	a := newFake()
	if err := h2.Resume(NewClient(a), 1, "L", ps[0].token); err != nil {
		t.Fatal(err)
	}
	if got := fc2.last(t).wait; got != 18*time.Second {
		t.Errorf("re-armed for %v, want 18s", got)
	}
}

func TestReactions(t *testing.T) {
	h, st := newHub(t, time.Minute)
	fc := newFakeClock(h)
	ps := threePlayers(t, h)
	d := join(t, h, "L", "D")
	if err := h.Spectate(d.c, true); err != nil {
		t.Fatal(err)
	}
	everyone := append(ps, d)
	for _, p := range everyone {
		p.s.drain()
	}
	version := h.rooms["L"].state.Version

	// In the lobby anyone may react; everyone in the room hears it.
	if err := h.React(ps[1].c, "🔥"); err != nil {
		t.Fatal(err)
	}
	for _, p := range everyone {
		ev := p.s.next(t, "reaction")
		if ev.PlayerName != "B" || ev.Emoji != "🔥" || ev.Lobby != nil {
			t.Errorf("%s got %+v", p.name, ev)
		}
	}
	if h.rooms["L"].state.Version != version {
		t.Error("reaction bumped the version")
	}
	if l, _ := st.Load("L"); l.Version != version {
		t.Error("reaction was persisted")
	}
	if err := h.React(ps[1].c, "🍕"); code(err) != "invalid" {
		t.Errorf("unknown emoji: %v", err)
	}
	if err := h.React(NewClient(newFake()), "🔥"); code(err) != "invalid" {
		t.Errorf("unbound: %v", err)
	}

	// Rate limit: a second one inside 700 ms is dropped without an error.
	fc.advance(500 * time.Millisecond)
	if err := h.React(ps[1].c, "😂"); err != nil {
		t.Fatal(err)
	}
	select {
	case ev := <-ps[0].s.events:
		t.Errorf("rate-limited reaction delivered: %+v", ev)
	default:
	}
	fc.advance(200 * time.Millisecond)
	if err := h.React(ps[1].c, "😂"); err != nil {
		t.Fatal(err)
	}
	if ev := ps[0].s.next(t, "reaction"); ev.Emoji != "😂" {
		t.Errorf("got %+v", ev)
	}
	// Other players have their own budget.
	if err := h.React(ps[2].c, "👀"); err != nil {
		t.Fatal(err)
	}
	ps[0].s.next(t, "reaction")

	// Mid-game only the audience may react.
	startAndAck(t, h, ps)
	fc.advance(time.Second)
	for _, p := range ps {
		if err := h.React(p.c, "👏"); code(err) != "invalid" {
			t.Errorf("alive %s: %v", p.name, err)
		}
	}
	if err := h.React(d.c, "👏"); err != nil {
		t.Errorf("spectator: %v", err)
	}
	if ev := ps[0].s.next(t, "reaction"); ev.PlayerName != "D" {
		t.Errorf("got %+v", ev)
	}
}

func TestPlayAgainRotatesHost(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	s := game.DefaultSettings()
	s.RotateHost = true
	if err := h.Settings(ps[0].c, s); err != nil {
		t.Fatal(err)
	}
	if err := h.PlayAgain(ps[0].c); code(err) != "invalid" {
		t.Errorf("play again in the lobby: %v", err)
	}
	startAndAck(t, h, ps)
	// Three players minus one is a decided game.
	h.Leave(ps[2].c)
	v := ps[0].s.latestLobby(t)
	if v.GamePhase != game.PhaseGameOver || v.GamesPlayed != 1 {
		t.Fatalf("view %+v", v)
	}
	if err := h.PlayAgain(ps[1].c); code(err) != "notHost" {
		t.Errorf("non-host: %v", err)
	}
	if err := h.PlayAgain(ps[0].c); err != nil {
		t.Fatal(err)
	}
	v = ps[1].s.latestLobby(t)
	if v.GamePhase != game.PhaseLobby || v.Host != "B" || v.GamesPlayed != 1 || len(v.Scores) != 3 {
		t.Errorf("after play again %+v", v)
	}
	// The seat really moved: only B can start, and A leaving no longer
	// closes the lobby.
	if err := h.Start(ps[0].c); code(err) != "notHost" {
		t.Errorf("old host start: %v", err)
	}
	c := join(t, h, "L", "C")
	if err := h.Start(ps[1].c); err != nil {
		t.Fatal(err)
	}
	h.Leave(ps[0].c)
	if v := c.s.latestLobby(t); len(v.Players) != 2 || v.Host != "B" {
		t.Errorf("after the old host left %+v", v)
	}
	if len(h.rooms) != 1 {
		t.Error("lobby closed when a non-host left")
	}
}

func TestSpectateAndMinPlayers(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	if err := h.Spectate(ps[2].c, true); err != nil {
		t.Fatal(err)
	}
	if v := ps[0].s.latestLobby(t); len(v.Spectators) != 1 || v.Spectators[0] != "C" {
		t.Errorf("spectators %v", v.Spectators)
	}
	if err := h.Start(ps[0].c); code(err) != "invalid" {
		t.Errorf("start with two players and a spectator: %v", err)
	}
	d := join(t, h, "L", "D")
	startAndAck(t, h, []*player{ps[0], ps[1], d})
	v := ps[2].s.latestLobby(t)
	if v.MyRole != game.RoleSpectator || v.MyWord == nil || v.GamePhase != game.PhasePlaying || len(v.AlivePlayers) != 3 {
		t.Errorf("spectator view %+v", v)
	}
}

func TestClueAndGuessThroughHub(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	d := join(t, h, "L", "D")
	all := append(ps, d)
	byName := map[string]*player{}
	for _, p := range all {
		byName[p.name] = p
	}
	s := game.DefaultSettings()
	s.ClueLog = true
	if err := h.Settings(ps[0].c, s); err != nil {
		t.Fatal(err)
	}
	startAndAck(t, h, all)
	v := ps[0].s.latestLobby(t)
	speaker := byName[v.RoundOrder[0]]
	if err := h.NextPlayer(speaker.c, 0); code(err) != "invalid" {
		t.Errorf("nextPlayer with the log on: %v", err)
	}
	if err := h.Clue(speaker.c, "shiny", 0); err != nil {
		t.Fatal(err)
	}
	v = ps[1].s.latestLobby(t)
	if len(v.Clues) != 1 || v.Clues[0].Text != "shiny" || v.Clues[0].Round != 1 || v.CurrentPlayerIndex != 1 {
		t.Errorf("view %+v", v)
	}
	if err := h.Guess(speaker.c, "x"); code(err) != "invalid" {
		t.Errorf("guess outside a last guess: %v", err)
	}
}
