package hub

import (
	"errors"
	"log/slog"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
	"github.com/JarneClaesen/underCoverLeague/server/internal/store"
)

type fakeSender struct {
	events chan Event
	closed chan string
}

func newFake() *fakeSender {
	return &fakeSender{events: make(chan Event, 64), closed: make(chan string, 4)}
}

func (f *fakeSender) Send(ev Event) bool {
	select {
	case f.events <- ev:
		return true
	default:
		return false
	}
}

func (f *fakeSender) Close(reason string) {
	select {
	case f.closed <- reason:
	default:
	}
}

// next returns the next event of the given type, dropping others.
func (f *fakeSender) next(t *testing.T, typ string) Event {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		select {
		case ev := <-f.events:
			if ev.Type == typ {
				return ev
			}
		case <-deadline:
			t.Fatalf("no %q event", typ)
		}
	}
}

// latestLobby drains the queue and returns the last lobby view seen,
// waiting for at least one.
func (f *fakeSender) latestLobby(t *testing.T) *game.View {
	t.Helper()
	ev := f.next(t, "lobby")
	for {
		select {
		case more := <-f.events:
			if more.Type == "lobby" {
				ev = more
			}
		default:
			return ev.Lobby
		}
	}
}

func (f *fakeSender) drain() {
	for {
		select {
		case <-f.events:
		default:
			return
		}
	}
}

type player struct {
	c     *Client
	s     *fakeSender
	token string
	name  string
}

func newHub(t *testing.T, grace time.Duration) (*Hub, *store.Store) {
	t.Helper()
	st, err := store.Open(filepath.Join(t.TempDir(), "h.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	return New(st, grace, slog.Default(), testCatalog()), st
}

// testCatalog is a minimal pool: two champions from different seasons and
// two items, enough to exercise settings and empty-pool rejections.
func testCatalog() *game.Catalog {
	var all game.SeasonSet
	all.Add(3)
	all.Add(16)
	return &game.Catalog{
		Patch: "16.18.1",
		Champions: []game.Champion{
			{Name: "Ahri", Icon: "https://x/Ahri_0.jpg", Season: 1},
			{Name: "Mel", Icon: "https://x/Mel_0.jpg", Season: 15},
		},
		Items: []game.Item{
			{Name: "Boots", Icon: "https://x/1001.png", Seasons: all, Tier: game.TierBoots},
			{Name: "Infinity Edge", Icon: "https://x/3031.png", Seasons: all, Tier: game.TierLegendary},
		},
	}
}

// settings wraps a filter in otherwise default rules.
func settings(f game.Filter) game.Settings {
	s := game.DefaultSettings()
	s.Filter = f
	return s
}

func create(t *testing.T, h *Hub, lobby, name string) *player {
	t.Helper()
	s := newFake()
	c := NewClient(s)
	if err := h.Create(c, 1, lobby, name); err != nil {
		t.Fatal(err)
	}
	j := s.next(t, "joined")
	if !j.IsHost || j.PlayerName != name {
		t.Fatalf("joined %+v", j)
	}
	return &player{c: c, s: s, token: j.Token, name: name}
}

func join(t *testing.T, h *Hub, lobby, name string) *player {
	t.Helper()
	s := newFake()
	c := NewClient(s)
	if err := h.Join(c, 2, lobby, name); err != nil {
		t.Fatal(err)
	}
	j := s.next(t, "joined")
	return &player{c: c, s: s, token: j.Token, name: name}
}

func code(err error) string {
	var e *game.Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func threePlayers(t *testing.T, h *Hub) []*player {
	t.Helper()
	ps := []*player{create(t, h, "L", "A"), join(t, h, "L", "B"), join(t, h, "L", "C")}
	for _, p := range ps {
		p.s.drain()
	}
	return ps
}

func startAndAck(t *testing.T, h *Hub, ps []*player) {
	t.Helper()
	if err := h.Start(ps[0].c); err != nil {
		t.Fatal(err)
	}
	for _, p := range ps {
		if err := h.Acknowledge(p.c); err != nil {
			t.Fatal(err)
		}
	}
}

func TestCreateJoinViews(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	a := create(t, h, "L", "A")
	b := join(t, h, "L", "B")
	for _, p := range []*player{a, b} {
		v := p.s.latestLobby(t)
		if len(v.Players) != 2 || v.Host != "A" || v.MyRole != game.RoleSpectator || !v.Connected["A"] || !v.Connected["B"] {
			t.Errorf("%s view %+v", p.name, v)
		}
	}
	if err := h.Create(NewClient(newFake()), 1, "L", "Z"); code(err) != "exists" {
		t.Errorf("duplicate create: %v", err)
	}
	if err := h.Join(NewClient(newFake()), 1, "L", "B"); code(err) != "nameTaken" {
		t.Errorf("duplicate join: %v", err)
	}
	if err := h.Join(NewClient(newFake()), 1, "nope", "B"); code(err) != "notFound" {
		t.Errorf("unknown lobby: %v", err)
	}
	if err := h.Join(a.c, 1, "L", "Q"); code(err) != "invalid" {
		t.Errorf("join while bound: %v", err)
	}
}

func TestLobbyCodesAreCaseInsensitive(t *testing.T) {
	h, _ := newHub(t, time.Minute)

	first := newFake()
	if err := h.Create(NewClient(first), 1, " abc12 ", "A"); err != nil {
		t.Fatal(err)
	}
	if j := first.next(t, "joined"); j.LobbyID != "ABC12" {
		t.Fatalf("created lobby %q, want the upper-case code", j.LobbyID)
	}
	if v := first.latestLobby(t); v.ID != "ABC12" {
		t.Errorf("view id %q", v.ID)
	}

	// Joining, colliding on create and resuming all ignore case.
	b := join(t, h, "Abc12", "B")
	if err := h.Create(NewClient(newFake()), 1, "aBC12", "C"); code(err) != "exists" {
		t.Errorf("create with a different casing: %v", err)
	}
	h.Disconnected(b.c)
	resumed := newFake()
	if err := h.Resume(NewClient(resumed), 5, "abc12", b.token); err != nil {
		t.Fatalf("resume: %v", err)
	}
	if j := resumed.next(t, "joined"); j.LobbyID != "ABC12" || j.PlayerName != "B" {
		t.Errorf("resumed %+v", j)
	}
}

func TestCreateWithoutIDGeneratesCode(t *testing.T) {
	h, _ := newHub(t, time.Minute)

	first := newFake()
	if err := h.Create(NewClient(first), 3, "", "A"); err != nil {
		t.Fatal(err)
	}
	j := first.next(t, "joined")
	if j.ReqID != 3 || !j.IsHost || j.PlayerName != "A" {
		t.Fatalf("joined %+v", j)
	}
	if len(j.LobbyID) != codeLength {
		t.Fatalf("code %q is not %d characters", j.LobbyID, codeLength)
	}
	for _, r := range j.LobbyID {
		if !strings.ContainsRune(codeAlphabet, r) {
			t.Fatalf("code %q uses %q, which is not in the alphabet", j.LobbyID, r)
		}
	}
	// The generated code is the lobby's real ID: it can be joined and it is
	// what the views carry.
	if v := first.latestLobby(t); v.ID != j.LobbyID {
		t.Errorf("view id %q, joined said %q", v.ID, j.LobbyID)
	}
	join(t, h, j.LobbyID, "B")

	second := newFake()
	if err := h.Create(NewClient(second), 4, "", "C"); err != nil {
		t.Fatal(err)
	}
	if j2 := second.next(t, "joined"); j2.LobbyID == j.LobbyID {
		t.Errorf("both lobbies got the code %q", j2.LobbyID)
	}

	// Only the empty id skips validation.
	if err := h.Create(NewClient(newFake()), 5, "a/b", "D"); code(err) != "invalid" {
		t.Errorf("invalid id: %v", err)
	}
	if err := h.Create(NewClient(newFake()), 6, strings.Repeat("x", 65), "D"); code(err) != "invalid" {
		t.Errorf("overlong id: %v", err)
	}
}

func TestStartHidesSecretsAndAutoAdvances(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	if err := h.Start(ps[1].c); code(err) != "notHost" {
		t.Errorf("non-host start: %v", err)
	}
	if err := h.Start(ps[0].c); err != nil {
		t.Fatal(err)
	}
	undercovers := 0
	for _, p := range ps {
		v := p.s.latestLobby(t)
		if v.GamePhase != game.PhaseRevealing || v.Roles != nil || v.SelectedWord != "" {
			t.Errorf("%s leaked secrets: %+v", p.name, v)
		}
		switch v.MyRole {
		case game.RoleUndercover:
			undercovers++
			if v.MyWord != nil {
				t.Errorf("undercover %s got the word", p.name)
			}
		case game.RoleCivilian:
			if v.MyWord == nil || *v.MyWord == "" {
				t.Errorf("civilian %s got no word", p.name)
			}
		default:
			t.Errorf("%s role %q", p.name, v.MyRole)
		}
	}
	if undercovers != 1 {
		t.Fatalf("%d undercovers", undercovers)
	}

	// Nobody sends a "start rounds" command: acknowledging is enough.
	for _, p := range ps {
		if err := h.Acknowledge(p.c); err != nil {
			t.Fatal(err)
		}
	}
	for _, p := range ps {
		if v := p.s.latestLobby(t); v.GamePhase != game.PhasePlaying {
			t.Errorf("%s phase %s", p.name, v.GamePhase)
		}
	}
}

func TestVotingTalliesServerSide(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	startAndAck(t, h, ps)
	byName := map[string]*player{}
	for _, p := range ps {
		byName[p.name] = p
	}
	v := ps[0].s.latestLobby(t)
	for i, name := range v.RoundOrder {
		if err := h.NextPlayer(byName[name].c, i); err != nil {
			t.Fatal(err)
		}
	}
	if v = ps[0].s.latestLobby(t); !v.RoundFinished {
		t.Fatalf("round not finished: %+v", v)
	}
	// Everyone votes for the player after them in round order: a 3-way tie.
	for i, name := range v.RoundOrder {
		target := v.RoundOrder[(i+1)%3]
		if err := h.Vote(byName[name].c, target); err != nil {
			t.Fatal(err)
		}
	}
	v = ps[1].s.latestLobby(t)
	if v.RoundFinished || v.LastEliminated == nil || *v.LastEliminated != "" || len(v.AlivePlayers) != 3 {
		t.Errorf("tie not handled: %+v", v)
	}
}

func TestDisconnectGraceAndResume(t *testing.T) {
	h, _ := newHub(t, 40*time.Millisecond)
	ps := threePlayers(t, h)
	a, b := ps[0], ps[1]

	h.Disconnected(b.c)
	if v := a.s.latestLobby(t); v.Connected["B"] || len(v.Players) != 3 {
		t.Fatalf("B should be seated but disconnected: %+v", v)
	}

	// Resume within the grace window keeps the seat.
	b2 := newFake()
	if err := h.Resume(NewClient(b2), 5, "L", b.token); err != nil {
		t.Fatal(err)
	}
	if j := b2.next(t, "joined"); j.PlayerName != "B" || j.IsHost {
		t.Errorf("resume joined %+v", j)
	}
	time.Sleep(80 * time.Millisecond)
	if v := a.s.latestLobby(t); !v.Connected["B"] || len(v.Players) != 3 {
		t.Fatalf("B lost after resume: %+v", v)
	}

	// Bad token.
	if err := h.Resume(NewClient(newFake()), 5, "L", "nope"); code(err) != "expired" {
		t.Errorf("bad token: %v", err)
	}
}

func TestDisconnectExpiryRemovesPlayer(t *testing.T) {
	h, _ := newHub(t, 30*time.Millisecond)
	ps := threePlayers(t, h)
	a, c := ps[0], ps[2]
	h.Disconnected(c.c)
	time.Sleep(90 * time.Millisecond)
	if v := a.s.latestLobby(t); len(v.Players) != 2 {
		t.Fatalf("C not removed: %+v", v)
	}
	// The old token is gone with the seat.
	if err := h.Resume(NewClient(newFake()), 1, "L", c.token); code(err) != "expired" {
		t.Errorf("stale token: %v", err)
	}
}

func TestSeatTakeoverByName(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	startAndAck(t, h, ps)
	b := ps[1]
	role := b.s.latestLobby(t).MyRole
	h.Disconnected(b.c)

	// Joining under the same name while disconnected takes the seat over,
	// even mid-game.
	b2 := join(t, h, "L", "B")
	if v := b2.s.latestLobby(t); v.MyRole != role || v.GamePhase != game.PhasePlaying {
		t.Errorf("takeover view %+v", v)
	}
	if err := h.Resume(NewClient(newFake()), 1, "L", b.token); code(err) != "expired" {
		t.Errorf("old token should be revoked: %v", err)
	}
	// A connected seat cannot be taken.
	if err := h.Join(NewClient(newFake()), 1, "L", "B"); code(err) != "inProgress" {
		t.Errorf("join over connected seat: %v", err)
	}
}

func TestHostLeaveClosesLobby(t *testing.T) {
	h, st := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	h.Leave(ps[0].c)
	for _, p := range ps[1:] {
		p.s.next(t, "lobbyClosed")
		select {
		case <-p.s.closed:
		default:
			t.Errorf("%s not closed", p.name)
		}
	}
	if l, _ := st.Load("L"); l != nil {
		t.Error("lobby still stored")
	}
	if len(h.LiveIDs()) != 0 {
		t.Error("room still live")
	}
}

func TestKick(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	a, b, c := ps[0], ps[1], ps[2]

	if err := h.Kick(b.c, "C"); code(err) != "notHost" {
		t.Errorf("non-host kick: %v", err)
	}
	if err := h.Kick(a.c, "A"); code(err) != "invalid" {
		t.Errorf("self kick: %v", err)
	}
	if err := h.Kick(a.c, "C"); err != nil {
		t.Fatal(err)
	}
	c.s.next(t, "kicked")
	select {
	case reason := <-c.s.closed:
		if reason != "kicked" {
			t.Errorf("close reason %q", reason)
		}
	default:
		t.Error("C not closed")
	}
	for _, p := range []*player{a, b} {
		if v := p.s.latestLobby(t); len(v.Players) != 2 || slices.Contains(v.Players, "C") {
			t.Errorf("%s sees %v", p.name, v.Players)
		}
	}
	// The kicked connection is unbound and its token is gone.
	if err := h.Kick(c.c, "B"); code(err) != "invalid" {
		t.Errorf("kicked client still bound: %v", err)
	}
	if err := h.Resume(NewClient(newFake()), 1, "L", c.token); code(err) != "expired" {
		t.Errorf("kicked token should be revoked: %v", err)
	}
	// Nothing bars them from coming back.
	join(t, h, "L", "C")
}

func TestKickDisconnectedPlayerMidGame(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	startAndAck(t, h, ps)
	h.Disconnected(ps[2].c)
	if err := h.Kick(ps[0].c, "C"); err != nil {
		t.Fatal(err)
	}
	v := ps[0].s.latestLobby(t)
	if slices.Contains(v.Players, "C") || v.GamePhase != game.PhaseGameOver {
		t.Errorf("view %+v", v)
	}
	if len(h.rooms["L"].timers) != 0 {
		t.Error("grace timer still pending for C")
	}
}

func TestHostGraceExpiryClosesLobby(t *testing.T) {
	h, _ := newHub(t, 30*time.Millisecond)
	ps := threePlayers(t, h)
	h.Disconnected(ps[0].c)
	ps[1].s.next(t, "lobbyClosed")
}

func TestNonHostLeaveMidGame(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)
	startAndAck(t, h, ps)
	h.Leave(ps[2].c)
	v := ps[0].s.latestLobby(t)
	if len(v.Players) != 2 {
		t.Errorf("C still present: %+v", v)
	}
	// Three players minus one is two alive: the game resolves.
	if v.GamePhase != game.PhaseGameOver {
		t.Errorf("phase %s", v.GamePhase)
	}
}

func TestResumeAcrossRestart(t *testing.T) {
	st, err := store.Open(filepath.Join(t.TempDir(), "r.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	h1 := New(st, time.Minute, slog.Default(), testCatalog())
	a := create(t, h1, "L", "A")
	join(t, h1, "L", "B")
	h1.Shutdown()
	select {
	case <-a.s.closed:
	default:
		t.Fatal("shutdown did not close connections")
	}

	h2 := New(st, time.Minute, slog.Default(), testCatalog())
	a2 := newFake()
	if err := h2.Resume(NewClient(a2), 9, "L", a.token); err != nil {
		t.Fatal(err)
	}
	if j := a2.next(t, "joined"); !j.IsHost || j.ReqID != 9 {
		t.Errorf("joined %+v", j)
	}
	if v := a2.latestLobby(t); len(v.Players) != 2 || v.Connected["B"] {
		t.Errorf("view after restart %+v", v)
	}
}

func TestSlowConsumerIsDropped(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	a := create(t, h, "L", "A")
	slow := &fakeSender{events: make(chan Event, 1), closed: make(chan string, 1)}
	if err := h.Join(NewClient(slow), 1, "L", "B"); err != nil {
		t.Fatal(err)
	}
	// Buffer of one holds "joined"; the following lobby view overflows.
	select {
	case <-slow.closed:
	default:
		t.Fatal("slow client not closed")
	}
	if v := a.s.latestLobby(t); v.Connected["B"] {
		t.Errorf("B should show as disconnected: %+v", v)
	}
}

func TestSettingsAndPoolSize(t *testing.T) {
	h, _ := newHub(t, time.Minute)
	ps := threePlayers(t, h)

	if err := h.Settings(ps[1].c, game.DefaultSettings()); code(err) != "notHost" {
		t.Errorf("non-host settings: %v", err)
	}
	f := settings(game.Filter{Packs: []game.Pack{game.PackChampions, game.PackItems}, ChampSeasons: [2]int{15, 16}, ItemTiers: []game.Tier{game.TierBoots}})
	if err := h.Settings(ps[0].c, f); err != nil {
		t.Fatal(err)
	}
	// Everyone sees the normalized settings and the server's counts.
	for _, p := range ps {
		v := p.s.latestLobby(t)
		if v.Settings.ChampSeasons != [2]int{15, 15} || v.Settings.ItemSeasons != [2]int{3, 16} || len(v.Settings.ItemTiers) != 1 {
			t.Errorf("%s settings %+v", p.name, v.Settings)
		}
		if v.PoolSize == nil || (*v.PoolSize)[game.PackChampions] != 1 || (*v.PoolSize)[game.PackItems] != 1 {
			t.Errorf("%s pool %+v", p.name, v.PoolSize)
		}
		if v.SeasonRange == nil || v.SeasonRange.Champions != [2]int{1, 15} {
			t.Errorf("%s range %+v", p.name, v.SeasonRange)
		}
	}

	// An empty pool is refused at start and nothing changes.
	if err := h.Settings(ps[0].c, settings(game.Filter{Packs: []game.Pack{game.PackChampions}, ChampSeasons: [2]int{2, 2}})); err != nil {
		t.Fatal(err)
	}
	if v := ps[0].s.latestLobby(t); (*v.PoolSize)[game.PackChampions] != 0 {
		t.Errorf("pool %+v", v.PoolSize)
	}
	if err := h.Start(ps[0].c); code(err) != "invalid" {
		t.Errorf("empty pool start: %v", err)
	}
	if h.rooms["L"].state.GameStarted {
		t.Error("game started with an empty pool")
	}

	// A catalog refresh shows up in the counts on the next change.
	bigger := testCatalog()
	bigger.Champions = append(bigger.Champions, game.Champion{Name: "Yunara", Icon: "https://x/Yunara_0.jpg", Season: 16})
	h.SetCatalog(bigger)
	h.SetCatalog(nil) // ignored
	if err := h.Settings(ps[0].c, settings(game.Filter{Packs: []game.Pack{game.PackChampions}, ChampSeasons: [2]int{16, 16}})); err != nil {
		t.Fatal(err)
	}
	if v := ps[2].s.latestLobby(t); (*v.PoolSize)[game.PackChampions] != 1 || v.SeasonRange.Champions != [2]int{1, 16} {
		t.Errorf("after refresh %+v %+v", v.PoolSize, v.SeasonRange)
	}

	// Started games carry the https icon to civilians and no pool info.
	if err := h.Start(ps[0].c); err != nil {
		t.Fatal(err)
	}
	for _, p := range ps {
		v := p.s.latestLobby(t)
		if v.PoolSize != nil || v.SeasonRange != nil {
			t.Errorf("%s got pool info mid-game", p.name)
		}
		if v.MyRole == game.RoleCivilian && (v.MyWord == nil || *v.MyWord != "Yunara" || v.MyIcon != "https://x/Yunara_0.jpg") {
			t.Errorf("%s civilian view %+v", p.name, v)
		}
	}
	if err := h.Settings(ps[0].c, game.DefaultSettings()); code(err) != "invalid" {
		t.Errorf("settings mid-game: %v", err)
	}
}
