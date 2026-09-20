package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

func TestRoundTrip(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	l := game.New("abc", "Host", time.Now())
	l.Join("B")
	l.Sessions["tok"] = "B"
	if err := s.Save(l); err != nil {
		t.Fatal(err)
	}
	got, err := s.Load("abc")
	if err != nil || got == nil {
		t.Fatalf("load: %v %v", got, err)
	}
	if got.Host != "Host" || len(got.Players) != 2 || got.Sessions["tok"] != "B" || got.LastEliminated != nil {
		t.Errorf("mismatch: %+v", got)
	}

	nobody := ""
	l.LastEliminated = &nobody
	l.Version = 7
	if err := s.Save(l); err != nil {
		t.Fatal(err)
	}
	got, _ = s.Load("abc")
	if got.LastEliminated == nil || *got.LastEliminated != "" || got.Version != 7 {
		t.Errorf("upsert lost fields: %+v", got)
	}

	if missing, err := s.Load("nope"); err != nil || missing != nil {
		t.Errorf("missing lobby: %v %v", missing, err)
	}
	if err := s.Delete("abc"); err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Load("abc"); got != nil {
		t.Error("delete did not remove the lobby")
	}
}

func TestPurge(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	for _, id := range []string{"old", "kept", "fresh"} {
		if err := s.Save(game.New(id, "H", time.Now())); err != nil {
			t.Fatal(err)
		}
	}
	// Age two of them by hand.
	if _, err := s.db.Exec(`UPDATE lobbies SET updated_at = 0 WHERE id IN ('old', 'kept')`); err != nil {
		t.Fatal(err)
	}
	n, err := s.Purge(time.Now().Add(-time.Hour), []string{"kept"})
	if err != nil || n != 1 {
		t.Fatalf("purged %d, err %v", n, err)
	}
	for id, want := range map[string]bool{"old": false, "kept": true, "fresh": true} {
		got, _ := s.Load(id)
		if (got != nil) != want {
			t.Errorf("%s present=%v, want %v", id, got != nil, want)
		}
	}
}

func TestBlobsAndSeasons(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "s.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	if b, _, err := s.LoadBlob("missing"); err != nil || b != nil {
		t.Fatalf("missing blob: %v %v", b, err)
	}
	if err := s.SaveBlob("k", []byte(`{"a":1}`)); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveBlob("k", []byte(`{"a":2}`)); err != nil {
		t.Fatal(err)
	}
	b, at, err := s.LoadBlob("k")
	if err != nil || string(b) != `{"a":2}` || at.IsZero() {
		t.Fatalf("blob round trip: %s %v %v", b, at, err)
	}

	if m, err := s.ChampionSeasons(); err != nil || len(m) != 0 {
		t.Fatalf("seasons: %v %v", m, err)
	}
	s.SetChampionSeason("Mel", 15)
	s.SetChampionSeason("Mel", 15)
	s.SetChampionSeason("Yunara", 16)
	m, err := s.ChampionSeasons()
	if err != nil || len(m) != 2 || m["Mel"] != 15 || m["Yunara"] != 16 {
		t.Fatalf("seasons: %v %v", m, err)
	}
}
