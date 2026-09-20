package game

import (
	"slices"
	"sort"
)

// Filter is the host's choice of word pool. It is stored on the lobby and
// sent to every player. Zero season bounds mean "no bound" and are filled
// in from the catalog by Normalized, so a lobby saved before filters
// existed keeps drawing from everything. A nil ItemTiers means every tier;
// an empty non-nil slice means none.
type Filter struct {
	UseChampions bool   `json:"useChampions"`
	UseItems     bool   `json:"useItems"`
	ChampSeasons [2]int `json:"champSeasons"` // inclusive [lo, hi]
	ItemSeasons  [2]int `json:"itemSeasons"`
	ItemTiers    []Tier `json:"itemTiers"`
}

func DefaultFilter() Filter {
	return Filter{UseChampions: true, UseItems: true}
}

// Validate rejects what a client should never send. Season bounds are only
// checked for order: values outside the catalog are clamped, not refused,
// because the catalog can change under a saved filter.
func (f Filter) Validate() error {
	if !f.UseChampions && !f.UseItems {
		return invalid("At least one of champions or items must be enabled.")
	}
	for _, r := range [][2]int{f.ChampSeasons, f.ItemSeasons} {
		if r[0] < 0 || r[1] < 0 || (r[0] != 0 && r[1] != 0 && r[0] > r[1]) {
			return invalid("Invalid season range.")
		}
	}
	for _, t := range f.ItemTiers {
		if !ValidTier(t) {
			return invalid("Unknown item tier: " + string(t))
		}
	}
	return nil
}

// Normalized fills unbounded seasons from the catalog, clamps the rest
// into it, and sorts/dedupes tiers (nil -> all). The result is what the
// view carries, so clients always see concrete values.
func (f Filter) Normalized(c *Catalog) Filter {
	out := f
	if c == nil {
		c = &Catalog{}
	}
	lo, hi := c.ChampSeasonRange()
	out.ChampSeasons = clampRange(f.ChampSeasons, lo, hi)
	lo, hi = c.ItemSeasonRange()
	out.ItemSeasons = clampRange(f.ItemSeasons, lo, hi)

	if f.ItemTiers == nil {
		out.ItemTiers = slices.Clone(AllTiers)
	} else {
		out.ItemTiers = []Tier{}
		for _, t := range f.ItemTiers {
			if ValidTier(t) && !slices.Contains(out.ItemTiers, t) {
				out.ItemTiers = append(out.ItemTiers, t)
			}
		}
		sort.Slice(out.ItemTiers, func(i, j int) bool {
			return slices.Index(AllTiers, out.ItemTiers[i]) < slices.Index(AllTiers, out.ItemTiers[j])
		})
	}
	return out
}

func clampRange(r [2]int, lo, hi int) [2]int {
	if r[0] == 0 {
		r[0] = lo
	}
	if r[1] == 0 {
		r[1] = hi
	}
	r[0] = min(max(r[0], lo), hi)
	r[1] = min(max(r[1], lo), hi)
	if r[0] > r[1] {
		r[0] = r[1]
	}
	return r
}
