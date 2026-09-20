// Package store persists lobbies in SQLite, one JSON blob per lobby. The
// hub holds the authoritative copy in memory; this exists so a restart or
// redeploy does not kill games in progress.
package store

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

type Store struct {
	db *sql.DB
}

func Open(path string) (*Store, error) {
	dsn := fmt.Sprintf("file:%s?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)", path)
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// One connection: the hub serialises writes per lobby anyway, and a
	// single writer never sees SQLITE_BUSY.
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS lobbies (
		id TEXT PRIMARY KEY,
		state TEXT NOT NULL,
		updated_at INTEGER NOT NULL
	)`); err != nil {
		db.Close()
		return nil, err
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) Ping() error {
	var one int
	return s.db.QueryRow(`SELECT 1`).Scan(&one)
}

func (s *Store) Save(l *game.Lobby) error {
	state, err := json.Marshal(l)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`INSERT INTO lobbies (id, state, updated_at) VALUES (?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET state = excluded.state, updated_at = excluded.updated_at`,
		l.ID, string(state), time.Now().UnixMilli())
	return err
}

// Load returns (nil, nil) when the lobby does not exist.
func (s *Store) Load(id string) (*game.Lobby, error) {
	var state string
	err := s.db.QueryRow(`SELECT state FROM lobbies WHERE id = ?`, id).Scan(&state)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var l game.Lobby
	if err := json.Unmarshal([]byte(state), &l); err != nil {
		return nil, fmt.Errorf("lobby %s: %w", id, err)
	}
	l.Normalize()
	return &l, nil
}

func (s *Store) Delete(id string) error {
	_, err := s.db.Exec(`DELETE FROM lobbies WHERE id = ?`, id)
	return err
}

// Purge deletes lobbies not updated since olderThan, except the given ids
// (the ones currently live in memory).
func (s *Store) Purge(olderThan time.Time, keep []string) (int64, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	rows, err := tx.Query(`SELECT id FROM lobbies WHERE updated_at < ?`, olderThan.UnixMilli())
	if err != nil {
		return 0, err
	}
	var stale []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		stale = append(stale, id)
	}
	rows.Close()

	keepSet := map[string]bool{}
	for _, id := range keep {
		keepSet[id] = true
	}
	var n int64
	for _, id := range stale {
		if keepSet[id] {
			continue
		}
		if _, err := tx.Exec(`DELETE FROM lobbies WHERE id = ?`, id); err != nil {
			return n, err
		}
		n++
	}
	return n, tx.Commit()
}
