package game

import (
	"encoding/json"
	"slices"
	"sort"
	"strings"
)

// Filter is the host's choice of word pool. It is stored on the lobby and
// sent to every player. Zero season bounds mean "no bound" and are filled
// in from the catalog by Normalized, so a lobby saved before filters
// existed keeps drawing from everything. A nil ItemTiers means every tier;
// an empty non-nil slice means none. Classes and regions are the opposite:
// nil or empty means every class/region. Seasons apply to champions and
// items; seasons, classes and regions also reach the abilities pack
// through the champion each ability belongs to.
type Filter struct {
	Packs        []Pack   `json:"packs"`        // enabled packs; nil on old rows (see UnmarshalJSON)
	ChampSeasons [2]int   `json:"champSeasons"` // inclusive [lo, hi]
	ItemSeasons  [2]int   `json:"itemSeasons"`
	ItemTiers    []Tier   `json:"itemTiers"`
	ChampClasses []string `json:"champClasses"` // Data Dragon tags, see AllClasses
	ChampRegions []string `json:"champRegions"` // see AllRegions
}

func DefaultFilter() Filter {
	return Filter{Packs: []Pack{PackChampions, PackItems}}
}

// UnmarshalJSON reads the current shape and, when "packs" is absent, the
// legacy "useChampions"/"useItems" booleans that rows saved and clients
// built before packs existed still send. A row from before filters existed
// has neither and leaves Packs nil, which Lobby.Normalize turns into the
// default.
//
// Embedding Filter in another struct promotes this method, so that struct
// needs its own UnmarshalJSON (decode the Filter separately, then the rest).
func (f *Filter) UnmarshalJSON(b []byte) error {
	type plain Filter
	var aux struct {
		plain
		UseChampions *bool `json:"useChampions"`
		UseItems     *bool `json:"useItems"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if aux.Packs == nil && (aux.UseChampions != nil || aux.UseItems != nil) {
		aux.Packs = []Pack{}
		if aux.UseChampions != nil && *aux.UseChampions {
			aux.Packs = append(aux.Packs, PackChampions)
		}
		if aux.UseItems != nil && *aux.UseItems {
			aux.Packs = append(aux.Packs, PackItems)
		}
	}
	*f = Filter(aux.plain)
	return nil
}

// Validate rejects what a client should never send. Season bounds are only
// checked for order: values outside the catalog are clamped, not refused,
// because the catalog can change under a saved filter.
func (f Filter) Validate() error {
	if len(f.Packs) == 0 {
		return invalid("Enable at least one word pack.")
	}
	for _, p := range f.Packs {
		if !ValidPack(p) {
			return invalid("Unknown word pack: " + string(p))
		}
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
	for _, cl := range f.ChampClasses {
		if !containsFold(AllClasses, cl) {
			return invalid("Unknown champion class: " + cl)
		}
	}
	for _, r := range f.ChampRegions {
		if !containsFold(AllRegions, r) {
			return invalid("Unknown region: " + r)
		}
	}
	return nil
}

// Normalized fills unbounded seasons from the catalog, clamps the rest
// into it, sorts/dedupes packs and tiers (nil tiers -> all, nil packs ->
// the default) and canonicalizes classes and regions (never nil). The
// result is what the view carries, so clients always see concrete values.
func (f Filter) Normalized(c *Catalog) Filter {
	out := f
	if c == nil {
		c = &Catalog{}
	}
	if f.Packs == nil {
		out.Packs = DefaultFilter().Packs
	} else {
		out.Packs = canonical(f.Packs, AllPacks)
	}
	lo, hi := c.ChampSeasonRange()
	out.ChampSeasons = clampRange(f.ChampSeasons, lo, hi)
	lo, hi = c.ItemSeasonRange()
	out.ItemSeasons = clampRange(f.ItemSeasons, lo, hi)

	if f.ItemTiers == nil {
		out.ItemTiers = slices.Clone(AllTiers)
	} else {
		out.ItemTiers = canonical(f.ItemTiers, AllTiers)
	}
	out.ChampClasses = canonicalFold(f.ChampClasses, AllClasses)
	out.ChampRegions = canonicalFold(f.ChampRegions, AllRegions)
	return out
}

// canonical keeps the known values of list, deduped and in the order of
// all. Never nil.
func canonical[T comparable](list, all []T) []T {
	out := []T{}
	for _, x := range list {
		if slices.Contains(all, x) && !slices.Contains(out, x) {
			out = append(out, x)
		}
	}
	sort.Slice(out, func(i, j int) bool { return slices.Index(all, out[i]) < slices.Index(all, out[j]) })
	return out
}

// canonicalFold is canonical for strings matched case-insensitively; the
// spelling from all wins.
func canonicalFold(list, all []string) []string {
	out := []string{}
	for _, x := range list {
		i := slices.IndexFunc(all, func(a string) bool { return strings.EqualFold(a, x) })
		if i >= 0 && !slices.Contains(out, all[i]) {
			out = append(out, all[i])
		}
	}
	sort.Slice(out, func(i, j int) bool { return slices.Index(all, out[i]) < slices.Index(all, out[j]) })
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
