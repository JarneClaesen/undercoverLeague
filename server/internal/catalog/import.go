package catalog

import (
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// snapItem is one Summoner's Rift shop item as it was in one patch. A
// snapshot per season is cached in SQLite under "items:<version>".
type snapItem struct {
	Name string    `json:"name"`
	Icon string    `json:"icon"`
	Tier game.Tier `json:"tier"`
}

// importItems keeps the items a player could buy in the Summoner's Rift
// shop of that patch. Data Dragon's flags are noisy (Arena and Swarm
// items carry maps["11"]=true, for instance), so several signals are
// combined; whatever slips through is handled by the overrides file.
func importItems(base, version string, raw map[string]rawItem) []snapItem {
	type cand struct {
		id int
		snapItem
	}
	byName := map[string]cand{}
	for idStr, it := range raw {
		id, err := strconv.Atoi(idStr)
		if err != nil {
			continue
		}
		name := strings.TrimSpace(it.Name)
		switch {
		case name == "":
			continue
		// Game-mode variants of items get six-digit ids (22xxxx Arena,
		// 77xxxx Swarm, ...); the real shop never goes past four digits.
		case id >= 10000:
			continue
		case !onSummonersRift(it.Maps):
			continue
		case !it.Gold.Purchasable:
			continue
		case it.InStore != nil && !*it.InStore:
			continue
		case it.HideFromAll:
			continue
		case it.RequiredChampion != "" || it.RequiredAlly != "":
			continue
		}
		c := cand{id: id, snapItem: snapItem{Name: name, Icon: ItemIcon(base, version, idStr), Tier: classifyTier(it)}}
		key := strings.ToLower(name)
		// Riot occasionally lists the same item twice; keep the lowest id,
		// which is the original.
		if prev, dup := byName[key]; !dup || c.id < prev.id {
			byName[key] = c
		}
	}
	out := make([]snapItem, 0, len(byName))
	for _, c := range byName {
		out = append(out, c.snapItem)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// onSummonersRift reads the per-map flags across Data Dragon's eras: "11"
// from patch 4 on, "1" in patch 3, and no key at all for 3.x SR items.
func onSummonersRift(maps map[string]bool) bool {
	if v, ok := maps["11"]; ok {
		return v
	}
	if v, ok := maps["1"]; ok {
		return v
	}
	return true
}

// classifyTier buckets an item for the host's filter chips. The order
// matters: boots and consumables are recognisable by tag, starters by
// having no recipe and (nearly) nothing to build into, components by
// building into something, and what is left is a completed item.
func classifyTier(it rawItem) game.Tier {
	has := func(tag string) bool { return slices.Contains(it.Tags, tag) }
	switch {
	case has("Trinket") || has("Consumable"):
		return game.TierConsumable
	case has("Boots"):
		return game.TierBoots
	case len(it.From) == 0 && len(it.Into) <= 1 &&
		(has("Lane") || has("Jungle") || (len(it.Into) == 0 && it.Gold.Total <= 500)):
		// Doran's items, Cull, jungle pets, Dark Seal; 3.x has no Lane tag
		// but its starters are cheap and build into nothing.
		return game.TierStarter
	case len(it.Into) > 0 && it.Gold.Total < 1600:
		return game.TierComponent
	default:
		return game.TierLegendary
	}
}

// importChampions turns champion.json into catalog entries. season resolves
// a Data Dragon id to its release season.
func importChampions(base string, raw map[string]rawChampion, season func(id string) int) []game.Champion {
	out := make([]game.Champion, 0, len(raw))
	for _, ch := range raw {
		name := strings.TrimSpace(ch.Name)
		if ch.ID == "" || name == "" {
			continue
		}
		out = append(out, game.Champion{Name: name, Icon: ChampionArt(base, ch.ID), Season: season(ch.ID)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// Build merges the per-season item snapshots and the champion list into a
// catalog and applies the overrides. Items are identified by name
// (case-insensitively) across seasons: an id can be reused and a name can
// change id, but a name is what players guess. Name, icon and tier come
// from the newest season the item appears in.
func Build(patch string, snaps map[int][]snapItem, champs []game.Champion, ov Overrides) *game.Catalog {
	type acc struct {
		item   game.Item
		newest int
	}
	byName := map[string]*acc{}
	seasons := make([]int, 0, len(snaps))
	for s := range snaps {
		seasons = append(seasons, s)
	}
	sort.Ints(seasons)
	for _, season := range seasons {
		for _, it := range snaps[season] {
			key := strings.ToLower(it.Name)
			a, ok := byName[key]
			if !ok {
				a = &acc{}
				byName[key] = a
			}
			a.item.Seasons.Add(season)
			if season >= a.newest {
				a.newest = season
				a.item.Name, a.item.Icon, a.item.Tier = it.Name, it.Icon, it.Tier
			}
		}
	}

	c := &game.Catalog{Patch: patch, Champions: []game.Champion{}, Items: []game.Item{}}
	for _, ch := range champs {
		if !ov.Champions.excluded(ch.Name) {
			c.Champions = append(c.Champions, ch)
		}
	}
	for _, a := range byName {
		it := a.item
		if ov.Items.excluded(it.Name) {
			continue
		}
		for _, s := range ov.Items.excludedSeasons(it.Name) {
			it.Seasons &^= 1 << s
		}
		if it.Seasons == 0 {
			continue
		}
		if t, ok := ov.Items.tier(it.Name); ok {
			it.Tier = t
		}
		c.Items = append(c.Items, it)
	}
	for _, inc := range ov.Items.Include {
		it, ok := inc.item()
		if !ok {
			continue
		}
		c.Items = slices.DeleteFunc(c.Items, func(x game.Item) bool { return strings.EqualFold(x.Name, it.Name) })
		c.Items = append(c.Items, it)
	}
	c.Sort()
	return c
}
