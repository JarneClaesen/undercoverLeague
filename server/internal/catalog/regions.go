package catalog

import (
	_ "embed"
	"encoding/json"
	"fmt"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// champion_regions.json maps Data Dragon champion ids to the region Riot's
// Universe files them under. Data Dragon has no region data, so the table
// is written by hand; a champion missing from it has no region ("") until
// the table or the overrides file (champions.regions) names one.
//
//go:embed champion_regions.json
var championRegionsJSON []byte

var staticRegions = func() map[string]string {
	var m map[string]string
	if err := json.Unmarshal(championRegionsJSON, &m); err != nil {
		panic("champion_regions.json: " + err.Error())
	}
	for id, r := range m {
		if !game.ValidRegion(r) {
			panic(fmt.Sprintf("champion_regions.json: %s has unknown region %q", id, r))
		}
	}
	return m
}()

// region resolves a champion id to its region: overrides first, then the
// static table, else "".
func (o ChampionOverrides) region(id string) string {
	if r, ok := lookupFold(o.Regions, id); ok {
		return r
	}
	return staticRegions[id]
}
