package catalog

import (
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// snapItem is one Summoner's Rift shop item as it was in one patch. A
// snapshot per season is cached in SQLite under itemsKey(version). From
// and Into are names within the same patch.
type snapItem struct {
	Name string    `json:"name"`
	Icon string    `json:"icon"`
	Tier game.Tier `json:"tier"`
	From []string  `json:"from,omitempty"`
	Into []string  `json:"into,omitempty"`
	Gold int       `json:"gold,omitempty"`
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
	// Recipes reference ids; the names are what the catalog keeps. An
	// edge to something outside the shop (Seraph's Embrace is not
	// purchasable) is harmless: it just never matches a catalog item.
	names := func(ids []string) []string {
		var out []string
		for _, id := range ids {
			if n := strings.TrimSpace(raw[id].Name); n != "" && !containsFold(out, n) {
				out = append(out, n)
			}
		}
		sort.Strings(out)
		return out
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
		c := cand{id: id, snapItem: snapItem{
			Name: name, Icon: ItemIcon(base, version, idStr), Tier: classifyTier(it),
			From: names(it.From), Into: names(it.Into), Gold: it.Gold.Total,
		}}
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

// importChampions turns championFull.json into catalog entries. season
// and region resolve a Data Dragon id.
func importChampions(base string, raw map[string]rawChampionFull, season func(id string) int, region func(id string) string) []game.Champion {
	out := make([]game.Champion, 0, len(raw))
	for _, ch := range raw {
		name := strings.TrimSpace(ch.Name)
		if ch.ID == "" || name == "" {
			continue
		}
		c := game.Champion{
			Name: name, Icon: ChampionArt(base, ch.ID), Season: season(ch.ID),
			Tags: slices.Clone(ch.Tags), Region: region(ch.ID), ID: ch.ID,
		}
		c.Range, c.Resource, c.Damage, c.Difficulty = classifyChampion(ch)
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// rangedFrom is the base attack range from which a champion counts as
// ranged. Melee champions sit at 125-225; the shortest ranged one (Rakan)
// has 300. Lillia (325) is the one champion this misfiles, since Riot's
// own melee/ranged flag is not in Data Dragon.
const rangedFrom = 300

// damageLean is how far info.attack must exceed info.magic (or the
// reverse) for a champion to count as physical (magic) rather than mixed.
// Riven (8/1) and Zed (9/1) are physical, Ahri (3/8) and Lux (2/9) magic,
// Jax (7/7), Kayle (6/7) and Corki (8/6) mixed; 3 splits the roster into
// roughly 70 physical, 60 magic and 40 mixed.
const damageLean = 3

// classifyChampion buckets a champion by attack range, resource bar and
// Riot's 0-10 attack/magic/difficulty ratings:
//
//	range:      attackrange >= rangedFrom -> ranged, else melee
//	resource:   Mana -> mana, Energy -> energy, None or "" -> none,
//	            anything else (Fury, Rage, Heat, Grit, Flow, ...) -> other
//	damage:     attack - magic >= damageLean -> physical,
//	            <= -damageLean -> magic, else mixed
//	difficulty: 1-3 easy, 4-6 medium, 7-10 hard
//
// Damage and difficulty are "" when the ratings are all zero (Akshan,
// Rell, Seraphine and Vex ship without them): such a champion is left out
// of those filters when they are active, exactly like a champion whose
// region is unknown.
func classifyChampion(ch rawChampionFull) (rng, resource, damage, difficulty string) {
	rng = game.RangeMelee
	if ch.Stats.AttackRange >= rangedFrom {
		rng = game.RangeRanged
	}
	switch strings.ToLower(strings.TrimSpace(ch.Partype)) {
	case "mana":
		resource = game.ResourceMana
	case "energy":
		resource = game.ResourceEnergy
	case "none", "":
		resource = game.ResourceNone
	default:
		resource = game.ResourceOther
	}
	if ch.Info.Attack == 0 && ch.Info.Magic == 0 && ch.Info.Difficulty == 0 {
		return rng, resource, "", ""
	}
	switch lean := ch.Info.Attack - ch.Info.Magic; {
	case lean >= damageLean:
		damage = game.DamagePhysical
	case lean <= -damageLean:
		damage = game.DamageMagic
	default:
		damage = game.DamageMixed
	}
	switch d := ch.Info.Difficulty; {
	case d <= 0:
	case d <= 3:
		difficulty = game.DifficultyEasy
	case d <= 6:
		difficulty = game.DifficultyMedium
	default:
		difficulty = game.DifficultyHard
	}
	return rng, resource, damage, difficulty
}

// importAbilities lists every champion's passive and four spells as
// "Charm (Ahri)", grouped by champion. champs supplies the display name
// and release season per id.
func importAbilities(base, version string, raw map[string]rawChampionFull, champs []game.Champion) []game.Entry {
	byID := map[string]game.Champion{}
	for _, ch := range champs {
		byID[ch.ID] = ch
	}
	var out []game.Entry
	for id, rc := range raw {
		ch, ok := byID[id]
		if !ok {
			continue
		}
		var seen []string
		add := func(name, icon string) {
			name = strings.TrimSpace(name)
			if name == "" || icon == "" || containsFold(seen, name) {
				return
			}
			seen = append(seen, name)
			out = append(out, game.Entry{
				Name: name + " (" + ch.Name + ")", Icon: icon, Group: ch.Name, Champion: ch.Name, Season: ch.Season,
			})
		}
		if rc.Passive.Image.Full != "" {
			add(rc.Passive.Name, PassiveIcon(base, version, rc.Passive.Image.Full))
		}
		for _, sp := range rc.Spells {
			if sp.Image.Full != "" {
				add(sp.Name, SpellIcon(base, version, sp.Image.Full))
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// importSpells keeps the summoner spells playable on Summoner's Rift
// (modes contains CLASSIC); the Jade/Cherry/Poro variants are game-mode
// copies.
func importSpells(base, version string, raw map[string]rawSpell) []game.Entry {
	keys := make([]string, 0, len(raw))
	for k := range raw {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var out []game.Entry
	for _, k := range keys {
		sp := raw[k]
		name := strings.TrimSpace(sp.Name)
		if name == "" || sp.Image.Full == "" || !slices.Contains(sp.Modes, "CLASSIC") {
			continue
		}
		if slices.ContainsFunc(out, func(e game.Entry) bool { return strings.EqualFold(e.Name, name) }) {
			continue
		}
		out = append(out, game.Entry{Name: name, Icon: SpellIcon(base, version, sp.Image.Full)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// importRunes flattens the rune trees: the first slot of a tree holds its
// keystones ("Precision/keystone"), the others its minor rows
// ("Precision/1" ...).
func importRunes(base string, trees []rawRuneTree) []game.Entry {
	var out []game.Entry
	for _, tree := range trees {
		key := strings.TrimSpace(tree.Key)
		if key == "" {
			key = strings.TrimSpace(tree.Name)
		}
		for i, slot := range tree.Slots {
			group := key + "/keystone"
			if i > 0 {
				group = key + "/" + strconv.Itoa(i)
			}
			for _, r := range slot.Runes {
				name := strings.TrimSpace(r.Name)
				if name == "" || r.Icon == "" {
					continue
				}
				out = append(out, game.Entry{Name: name, Icon: RuneIcon(base, r.Icon), Group: group})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

var (
	// A trailing parenthetical is a chroma or an edition: "PROJECT: Akali
	// (Ruby)", "Prestige K/DA Ahri (2022)".
	skinSuffixRE = regexp.MustCompile(`\s*\([^)]*\)\s*$`)
	skinPrefixRE = regexp.MustCompile(`^(?i:prestige)\s+`)
)

// importSkinLines derives the skin lines ("PROJECT", "Star Guardian")
// from the skin names by cutting the champion's name out of each and
// keeping what is left, when at least two skins share it. Skins whose
// name is a pun on the champion's ("Beezcrank", "Pug'Maw") carry no line
// and are skipped; the odd false line the heuristic leaves ("Count",
// "King") is for the overrides file. The icon is the splash of the first
// skin found in champion-name order, so it is stable between imports.
func importSkinLines(base string, raw map[string]rawChampionFull) []game.Entry {
	type line struct {
		skins map[string]bool
		icon  string
	}
	lines := map[string]*line{}
	ids := make([]string, 0, len(raw))
	for id := range raw {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return raw[ids[i]].Name < raw[ids[j]].Name })
	for _, id := range ids {
		ch := raw[id]
		if ch.ID == "" || strings.TrimSpace(ch.Name) == "" {
			continue
		}
		cutters := nameCutters(strings.TrimSpace(ch.Name))
		for _, sk := range ch.Skins {
			if sk.Num == 0 {
				continue
			}
			name := skinPrefixRE.ReplaceAllString(skinSuffixRE.ReplaceAllString(sk.Name, ""), "")
			rest, ok := cutName(name, cutters)
			if !ok || rest == "" {
				continue
			}
			l := lines[rest]
			if l == nil {
				l = &line{skins: map[string]bool{}}
				lines[rest] = l
			}
			l.skins[ch.ID+"/"+strings.ToLower(name)] = true
			if l.icon == "" {
				l.icon = SkinSplash(base, ch.ID, sk.Num)
			}
		}
	}
	var out []game.Entry
	for name, l := range lines {
		if len(l.skins) >= 2 {
			out = append(out, game.Entry{Name: name, Icon: l.icon})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// nameCutters builds the patterns that find a champion in a skin name:
// the full name first, then for multi-word names the last and first word
// ("Yi" in "PROJECT: Yi", "Mundo" in "Corporate Mundo"), each as a whole
// word with an optional possessive.
func nameCutters(name string) []*regexp.Regexp {
	cands := []string{name}
	if parts := strings.Fields(name); len(parts) > 1 {
		cands = append(cands, parts[len(parts)-1], parts[0])
	}
	var out []*regexp.Regexp
	for _, c := range cands {
		out = append(out, regexp.MustCompile(`(?i)(^|[^\pL])`+regexp.QuoteMeta(c)+`(?:'s)?($|[^\pL])`))
	}
	return out
}

// cutName removes the first pattern that matches and tidies what is left:
// "PROJECT: Ashe" -> "PROJECT", "Ahri Star Guardian" -> "Star Guardian".
func cutName(skin string, cutters []*regexp.Regexp) (string, bool) {
	for _, re := range cutters {
		if !re.MatchString(skin) {
			continue
		}
		rest := re.ReplaceAllString(skin, "$1 $2")
		rest = strings.Join(strings.Fields(rest), " ")
		rest = strings.Trim(rest, ": ")
		return rest, true
	}
	return "", false
}

// Packs are the imported entries of the packs other than champions and
// items, handed to Build.
type Packs struct {
	Spells    []game.Entry
	Runes     []game.Entry
	Abilities []game.Entry
	SkinLines []game.Entry
	Monsters  []game.Entry
}

// Build merges the per-season item snapshots, the champion list and the
// other packs into a catalog and applies the overrides. Items are
// identified by name (case-insensitively) across seasons: an id can be
// reused and a name can change id, but a name is what players guess.
// Name, icon, tier, recipe and price come from the newest season the item
// appears in. Excluding a champion also removes its abilities.
func Build(patch string, snaps map[int][]snapItem, champs []game.Champion, packs Packs, ov Overrides) *game.Catalog {
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
				a.item.From, a.item.Into, a.item.Gold = it.From, it.Into, it.Gold
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
	c.Spells = slices.Clone(packs.Spells)
	c.Runes = slices.Clone(packs.Runes)
	c.Monsters = slices.Clone(packs.Monsters)
	for _, a := range packs.Abilities {
		if !ov.Champions.excluded(a.Champion) {
			c.Abilities = append(c.Abilities, a)
		}
	}
	for _, l := range packs.SkinLines {
		if !ov.SkinLines.excluded(l.Name) {
			c.SkinLines = append(c.SkinLines, l)
		}
	}
	c.Sort()
	return c
}
