package catalog

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strings"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// Overrides is the hand-curated correction layer on top of the automatic
// import, read from a JSON file (server/deploy/catalog_overrides.json in
// the repo, mounted into the container). Item names match display names
// case-insensitively; champion seasons, regions and lanes are keyed by
// Data Dragon id ("MonkeyKing"), champion exclusions by display name
// ("Wukong"). Excluding a champion also drops its abilities. A lanes entry
// replaces what the play-rate feed says for that champion ([] = no lane).
//
//	{
//	  "items": {
//	    "exclude": ["Cappa Juice"],
//	    "excludeSeasons": {"Sword of the Divine": [16]},
//	    "include": [{"name": "Muramana", "icon": "https://…/3042.png", "tier": "legendary", "seasons": [3, 16]}],
//	    "tiers": {"Long Sword": "component"}
//	  },
//	  "champions": {"exclude": [], "seasons": {"Ambessa": 14}, "regions": {"Zaahen": "Shurima"}, "lanes": {"Teemo": ["top"]}},
//	  "skinLines": {"exclude": ["Count"]}
//	}
type Overrides struct {
	Items     ItemOverrides     `json:"items"`
	Champions ChampionOverrides `json:"champions"`
	SkinLines SkinLineOverrides `json:"skinLines"`
}

type ItemOverrides struct {
	Exclude        []string             `json:"exclude"`
	ExcludeSeasons map[string][]int     `json:"excludeSeasons"`
	Include        []IncludedItem       `json:"include"`
	Tiers          map[string]game.Tier `json:"tiers"`
}

// IncludedItem is added (or replaces the imported entry of the same name).
// Seasons is an inclusive [from, to] range.
type IncludedItem struct {
	Name    string    `json:"name"`
	Icon    string    `json:"icon"`
	Tier    game.Tier `json:"tier"`
	Seasons [2]int    `json:"seasons"`
}

type ChampionOverrides struct {
	Exclude []string            `json:"exclude"`
	Seasons map[string]int      `json:"seasons"`
	Regions map[string]string   `json:"regions"` // id -> one of game.AllRegions
	Lanes   map[string][]string `json:"lanes"`   // id -> subset of game.AllLanes
}

// SkinLineOverrides drops lines the name heuristic got wrong ("Count",
// "King"), matched case-insensitively.
type SkinLineOverrides struct {
	Exclude []string `json:"exclude"`
}

// LoadOverrides reads the file; a missing file means no overrides.
func LoadOverrides(path string) (Overrides, error) {
	var ov Overrides
	if path == "" {
		return ov, nil
	}
	b, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return ov, nil
	}
	if err != nil {
		return ov, err
	}
	if err := json.Unmarshal(b, &ov); err != nil {
		return Overrides{}, fmt.Errorf("%s: %w", path, err)
	}
	for _, inc := range ov.Items.Include {
		if _, ok := inc.item(); !ok {
			return Overrides{}, fmt.Errorf("%s: include entry %q needs name, icon, a valid tier and seasons [from, to]", path, inc.Name)
		}
	}
	for name, t := range ov.Items.Tiers {
		if !game.ValidTier(t) {
			return Overrides{}, fmt.Errorf("%s: unknown tier %q for %q", path, t, name)
		}
	}
	for id, r := range ov.Champions.Regions {
		if !game.ValidRegion(r) {
			return Overrides{}, fmt.Errorf("%s: unknown region %q for %q", path, r, id)
		}
	}
	for id, lanes := range ov.Champions.Lanes {
		for _, l := range lanes {
			if !game.ValidLane(l) {
				return Overrides{}, fmt.Errorf("%s: unknown lane %q for %q", path, l, id)
			}
		}
	}
	return ov, nil
}

func containsFold(list []string, name string) bool {
	for _, x := range list {
		if strings.EqualFold(strings.TrimSpace(x), name) {
			return true
		}
	}
	return false
}

func lookupFold[V any](m map[string]V, name string) (V, bool) {
	for k, v := range m {
		if strings.EqualFold(strings.TrimSpace(k), name) {
			return v, true
		}
	}
	var zero V
	return zero, false
}

func (o ItemOverrides) excluded(name string) bool { return containsFold(o.Exclude, name) }

func (o ItemOverrides) excludedSeasons(name string) []int {
	s, _ := lookupFold(o.ExcludeSeasons, name)
	return s
}

func (o ItemOverrides) tier(name string) (game.Tier, bool) { return lookupFold(o.Tiers, name) }

func (o ChampionOverrides) excluded(name string) bool { return containsFold(o.Exclude, name) }

func (o ChampionOverrides) season(id string) (int, bool) { return lookupFold(o.Seasons, id) }

// lanes is the override for a champion id, in canonical spelling and
// game.AllLanes order; ok is false when the file has no entry for it.
func (o ChampionOverrides) lanes(id string) (lanes []string, ok bool) {
	list, ok := lookupFold(o.Lanes, id)
	if !ok {
		return nil, false
	}
	lanes = []string{}
	for _, l := range game.AllLanes {
		if containsFold(list, l) {
			lanes = append(lanes, l)
		}
	}
	return lanes, true
}

func (o SkinLineOverrides) excluded(name string) bool { return containsFold(o.Exclude, name) }

func (inc IncludedItem) item() (game.Item, bool) {
	name := strings.TrimSpace(inc.Name)
	if name == "" || inc.Icon == "" || !game.ValidTier(inc.Tier) || inc.Seasons[0] <= 0 || inc.Seasons[1] < inc.Seasons[0] {
		return game.Item{}, false
	}
	it := game.Item{Name: name, Icon: inc.Icon, Tier: inc.Tier}
	for s := inc.Seasons[0]; s <= inc.Seasons[1]; s++ {
		it.Seasons.Add(s)
	}
	return it, true
}
