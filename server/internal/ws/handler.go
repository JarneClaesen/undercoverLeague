// Package ws is the WebSocket transport: one goroutine pair per connection,
// JSON text frames in both directions, and a mapping from client commands
// onto hub calls. It knows nothing about game rules.
package ws

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
	"github.com/JarneClaesen/underCoverLeague/server/internal/hub"
)

// Command is a client -> server message. Only the fields relevant to Type
// are set; the rest are omitted on the wire.
type Command struct {
	Type  string `json:"type"` // create | join | resume | leave | settings | start | ack | nextPlayer | vote | reset
	ReqID int    `json:"reqId,omitempty"`

	LobbyID string `json:"lobbyId,omitempty"`
	Name    string `json:"name,omitempty"`
	Token   string `json:"token,omitempty"`

	Settings      *game.Filter `json:"settings,omitempty"`
	ExpectedIndex *int         `json:"expectedIndex,omitempty"`
	VotedFor      string       `json:"votedFor,omitempty"`
}

const (
	readLimit    = 4096
	sendBuffer   = 32
	pingInterval = 25 * time.Second
	writeTimeout = 10 * time.Second
)

type Handler struct {
	Hub *hub.Hub
	Log *slog.Logger
}

// conn implements hub.Sender. Send never blocks: the hub calls it while
// holding its lock, so a stalled socket must not stall every lobby.
type conn struct {
	ws     *websocket.Conn
	send   chan []byte
	ctx    context.Context
	cancel context.CancelFunc

	closeOnce sync.Once
	closing   chan struct{} // closed by Close; the writer flushes, then cancels
	mu        sync.Mutex
	reason    string // set by Close; read when the socket is finally closed
}

func (c *conn) Send(ev hub.Event) bool {
	b, err := json.Marshal(ev)
	if err != nil {
		return false
	}
	select {
	case c.send <- b:
		return true
	default:
		return false
	}
}

// Close asks for an orderly shutdown: queued events (e.g. lobbyClosed) are
// still written before the socket goes away.
func (c *conn) Close(reason string) {
	c.closeOnce.Do(func() {
		c.mu.Lock()
		c.reason = reason
		c.mu.Unlock()
		close(c.closing)
	})
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// No origin check on purpose: there is no cookie or ambient credential
	// to forge a request with. Every action needs the in-band session token,
	// the Flutter web build may be served from a different host in dev, and
	// native apps send no Origin at all.
	socket, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	socket.SetReadLimit(readLimit)

	ctx, cancel := context.WithCancel(r.Context())
	c := &conn{
		ws:      socket,
		send:    make(chan []byte, sendBuffer),
		ctx:     ctx,
		cancel:  cancel,
		closing: make(chan struct{}),
	}
	client := hub.NewClient(c)

	go c.writeLoop()
	go c.pingLoop()

	left := false
	for {
		var cmd Command
		if err := wsjson.Read(ctx, socket, &cmd); err != nil {
			break
		}
		if cmd.Type == "leave" {
			h.Hub.Leave(client)
			left = true
			c.Close("left")
			break
		}
		if err := h.dispatch(client, cmd); err != nil {
			c.Send(hub.ErrorEvent(cmd.ReqID, err))
		}
	}

	if !left {
		h.Hub.Disconnected(client)
	}
	cancel()
	c.mu.Lock()
	reason := c.reason
	c.mu.Unlock()
	status := websocket.StatusNormalClosure
	if reason != "" && reason != "left" {
		status = websocket.StatusGoingAway
	}
	socket.Close(status, reason)
}

func (h *Handler) dispatch(client *hub.Client, cmd Command) error {
	switch cmd.Type {
	case "create":
		return h.Hub.Create(client, cmd.ReqID, strings.TrimSpace(cmd.LobbyID), strings.TrimSpace(cmd.Name))
	case "join":
		return h.Hub.Join(client, cmd.ReqID, strings.TrimSpace(cmd.LobbyID), strings.TrimSpace(cmd.Name))
	case "resume":
		return h.Hub.Resume(client, cmd.ReqID, strings.TrimSpace(cmd.LobbyID), cmd.Token)
	case "settings":
		if cmd.Settings == nil {
			return &game.Error{Code: "invalid", Message: "settings is required."}
		}
		return h.Hub.Settings(client, *cmd.Settings)
	case "start":
		return h.Hub.Start(client)
	case "ack":
		return h.Hub.Acknowledge(client)
	case "nextPlayer":
		if cmd.ExpectedIndex == nil {
			return &game.Error{Code: "invalid", Message: "expectedIndex is required."}
		}
		return h.Hub.NextPlayer(client, *cmd.ExpectedIndex)
	case "vote":
		return h.Hub.Vote(client, cmd.VotedFor)
	case "reset":
		return h.Hub.Reset(client)
	default:
		return &game.Error{Code: "invalid", Message: "Unknown command."}
	}
}

func (c *conn) writeLoop() {
	defer c.cancel()
	for {
		select {
		case <-c.ctx.Done():
			return
		case b := <-c.send:
			if !c.write(b) {
				return
			}
		case <-c.closing:
			// Flush whatever is queued, then let the read loop close the socket.
			for {
				select {
				case b := <-c.send:
					if !c.write(b) {
						return
					}
				default:
					return
				}
			}
		}
	}
}

func (c *conn) write(b []byte) bool {
	ctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
	defer cancel()
	return c.ws.Write(ctx, websocket.MessageText, b) == nil
}

// pingLoop notices sockets that died without a close frame (mobile NAT
// timeouts, killed apps) so the hub can start the player's grace timer.
func (c *conn) pingLoop() {
	t := time.NewTicker(pingInterval)
	defer t.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-t.C:
			ctx, cancel := context.WithTimeout(c.ctx, writeTimeout)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil && !errors.Is(err, context.Canceled) {
				c.Close("ping timeout")
				return
			}
		}
	}
}
