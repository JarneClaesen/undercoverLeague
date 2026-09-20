package ws

import (
	"context"
	"log/slog"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
	"github.com/JarneClaesen/underCoverLeague/server/internal/hub"
	"github.com/JarneClaesen/underCoverLeague/server/internal/store"
)

type testClient struct {
	t  *testing.T
	ws *websocket.Conn
}

func dial(t *testing.T, srv *httptest.Server) *testClient {
	t.Helper()
	url := "ws" + strings.TrimPrefix(srv.URL, "http")
	c, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.CloseNow() })
	return &testClient{t: t, ws: c}
}

func (c *testClient) send(cmd Command) {
	c.t.Helper()
	if err := wsjson.Write(context.Background(), c.ws, cmd); err != nil {
		c.t.Fatal(err)
	}
}

// expect reads until an event of the given type arrives.
func (c *testClient) expect(typ string) hub.Event {
	c.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for {
		var ev hub.Event
		if err := wsjson.Read(ctx, c.ws, &ev); err != nil {
			c.t.Fatalf("waiting for %q: %v", typ, err)
		}
		if ev.Type == typ {
			return ev
		}
	}
}

func TestEndToEnd(t *testing.T) {
	st, err := store.Open(filepath.Join(t.TempDir(), "ws.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	h := hub.New(st, 50*time.Millisecond, slog.Default(), testCatalog())
	srv := httptest.NewServer(&Handler{Hub: h, Log: slog.Default()})
	defer srv.Close()

	a := dial(t, srv)
	a.send(Command{Type: "create", ReqID: 1, LobbyID: " t1 ", Name: "Alice"})
	joined := a.expect("joined")
	if joined.ReqID != 1 || !joined.IsHost || joined.LobbyID != "T1" || joined.Token == "" {
		t.Fatalf("joined %+v", joined)
	}

	b := dial(t, srv)
	b.send(Command{Type: "join", ReqID: 2, LobbyID: "t1", Name: "Bob"})
	b.expect("joined")

	// Errors carry the request id and a code the client can switch on.
	c := dial(t, srv)
	c.send(Command{Type: "join", ReqID: 3, LobbyID: "t1", Name: "Bob"})
	if ev := c.expect("error"); ev.ReqID != 3 || ev.Code != "nameTaken" {
		t.Fatalf("error %+v", ev)
	}
	c.send(Command{Type: "start"})
	if ev := c.expect("error"); ev.Code != "invalid" {
		t.Fatalf("unbound command %+v", ev)
	}
	c.send(Command{Type: "join", ReqID: 4, LobbyID: "t1", Name: "Cara"})
	c.expect("joined")

	// Settings are a host-only lobby mutation; the reply is a broadcast view
	// with the server's pool counts, and rejections are plain errors.
	b.send(Command{Type: "settings", Settings: &game.Settings{Filter: game.DefaultFilter(), Undercovers: 1}})
	if ev := b.expect("error"); ev.Code != "notHost" {
		t.Fatalf("non-host settings %+v", ev)
	}
	a.send(Command{Type: "settings"})
	if ev := a.expect("error"); ev.Code != "invalid" {
		t.Fatalf("missing settings %+v", ev)
	}
	a.send(Command{Type: "settings", Settings: &game.Settings{Filter: game.Filter{Packs: []game.Pack{game.PackChampions}, ChampSeasons: [2]int{15, 16}}, Undercovers: 1, RandomOrder: true}})
	for {
		ev := a.expect("lobby")
		if ev.Lobby.Settings.ChampSeasons == [2]int{15, 15} {
			if ev.Lobby.PoolSize == nil || (*ev.Lobby.PoolSize)[game.PackChampions] != 1 || len(*ev.Lobby.PoolSize) != 1 {
				t.Fatalf("pool size %+v", ev.Lobby.PoolSize)
			}
			break
		}
	}

	// Host starts; everyone gets a revealing view.
	a.send(Command{Type: "start"})
	for _, p := range []*testClient{a, b, c} {
		for {
			ev := p.expect("lobby")
			if ev.Lobby.GamePhase == "revealingRoles" {
				if ev.Lobby.MyRole == game.RoleCivilian && (ev.Lobby.MyWord == nil || *ev.Lobby.MyWord != "Mel" || ev.Lobby.MyIcon != "https://x/Mel_0.jpg") {
					t.Fatalf("civilian view %+v", ev.Lobby)
				}
				break
			}
		}
	}

	// Dropping the socket without "leave" keeps the seat until grace ends.
	b.ws.CloseNow()
	deadline := time.Now().Add(2 * time.Second)
	for {
		ev := a.expect("lobby")
		if len(ev.Lobby.Players) == 2 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("Bob never removed after grace")
		}
	}

	// Explicit leave by the host closes the lobby for everyone else.
	a.send(Command{Type: "leave"})
	c.expect("lobbyClosed")
}

func TestOversizedFrameIsRejected(t *testing.T) {
	st, _ := store.Open(filepath.Join(t.TempDir(), "ws.db"))
	defer st.Close()
	h := hub.New(st, time.Minute, slog.Default(), testCatalog())
	srv := httptest.NewServer(&Handler{Hub: h, Log: slog.Default()})
	defer srv.Close()

	c := dial(t, srv)
	c.send(Command{Type: "create", LobbyID: "x", Name: strings.Repeat("a", readLimit)})
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var ev hub.Event
	if err := wsjson.Read(ctx, c.ws, &ev); err == nil {
		t.Fatalf("expected the server to close the socket, got %+v", ev)
	}
}

func testCatalog() *game.Catalog {
	var all game.SeasonSet
	all.Add(16)
	return &game.Catalog{
		Patch: "16.18.1",
		Champions: []game.Champion{
			{Name: "Ahri", Icon: "https://x/Ahri_0.jpg", Season: 1},
			{Name: "Mel", Icon: "https://x/Mel_0.jpg", Season: 15},
		},
		Items: []game.Item{{Name: "Boots", Icon: "https://x/1001.png", Seasons: all, Tier: game.TierBoots}},
	}
}

// The new commands reach the hub with their fields; missing ones are plain
// errors and a reaction comes back as its own event.
func TestNewCommandsRoute(t *testing.T) {
	st, _ := store.Open(filepath.Join(t.TempDir(), "ws.db"))
	defer st.Close()
	h := hub.New(st, time.Minute, slog.Default(), testCatalog())
	srv := httptest.NewServer(&Handler{Hub: h, Log: slog.Default()})
	defer srv.Close()

	a := dial(t, srv)
	a.send(Command{Type: "create", ReqID: 1, LobbyID: "r1", Name: "Alice"})
	a.expect("joined")
	b := dial(t, srv)
	b.send(Command{Type: "join", ReqID: 2, LobbyID: "r1", Name: "Bob"})
	b.expect("joined")

	a.send(Command{Type: "spectate", ReqID: 3})
	if ev := a.expect("error"); ev.ReqID != 3 || ev.Code != "invalid" {
		t.Fatalf("spectate without a flag %+v", ev)
	}
	yes := true
	b.send(Command{Type: "spectate", ReqID: 4, Spectating: &yes})
	for {
		ev := a.expect("lobby")
		if len(ev.Lobby.Spectators) == 1 && ev.Lobby.Spectators[0] == "Bob" {
			break
		}
	}
	a.send(Command{Type: "clue", ReqID: 5, Text: "x"})
	if ev := a.expect("error"); ev.ReqID != 5 || ev.Code != "invalid" {
		t.Fatalf("clue without an index %+v", ev)
	}
	a.send(Command{Type: "guess", ReqID: 6, Word: "x"})
	if ev := a.expect("error"); ev.ReqID != 6 || ev.Code != "invalid" {
		t.Fatalf("guess in the lobby %+v", ev)
	}
	a.send(Command{Type: "playAgain", ReqID: 7})
	if ev := a.expect("error"); ev.ReqID != 7 || ev.Code != "invalid" {
		t.Fatalf("play again in the lobby %+v", ev)
	}
	a.send(Command{Type: "react", ReqID: 8, Emoji: "🍕"})
	if ev := a.expect("error"); ev.ReqID != 8 || ev.Code != "invalid" {
		t.Fatalf("unknown emoji %+v", ev)
	}
	b.send(Command{Type: "react", Emoji: "🔥"})
	for _, c := range []*testClient{a, b} {
		if ev := c.expect("reaction"); ev.PlayerName != "Bob" || ev.Emoji != "🔥" {
			t.Fatalf("reaction %+v", ev)
		}
	}
	// The settings command carries the rule fields too.
	s := game.DefaultSettings()
	s.TurnSeconds = 30
	s.ClueLog = true
	a.send(Command{Type: "settings", Settings: &s})
	for {
		ev := a.expect("lobby")
		if ev.Lobby.Settings.TurnSeconds == 30 && ev.Lobby.Settings.ClueLog {
			break
		}
	}
}
