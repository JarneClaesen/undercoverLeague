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
	h := hub.New(st, 50*time.Millisecond, slog.Default())
	srv := httptest.NewServer(&Handler{Hub: h, Log: slog.Default()})
	defer srv.Close()

	a := dial(t, srv)
	a.send(Command{Type: "create", ReqID: 1, LobbyID: " t1 ", Name: "Alice"})
	joined := a.expect("joined")
	if joined.ReqID != 1 || !joined.IsHost || joined.LobbyID != "t1" || joined.Token == "" {
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

	// Host starts; everyone gets a revealing view.
	a.send(Command{Type: "start"})
	for _, p := range []*testClient{a, b, c} {
		for {
			ev := p.expect("lobby")
			if ev.Lobby.GamePhase == "revealingRoles" {
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
	h := hub.New(st, time.Minute, slog.Default())
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
