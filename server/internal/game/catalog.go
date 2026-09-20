package game

import "sort"

// Tier is the coarse shop category of an item, used for the host's filter
// chips. Derived by the importer from Data Dragon tags and recipes.
type Tier string

const (
	TierStarter    Tier = "starter"
	TierConsumable Tier = "consumable" // consumables and trinkets
	TierBoots      Tier = "boots"
	TierComponent  Tier = "component" // anything that builds into something
	TierLegendary  Tier = "legendary" // completed items
)

var AllTiers = []Tier{TierStarter, TierConsumable, TierBoots, TierComponent, TierLegendary}

func ValidTier(t Tier) bool {
	for _, x := range AllTiers {
		if x == t {
			return true
		}
	}
	return false
}

// SeasonSet is a bitmask of seasons (bit s = season s). Seasons are numbered
// by year: S1 = 2011 ... S16 = 2026, which is also the Data Dragon major
// version from S3 on.
type SeasonSet uint32

func (s SeasonSet) Has(season int) bool { return season >= 0 && season < 32 && s&(1<<season) != 0 }

func (s *SeasonSet) Add(season int) {
	if season >= 0 && season < 32 {
		*s |= 1 << season
	}
}

// Seasons lists the set in ascending order.
func (s SeasonSet) Seasons() []int {
	var out []int
	for i := 0; i < 32; i++ {
		if s.Has(i) {
			out = append(out, i)
		}
	}
	return out
}

// Overlaps reports whether any season in [lo, hi] is in the set.
func (s SeasonSet) Overlaps(lo, hi int) bool {
	for i := lo; i <= hi; i++ {
		if s.Has(i) {
			return true
		}
	}
	return false
}

type Champion struct {
	Name   string `json:"name"`
	Icon   string `json:"icon"` // https URL of the loading-screen art
	Season int    `json:"season"`
}

type Item struct {
	Name    string    `json:"name"`
	Icon    string    `json:"icon"`
	Seasons SeasonSet `json:"seasons"` // every season the item was in the SR shop
	Tier    Tier      `json:"tier"`
}

// Word is what a game draws: the name shown to civilians and its picture.
type Word struct {
	Name string `json:"name"`
	Icon string `json:"icon"`
}

// Catalog is the full word pool. It is built by the catalog package,
// published to the hub as an immutable value and never mutated afterwards.
type Catalog struct {
	Patch     string     `json:"patch"`
	Champions []Champion `json:"champions"`
	Items     []Item     `json:"items"`
}

// ChampSeasonRange is the span of champion release seasons, (0, 0) when empty.
func (c *Catalog) ChampSeasonRange() (lo, hi int) {
	for i, ch := range c.Champions {
		if i == 0 || ch.Season < lo {
			lo = ch.Season
		}
		if ch.Season > hi {
			hi = ch.Season
		}
	}
	return lo, hi
}

// ItemSeasonRange is the span of seasons any item exists in, (0, 0) when
// empty. Data Dragon only starts in Season 3, so lo is normally 3.
func (c *Catalog) ItemSeasonRange() (lo, hi int) {
	var all SeasonSet
	for _, it := range c.Items {
		all |= it.Seasons
	}
	seasons := all.Seasons()
	if len(seasons) == 0 {
		return 0, 0
	}
	return seasons[0], seasons[len(seasons)-1]
}

// FilterChampions returns the champions matching f (ignoring UseChampions).
func (c *Catalog) FilterChampions(f Filter) []Champion {
	var out []Champion
	for _, ch := range c.Champions {
		if ch.Season >= f.ChampSeasons[0] && ch.Season <= f.ChampSeasons[1] {
			out = append(out, ch)
		}
	}
	return out
}

// FilterItems returns the items matching f (ignoring UseItems).
func (c *Catalog) FilterItems(f Filter) []Item {
	tiers := map[Tier]bool{}
	for _, t := range f.ItemTiers {
		tiers[t] = true
	}
	var out []Item
	for _, it := range c.Items {
		if it.Seasons.Overlaps(f.ItemSeasons[0], f.ItemSeasons[1]) && tiers[it.Tier] {
			out = append(out, it)
		}
	}
	return out
}

// PoolSize counts what a game with these settings could draw from; a
// disabled category counts as 0. f should already be Normalized.
func (c *Catalog) PoolSize(f Filter) PoolSize {
	var p PoolSize
	if f.UseChampions {
		p.Champions = len(c.FilterChampions(f))
	}
	if f.UseItems {
		p.Items = len(c.FilterItems(f))
	}
	return p
}

type PoolSize struct {
	Champions int `json:"champions"`
	Items     int `json:"items"`
}

// SeasonRange tells the client which seasons the sliders may span.
type SeasonRange struct {
	Champions [2]int `json:"champions"`
	Items     [2]int `json:"items"`
}

func (c *Catalog) SeasonRange() SeasonRange {
	var r SeasonRange
	r.Champions[0], r.Champions[1] = c.ChampSeasonRange()
	r.Items[0], r.Items[1] = c.ItemSeasonRange()
	return r
}

// Sort orders both lists by name so output is stable regardless of the
// order the importer produced them in.
func (c *Catalog) Sort() {
	sort.Slice(c.Champions, func(i, j int) bool { return c.Champions[i].Name < c.Champions[j].Name })
	sort.Slice(c.Items, func(i, j int) bool { return c.Items[i].Name < c.Items[j].Name })
}
