package catalog

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"log/slog"
	"sort"
	"sync"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// fallback.json is a complete catalog baked into the binary so a fresh
// deployment can start games before (or without) reaching Data Dragon.
// Regenerate it now and then with: go run ./cmd/catalogtool -dump.
//
//go:embed fallback.json
var fallbackJSON []byte

const currentKey = "catalog:current"

func itemsKey(version string) string { return "items:" + version }

// BlobStore caches fetched data across restarts. Implemented by store.Store.
type BlobStore interface {
	SaveBlob(key string, b []byte) error
	LoadBlob(key string) ([]byte, time.Time, error)
}

type Store interface {
	BlobStore
	SeasonStore
}

// Service owns the current catalog. Bootstrap gives the hub something
// immediately (SQLite cache, else the embedded fallback); Run then keeps it
// fresh from Data Dragon in the background.
type Service struct {
	fetch         *Fetcher
	store         Store // nil in catalogtool
	overridesPath string
	log           *slog.Logger

	mu        sync.Mutex
	current   *game.Catalog
	source    string // embedded | cache | ddragon
	updatedAt time.Time
}

type Status struct {
	Source    string    `json:"source"`
	Patch     string    `json:"patch"`
	UpdatedAt time.Time `json:"updatedAt"`
}

func New(fetch *Fetcher, st Store, overridesPath string, log *slog.Logger) *Service {
	if log == nil {
		log = slog.Default()
	}
	return &Service{fetch: fetch, store: st, overridesPath: overridesPath, log: log}
}

// Bootstrap loads the last catalog this server built, else the embedded
// one. It never touches the network so startup cannot hang on Riot.
func (s *Service) Bootstrap() *game.Catalog {
	if s.store != nil {
		if b, at, err := s.store.LoadBlob(currentKey); err != nil {
			s.log.Warn("catalog: reading cache", "err", err)
		} else if b != nil {
			var c game.Catalog
			if err := json.Unmarshal(b, &c); err == nil && len(c.Champions) > 0 {
				s.set(&c, "cache", at)
				return &c
			}
			s.log.Warn("catalog: cached catalog unreadable, using embedded", "err", err)
		}
	}
	var c game.Catalog
	if err := json.Unmarshal(fallbackJSON, &c); err != nil {
		panic("fallback.json: " + err.Error())
	}
	s.set(&c, "embedded", time.Time{})
	return &c
}

// Refresh rebuilds the catalog from Data Dragon. Past seasons' snapshots
// come from the cache when present (a finished patch never changes); the
// current season and the champion list are always fetched. On error the
// previous catalog stays current.
func (s *Service) Refresh(ctx context.Context) (*game.Catalog, error) {
	versions, err := s.fetch.Versions(ctx)
	if err != nil {
		return nil, fmt.Errorf("versions: %w", err)
	}
	bySeason, current := SeasonVersions(versions)
	if current == 0 {
		return nil, fmt.Errorf("versions: no x.y.z patch in %d entries", len(versions))
	}
	latest := bySeason[current]

	ov, err := LoadOverrides(s.overridesPath)
	if err != nil {
		return nil, fmt.Errorf("overrides: %w", err)
	}

	seasons := make([]int, 0, len(bySeason))
	for season := range bySeason {
		seasons = append(seasons, season)
	}
	sort.Ints(seasons)
	snaps := map[int][]snapItem{}
	for _, season := range seasons {
		version := bySeason[season]
		if season < current {
			if snap, ok := s.cachedSnapshot(version); ok {
				snaps[season] = snap
				continue
			}
		}
		raw, err := s.fetch.Items(ctx, version)
		if err != nil {
			return nil, fmt.Errorf("items %s: %w", version, err)
		}
		snap := importItems(s.fetch.Base, version, raw)
		if len(snap) == 0 {
			return nil, fmt.Errorf("items %s: nothing imported", version)
		}
		snaps[season] = snap
		s.saveJSON(itemsKey(version), snap)
	}

	rawChamps, err := s.fetch.Champions(ctx, latest)
	if err != nil {
		return nil, fmt.Errorf("champions %s: %w", latest, err)
	}
	var seasonStore SeasonStore
	if s.store != nil {
		seasonStore = s.store
	}
	resolver := newSeasonResolver(ov.Champions, seasonStore, current, s.log)
	champs := importChampions(s.fetch.Base, rawChamps, resolver.season)
	if len(champs) == 0 {
		return nil, fmt.Errorf("champions %s: nothing imported", latest)
	}

	c := Build(latest, snaps, champs, ov)
	s.saveJSON(currentKey, c)
	s.set(c, "ddragon", time.Now())
	s.log.Info("catalog: refreshed", "patch", latest, "champions", len(c.Champions), "items", len(c.Items), "seasons", seasons)
	return c, nil
}

// Run refreshes immediately and then every interval until ctx ends, handing
// each new catalog to publish. every <= 0 disables fetching entirely.
func (s *Service) Run(ctx context.Context, every time.Duration, publish func(*game.Catalog)) {
	if every <= 0 {
		return
	}
	refresh := func() {
		c, err := s.Refresh(ctx)
		if err != nil {
			if ctx.Err() == nil {
				s.log.Warn("catalog: refresh failed, keeping current", "err", err, "source", s.Status().Source)
			}
			return
		}
		publish(c)
	}
	refresh()
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			refresh()
		}
	}
}

func (s *Service) Current() *game.Catalog {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.current
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := Status{Source: s.source, UpdatedAt: s.updatedAt}
	if s.current != nil {
		st.Patch = s.current.Patch
	}
	return st
}

func (s *Service) set(c *game.Catalog, source string, at time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.current, s.source, s.updatedAt = c, source, at
}

func (s *Service) cachedSnapshot(version string) ([]snapItem, bool) {
	if s.store == nil {
		return nil, false
	}
	b, _, err := s.store.LoadBlob(itemsKey(version))
	if err != nil || b == nil {
		return nil, false
	}
	var snap []snapItem
	if err := json.Unmarshal(b, &snap); err != nil || len(snap) == 0 {
		return nil, false
	}
	return snap, true
}

func (s *Service) saveJSON(key string, v any) {
	if s.store == nil {
		return
	}
	b, err := json.Marshal(v)
	if err == nil {
		err = s.store.SaveBlob(key, b)
	}
	if err != nil {
		s.log.Warn("catalog: caching", "key", key, "err", err)
	}
}
