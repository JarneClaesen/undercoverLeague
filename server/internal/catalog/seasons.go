package catalog

import (
	_ "embed"
	"encoding/json"
	"log/slog"
)

// champion_seasons.json maps Data Dragon champion ids to release seasons.
// Data Dragon has no release dates, so the table was generated once from
// the LoL wiki (go run ./cmd/catalogtool -seasons). Champions missing from
// it are new: they get the current season and are remembered in SQLite so
// the value stays put even after the table is regenerated late.
//
//go:embed champion_seasons.json
var championSeasonsJSON []byte

var staticSeasons = func() map[string]int {
	var m map[string]int
	if err := json.Unmarshal(championSeasonsJSON, &m); err != nil {
		panic("champion_seasons.json: " + err.Error())
	}
	return m
}()

// SeasonStore remembers first-seen champions. Implemented by store.Store.
type SeasonStore interface {
	ChampionSeasons() (map[string]int, error)
	SetChampionSeason(id string, season int) error
}

// seasonResolver answers "which season was champion id released in" in
// order: overrides, the static table, the store, else the current season
// (which it then records).
type seasonResolver struct {
	overrides ChampionOverrides
	store     SeasonStore
	learned   map[string]int
	current   int
	log       *slog.Logger
}

func newSeasonResolver(ov ChampionOverrides, st SeasonStore, current int, log *slog.Logger) *seasonResolver {
	if log == nil {
		log = slog.Default()
	}
	r := &seasonResolver{overrides: ov, store: st, learned: map[string]int{}, current: current, log: log}
	if st != nil {
		if m, err := st.ChampionSeasons(); err == nil {
			r.learned = m
		} else {
			log.Warn("catalog: reading learned champion seasons", "err", err)
		}
	}
	return r
}

func (r *seasonResolver) season(id string) int {
	if s, ok := r.overrides.season(id); ok {
		return s
	}
	if s, ok := staticSeasons[id]; ok {
		return s
	}
	if s, ok := r.learned[id]; ok {
		return s
	}
	r.learned[id] = r.current
	if r.store != nil {
		if err := r.store.SetChampionSeason(id, r.current); err != nil {
			r.log.Warn("catalog: recording champion season", "id", id, "err", err)
		}
	}
	r.log.Info("catalog: new champion", "id", id, "season", r.current)
	return r.current
}
