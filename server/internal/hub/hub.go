// Package hub owns the live lobbies: which connection is which player, the
// disconnect grace timers, write-through persistence and the per-player
// broadcasts. The game rules themselves live in package game.
//
// One mutex guards everything. A party game mutates a lobby about once a
// second and each mutation is microseconds plus one SQLite upsert, so a
// global lock is both fast enough and removes every lock-ordering question.
package hub

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	mathrand "math/rand/v2"
	"sync"
	"sync/atomic"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
	"github.com/JarneClaesen/underCoverLeague/server/internal/store"
)

// Event is a server -> client message.
type Event struct {
	Type  string `json:"type"` // lobby | joined | error | lobbyClosed | reaction
	ReqID int    `json:"reqId,omitempty"`

	Lobby *game.View `json:"lobby,omitempty"`

	Token      string `json:"token,omitempty"`
	LobbyID    string `json:"lobbyId,omitempty"`
	PlayerName string `json:"playerName,omitempty"`
	Emoji      string `json:"emoji,omitempty"` // reaction
	IsHost     bool   `json:"isHost,omitempty"`

	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
}

// ErrorEvent builds the error event for a rejected command.
func ErrorEvent(reqID int, err error) Event {
	var e *game.Error
	if errors.As(err, &e) {
		return Event{Type: "error", ReqID: reqID, Code: e.Code, Message: e.Message}
	}
	return Event{Type: "error", ReqID: reqID, Code: "internal", Message: "Something went wrong."}
}

// Sender is the transport side of a client. Send must not block: the
// WebSocket implementation queues into a bounded buffer and returns false
// when the client cannot keep up, at which point the hub drops it.
type Sender interface {
	Send(ev Event) bool
	Close(reason string)
}

// Client is one connection. It is unbound until create/join/resume succeeds.
type Client struct {
	sender Sender
	room   *room  // nil while unbound; guarded by Hub.mu
	player string // guarded by Hub.mu
}

func NewClient(s Sender) *Client { return &Client{sender: s} }

type graceTimer struct {
	seq   int64
	timer *time.Timer
}

// deadlineTimer fires the game's turn timer. What it was armed for is kept
// so the callback can tell whether the lobby moved on in the meantime.
type deadlineTimer struct {
	deadline int64
	version  int64
	timer    *time.Timer
}

type room struct {
	state  *game.Lobby
	conns  map[string]*Client     // player -> attached client
	timers map[string]*graceTimer // player -> pending removal
	seq    int64
	// deadline is the pending turn timer, nil when the game is untimed or
	// waiting on nothing.
	deadline *deadlineTimer
	// lastReaction rate-limits reactions per player.
	lastReaction map[string]time.Time
}

func newRoom(state *game.Lobby) *room {
	return &room{
		state:        state,
		conns:        map[string]*Client{},
		timers:       map[string]*graceTimer{},
		lastReaction: map[string]time.Time{},
	}
}

// reactionInterval is the minimum gap between two reactions of one player;
// faster ones are dropped silently.
const reactionInterval = 700 * time.Millisecond

type Hub struct {
	mu    sync.Mutex
	rooms map[string]*room
	store *store.Store
	// catalog is swapped whole by SetCatalog when Data Dragon is refreshed;
	// a lobby that already drew its word is unaffected.
	catalog atomic.Pointer[game.Catalog]
	grace   time.Duration
	rng     *mathrand.Rand
	log     *slog.Logger
	now     func() time.Time
	// after schedules the turn timers; tests replace it to fire them by hand.
	after func(d time.Duration, f func()) *time.Timer
}

func New(st *store.Store, grace time.Duration, log *slog.Logger, cat *game.Catalog) *Hub {
	var seed [32]byte
	rand.Read(seed[:])
	h := &Hub{
		rooms: map[string]*room{},
		store: st,
		grace: grace,
		rng:   mathrand.New(mathrand.NewChaCha8(seed)),
		log:   log,
		now:   time.Now,
		after: time.AfterFunc,
	}
	h.SetCatalog(cat)
	return h
}

// SetCatalog publishes a new word pool. Views are not rebroadcast: the
// pool counts a lobby shows refresh on its next change.
func (h *Hub) SetCatalog(c *game.Catalog) {
	if c != nil {
		h.catalog.Store(c)
	}
}

// ---------------------------------------------------------------------------
// Binding a connection to a player
// ---------------------------------------------------------------------------

// Create opens a new lobby. An empty id asks the server for a generated
// code; anything else is validated and must not be taken. Either way the
// "joined" event carries the code the lobby actually got. Codes are case
// insensitive: they are stored and echoed back in upper case.
func (h *Hub) Create(c *Client, reqID int, id, name string) error {
	id = game.NormalizeLobbyID(id)
	generate := id == ""
	if !generate {
		if err := game.ValidateLobbyID(id); err != nil {
			return err
		}
	}
	if err := game.ValidatePlayerName(name); err != nil {
		return err
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room != nil {
		return game.ErrInvalid
	}
	if generate {
		code, err := h.generateID()
		if err != nil {
			return err
		}
		id = code
	} else if r, err := h.getOrLoad(id); err != nil {
		return err
	} else if r != nil {
		return game.ErrExists
	}
	r := newRoom(game.New(id, name, h.now()))
	h.rooms[id] = r
	h.attach(r, c, reqID, name)
	h.commit(r)
	return nil
}

func (h *Hub) Join(c *Client, reqID int, id, name string) error {
	id = game.NormalizeLobbyID(id)
	if err := game.ValidateLobbyID(id); err != nil {
		return err
	}
	if err := game.ValidatePlayerName(name); err != nil {
		return err
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room != nil {
		return game.ErrInvalid
	}
	r, err := h.getOrLoad(id)
	if err != nil {
		return err
	}
	if r == nil {
		return game.ErrNotFound
	}
	// A player who is in the lobby but not connected (grace window, or the
	// server restarted) gets their seat back by joining under the same
	// name. That is what makes "reopen the app and rejoin" work.
	if _, seated := r.timers[name]; seated && r.conns[name] == nil {
		for token, p := range r.state.Sessions {
			if p == name {
				delete(r.state.Sessions, token)
			}
		}
		h.attach(r, c, reqID, name)
		h.commit(r)
		return nil
	}
	if err := r.state.Join(name); err != nil {
		return err
	}
	h.attach(r, c, reqID, name)
	h.commit(r)
	return nil
}

func (h *Hub) Resume(c *Client, reqID int, id, token string) error {
	id = game.NormalizeLobbyID(id)
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room != nil {
		return game.ErrInvalid
	}
	r, err := h.getOrLoad(id)
	if err != nil {
		return err
	}
	if r == nil {
		return game.ErrNotFound
	}
	name, ok := r.state.Sessions[token]
	if !ok {
		return game.ErrExpired
	}
	// Newest connection wins; the old one (if still open) is told to go.
	if old := r.conns[name]; old != nil && old != c {
		old.room = nil
		old.sender.Close("superseded")
	}
	h.cancelTimer(r, name)
	c.room, c.player = r, name
	r.conns[name] = c
	c.sender.Send(Event{
		Type: "joined", ReqID: reqID, Token: token, LobbyID: id,
		PlayerName: name, IsHost: name == r.state.Host,
	})
	h.broadcast(r)
	return nil
}

// attach binds c to player with a fresh token and tells it so. Caller holds
// h.mu and commits afterwards.
func (h *Hub) attach(r *room, c *Client, reqID int, player string) {
	token := newToken()
	r.state.Sessions[token] = player
	h.cancelTimer(r, player)
	c.room, c.player = r, player
	r.conns[player] = c
	c.sender.Send(Event{
		Type: "joined", ReqID: reqID, Token: token, LobbyID: r.state.ID,
		PlayerName: player, IsHost: player == r.state.Host,
	})
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

// Apply runs one game mutation for the bound player, then advances the game,
// persists and broadcasts. An error from fn is returned to the caller only.
func (h *Hub) Apply(c *Client, fn func(l *game.Lobby, player string) error) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room == nil {
		return &game.Error{Code: "invalid", Message: "Not in a lobby."}
	}
	if err := fn(c.room.state, c.player); err != nil {
		return err
	}
	h.commit(c.room)
	return nil
}

func (h *Hub) Settings(c *Client, s game.Settings) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.SetSettings(p, s) })
}

func (h *Hub) Spectate(c *Client, spectating bool) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Spectate(p, spectating) })
}

func (h *Hub) Start(c *Client) error {
	return h.Apply(c, func(l *game.Lobby, p string) error {
		return l.Start(p, h.rng, h.catalog.Load())
	})
}

func (h *Hub) Acknowledge(c *Client) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Acknowledge(p) })
}

func (h *Hub) NextPlayer(c *Client, expectedIndex int) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.NextPlayer(p, expectedIndex, h.now()) })
}

func (h *Hub) Clue(c *Client, text string, expectedIndex int) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Clue(p, text, expectedIndex, h.now()) })
}

func (h *Hub) Vote(c *Client, votedFor string) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Vote(p, votedFor) })
}

func (h *Hub) Guess(c *Client, word string) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Guess(p, word, h.now(), h.rng) })
}

func (h *Hub) Reset(c *Client) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.Reset(p) })
}

func (h *Hub) PlayAgain(c *Client) error {
	return h.Apply(c, func(l *game.Lobby, p string) error { return l.PlayAgain(p) })
}

// React relays an emoji from a watcher to everyone in the room. Nothing is
// stored and the lobby version does not move: a reaction that arrives late
// or not at all is no loss. Too-frequent ones are dropped without a word.
func (h *Hub) React(c *Client, emoji string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room == nil {
		return &game.Error{Code: "invalid", Message: "Not in a lobby."}
	}
	if !game.ValidReaction(emoji) {
		return &game.Error{Code: "invalid", Message: "Unknown reaction."}
	}
	r, player := c.room, c.player
	if err := r.state.CanReact(player); err != nil {
		return err
	}
	now := h.now()
	if last, ok := r.lastReaction[player]; ok && now.Sub(last) < reactionInterval {
		return nil
	}
	r.lastReaction[player] = now
	h.deliver(r, Event{Type: "reaction", PlayerName: player, Emoji: emoji})
	return nil
}

// Leave removes the player immediately (no grace) and unbinds c.
func (h *Hub) Leave(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room == nil {
		return
	}
	r, player := c.room, c.player
	c.room = nil
	if r.conns[player] == c {
		delete(r.conns, player)
	}
	h.removePlayer(r, player)
}

// Disconnected is called by the transport when the socket went away
// without a leave. The seat is kept for the grace period.
func (h *Hub) Disconnected(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if c.room == nil {
		return
	}
	r, player := c.room, c.player
	c.room = nil
	if r.conns[player] != c {
		return // already superseded by a resume
	}
	delete(r.conns, player)
	h.startTimer(r, player)
	h.broadcast(r)
}

// LiveIDs lists the lobbies currently in memory, for the purge job to skip.
func (h *Hub) LiveIDs() []string {
	h.mu.Lock()
	defer h.mu.Unlock()
	ids := make([]string, 0, len(h.rooms))
	for id := range h.rooms {
		ids = append(ids, id)
	}
	return ids
}

// Shutdown closes every connection. State is already in the store; clients
// resume into the next process.
func (h *Hub) Shutdown() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, r := range h.rooms {
		for _, c := range r.conns {
			c.room = nil
			c.sender.Close("shutdown")
		}
		r.conns = map[string]*Client{}
		h.cancelDeadline(r)
		for p := range r.timers {
			h.cancelTimer(r, p)
		}
	}
	h.rooms = map[string]*room{}
}

// ---------------------------------------------------------------------------
// Internals (all called with h.mu held)
// ---------------------------------------------------------------------------

func (h *Hub) getOrLoad(id string) (*room, error) {
	if r, ok := h.rooms[id]; ok {
		return r, nil
	}
	l, err := h.store.Load(id)
	if err != nil {
		h.log.Error("load lobby", "id", id, "err", err)
		return nil, &game.Error{Code: "internal", Message: "Could not load the lobby."}
	}
	if l == nil {
		return nil, nil
	}
	// Nobody is connected to a lobby that just came off disk. Give everyone
	// the grace period to come back, after which they are removed exactly
	// as if they had dropped while the server was up.
	r := newRoom(l)
	h.rooms[id] = r
	for _, p := range l.Players {
		h.startTimer(r, p)
	}
	// A turn that was running when the process stopped keeps its deadline.
	h.armDeadline(r)
	return r, nil
}

// commit finishes a mutation: server-driven transitions, version bump,
// persistence, broadcast, and the turn timer for whatever is now pending.
func (h *Hub) commit(r *room) {
	r.state.Advance(h.now(), h.rng)
	r.state.Version++
	if err := h.store.Save(r.state); err != nil {
		h.log.Error("save lobby", "id", r.state.ID, "err", err)
	}
	h.armDeadline(r)
	h.broadcast(r)
}

func (h *Hub) broadcast(r *room) {
	// Dropping a slow consumer changes who is connected, so go again until
	// a pass completes without drops; each drop shrinks r.conns.
	for {
		connected := make(map[string]bool, len(r.state.Players))
		for _, p := range r.state.Players {
			connected[p] = r.conns[p] != nil
		}
		dropped := false
		now := h.now()
		for player, c := range r.conns {
			view := r.state.ViewFor(player, connected, h.catalog.Load(), now)
			if !c.sender.Send(Event{Type: "lobby", Lobby: &view}) {
				h.dropSlow(r, player, c)
				dropped = true
			}
		}
		if !dropped {
			return
		}
	}
}

// deliver sends the same event to every connection in the room. A consumer
// that cannot take it is dropped like any slow one, and the others then get
// a fresh view because that changed who is connected.
func (h *Hub) deliver(r *room, ev Event) {
	dropped := false
	for player, c := range r.conns {
		if !c.sender.Send(ev) {
			h.dropSlow(r, player, c)
			dropped = true
		}
	}
	if dropped {
		h.broadcast(r)
	}
}

// dropSlow unbinds a connection whose queue is full; it will resume and
// get a fresh view.
func (h *Hub) dropSlow(r *room, player string, c *Client) {
	delete(r.conns, player)
	c.room = nil
	c.sender.Close("slow consumer")
	h.startTimer(r, player)
}

// armDeadline (re)schedules the room's turn timer for the lobby's current
// Deadline. Caller holds h.mu.
func (h *Hub) armDeadline(r *room) {
	h.cancelDeadline(r)
	deadline := r.state.Deadline
	if deadline == 0 {
		return
	}
	id, version := r.state.ID, r.state.Version
	wait := time.Duration(deadline-h.now().UnixMilli()) * time.Millisecond
	r.deadline = &deadlineTimer{
		deadline: deadline,
		version:  version,
		timer: h.after(max(wait, 0), func() {
			h.mu.Lock()
			defer h.mu.Unlock()
			// Only act if the lobby is exactly where it was when this timer
			// was armed; any mutation since has re-armed or cleared it.
			r, ok := h.rooms[id]
			if !ok || r.deadline == nil || r.deadline.deadline != deadline || r.state.Version != version {
				return
			}
			r.deadline = nil
			if !r.state.Expire(h.now(), h.rng) {
				// Fired early (clock adjustment): try again at the right time.
				h.armDeadline(r)
				return
			}
			h.log.Info("turn expired", "lobby", id, "phase", r.state.GamePhase)
			h.commit(r)
		}),
	}
}

func (h *Hub) cancelDeadline(r *room) {
	if r.deadline != nil {
		r.deadline.timer.Stop()
		r.deadline = nil
	}
}

// removePlayer applies a leave (explicit or grace expiry).
func (h *Hub) removePlayer(r *room, player string) {
	h.cancelTimer(r, player)
	if r.state.Leave(player, h.now(), h.rng) {
		h.closeRoom(r)
		return
	}
	h.commit(r)
	h.maybeEvict(r)
}

func (h *Hub) closeRoom(r *room) {
	if err := h.store.Delete(r.state.ID); err != nil {
		h.log.Error("delete lobby", "id", r.state.ID, "err", err)
	}
	for _, c := range r.conns {
		c.room = nil
		c.sender.Send(Event{Type: "lobbyClosed"})
		c.sender.Close("lobby closed")
	}
	r.conns = map[string]*Client{}
	h.cancelDeadline(r)
	for p := range r.timers {
		h.cancelTimer(r, p)
	}
	delete(h.rooms, r.state.ID)
}

// maybeEvict drops a room from memory once nothing refers to it. The state
// stays in the store until purged, so a later join or resume reloads it.
func (h *Hub) maybeEvict(r *room) {
	if len(r.conns) == 0 && len(r.timers) == 0 {
		h.cancelDeadline(r)
		delete(h.rooms, r.state.ID)
	}
}

func (h *Hub) startTimer(r *room, player string) {
	h.cancelTimer(r, player)
	r.seq++
	seq := r.seq
	id := r.state.ID
	r.timers[player] = &graceTimer{
		seq: seq,
		timer: time.AfterFunc(h.grace, func() {
			h.mu.Lock()
			defer h.mu.Unlock()
			// Only act if this exact timer is still the pending one for
			// that seat; a resume in between will have replaced or
			// cancelled it.
			r, ok := h.rooms[id]
			if !ok {
				return
			}
			if t := r.timers[player]; t == nil || t.seq != seq {
				return
			}
			h.log.Info("grace expired", "lobby", id, "player", player)
			h.removePlayer(r, player)
		}),
	}
}

func (h *Hub) cancelTimer(r *room, player string) {
	if t, ok := r.timers[player]; ok {
		t.timer.Stop()
		delete(r.timers, player)
	}
}

// Lobby codes people read off a screen and type on a phone: no O/0, I/1 or
// similar look-alikes, and short enough to say out loud.
const (
	codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	codeLength   = 5
	codeAttempts = 20
)

// generateID returns an unused lobby code. Caller holds h.mu.
func (h *Hub) generateID() (string, error) {
	b := make([]byte, codeLength)
	for range codeAttempts {
		for i := range b {
			b[i] = codeAlphabet[h.rng.IntN(len(codeAlphabet))]
		}
		id := string(b)
		r, err := h.getOrLoad(id)
		if err != nil {
			return "", err
		}
		if r == nil {
			return id, nil
		}
	}
	// 32^5 codes: reaching this means something is very wrong, not that the
	// space is full.
	h.log.Error("no free lobby code", "attempts", codeAttempts)
	return "", &game.Error{Code: "internal", Message: "Could not create a lobby."}
}

func newToken() string {
	var b [16]byte
	rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
