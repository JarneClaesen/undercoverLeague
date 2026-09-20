package game

import (
	"hash/fnv"
	"math/rand/v2"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Pack is one category of words the host can enable. Champions and items
// are the original two; the rest were added later and an older fallback
// or cache may simply not carry them (their slices are then empty).
type Pack string

const (
	PackChampions Pack = "champions"
	PackItems     Pack = "items"
	PackSpells    Pack = "spells"    // summoner spells
	PackRunes     Pack = "runes"     // keystones and minor runes
	PackAbilities Pack = "abilities" // champion abilities, "Charm (Ahri)"
	PackSkinLines Pack = "skinlines" // "PROJECT", "Star Guardian", ...
	PackMonsters  Pack = "monsters"  // jungle camps, epic monsters, lane structures
)

var AllPacks = []Pack{PackChampions, PackItems, PackSpells, PackRunes, PackAbilities, PackSkinLines, PackMonsters}

func ValidPack(p Pack) bool { return slices.Contains(AllPacks, p) }

// Label is the pack's name in error messages, e.g. "summoner spells".
func (p Pack) Label() string {
	switch p {
	case PackSpells:
		return "summoner spells"
	case PackSkinLines:
		return "skin lines"
	}
	return string(p)
}

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

func ValidTier(t Tier) bool { return slices.Contains(AllTiers, t) }

// AllClasses are the Data Dragon champion tags; a champion has one or two,
// the first being its primary class.
var AllClasses = []string{"Assassin", "Fighter", "Mage", "Marksman", "Support", "Tank"}

// AllRegions are the Runeterra regions a champion can belong to.
// "Runeterra" is Riot's label for champions tied to no single region.
var AllRegions = []string{
	"Bandle City", "Bilgewater", "Demacia", "Freljord", "Ionia", "Ixtal", "Noxus",
	"Piltover", "Runeterra", "Shadow Isles", "Shurima", "Targon", "Void", "Zaun",
}

func ValidRegion(r string) bool { return slices.Contains(AllRegions, r) }

// The four fixed champion buckets below are derived by the importer from
// championFull.json (see catalog.classifyChampion); a champion has exactly
// one of each, or "" when Data Dragon has no data for it (damage and
// difficulty only). Validation is case-insensitive like classes/regions.
const (
	RangeMelee  = "melee"  // attack range under 300
	RangeRanged = "ranged" // attack range 300 and up

	ResourceMana   = "mana"
	ResourceEnergy = "energy"
	ResourceNone   = "none"  // manaless: Data Dragon "None" or ""
	ResourceOther  = "other" // Fury, Rage, Heat, Grit, Flow, Blood Well, ...

	DamagePhysical = "physical"
	DamageMagic    = "magic"
	DamageMixed    = "mixed"

	DifficultyEasy   = "easy"   // info.difficulty 1-3
	DifficultyMedium = "medium" // 4-6
	DifficultyHard   = "hard"   // 7-10
)

var (
	AllRanges       = []string{RangeMelee, RangeRanged}
	AllResources    = []string{ResourceMana, ResourceEnergy, ResourceNone, ResourceOther}
	AllDamages      = []string{DamagePhysical, DamageMagic, DamageMixed}
	AllDifficulties = []string{DifficultyEasy, DifficultyMedium, DifficultyHard}
)

func ValidRange(s string) bool      { return containsFold(AllRanges, s) }
func ValidResource(s string) bool   { return containsFold(AllResources, s) }
func ValidDamage(s string) bool     { return containsFold(AllDamages, s) }
func ValidDifficulty(s string) bool { return containsFold(AllDifficulties, s) }

// Lanes are the positions a champion is actually played in, from Riot's
// per-position play rates (imported via Meraki Analytics, see
// catalog.laneTable). A champion has every lane with a non-zero rate, so
// most have one or two; one missing from the feed has none and matches no
// lane filter, like a champion whose region is unknown.
const (
	LaneTop     = "top"
	LaneJungle  = "jungle"
	LaneMid     = "mid"
	LaneBot     = "bot"
	LaneSupport = "support"
)

var AllLanes = []string{LaneTop, LaneJungle, LaneMid, LaneBot, LaneSupport}

func ValidLane(s string) bool { return containsFold(AllLanes, s) }

// LaneLabel is the lane's name in titles: Top, Jungle, Mid, Bot, Support.
func LaneLabel(lane string) string {
	switch strings.ToLower(lane) {
	case LaneTop:
		return "Top"
	case LaneJungle:
		return "Jungle"
	case LaneMid:
		return "Mid"
	case LaneBot:
		return "Bot"
	case LaneSupport:
		return "Support"
	}
	return lane
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
	Name   string   `json:"name"`
	Icon   string   `json:"icon"` // https URL of the loading-screen art
	Season int      `json:"season"`
	Tags   []string `json:"tags,omitempty"`   // Data Dragon classes, primary first
	Region string   `json:"region,omitempty"` // one of AllRegions, "" when unknown
	ID     string   `json:"id,omitempty"`     // Data Dragon id, e.g. MonkeyKing

	// Fixed buckets, see AllRanges etc. Damage and Difficulty are "" for
	// the few champions Data Dragon ships without info ratings.
	Range      string `json:"range,omitempty"`
	Resource   string `json:"resource,omitempty"`
	Damage     string `json:"damage,omitempty"`
	Difficulty string `json:"difficulty,omitempty"`

	// Lanes the champion is played in, a subset of AllLanes in that order;
	// nil when the play-rate feed did not know the champion.
	Lanes []string `json:"lanes,omitempty"`
}

type Item struct {
	Name    string    `json:"name"`
	Icon    string    `json:"icon"`
	Seasons SeasonSet `json:"seasons"` // every season the item was in the SR shop
	Tier    Tier      `json:"tier"`
	From    []string  `json:"from,omitempty"` // component names, as of the newest season
	Into    []string  `json:"into,omitempty"` // what it builds into, names
	Gold    int       `json:"gold,omitempty"` // total price, newest season
}

// Entry is a member of one of the smaller packs. Group is what Decoy uses
// to find a neighbour; its meaning depends on the pack (see Catalog).
type Entry struct {
	Name     string `json:"name"`
	Icon     string `json:"icon"`
	Group    string `json:"group,omitempty"`
	Champion string `json:"champion,omitempty"` // abilities: the champion's display name
	Season   int    `json:"season,omitempty"`   // abilities: the champion's release season
}

// Word is what a game draws: the name shown to civilians and its picture.
type Word struct {
	Name string `json:"name"`
	Icon string `json:"icon"`
}

// Catalog is the full word pool. It is built by the catalog package,
// published to the hub as an immutable value and never mutated afterwards.
type Catalog struct {
	Patch string `json:"patch"`
	// LanesPatch is the patch of the play-rate feed the champion lanes
	// came from (Meraki numbers patches differently from Data Dragon),
	// "" when no lanes were imported.
	LanesPatch string     `json:"lanesPatch,omitempty"`
	Champions  []Champion `json:"champions"`
	Items      []Item     `json:"items"`
	Spells     []Entry    `json:"spells,omitempty"`    // Group ""
	Runes      []Entry    `json:"runes,omitempty"`     // Group "<tree>/keystone" or "<tree>/<row>"
	Abilities  []Entry    `json:"abilities,omitempty"` // Group = champion name
	SkinLines  []Entry    `json:"skinLines,omitempty"` // Group ""
	Monsters   []Entry    `json:"monsters,omitempty"`  // Group epic | drake | camp | lane
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

// Classes lists every champion tag present, sorted.
func (c *Catalog) Classes() []string {
	set := map[string]bool{}
	for _, ch := range c.Champions {
		for _, t := range ch.Tags {
			set[t] = true
		}
	}
	return sortedKeys(set)
}

// Regions lists every champion region present, sorted.
func (c *Catalog) Regions() []string {
	set := map[string]bool{}
	for _, ch := range c.Champions {
		if ch.Region != "" {
			set[ch.Region] = true
		}
	}
	return sortedKeys(set)
}

// Resources lists the resource buckets present, in AllResources order:
// energy is rare enough that a filtered catalog can lack it entirely.
func (c *Catalog) Resources() []string {
	set := map[string]bool{}
	for _, ch := range c.Champions {
		if ch.Resource != "" {
			set[ch.Resource] = true
		}
	}
	out := []string{}
	for _, r := range AllResources {
		if set[r] {
			out = append(out, r)
		}
	}
	return out
}

// Lanes lists the lanes any champion is played in, in AllLanes order:
// empty when the play-rate feed was never reached, in which case the
// client offers no lane filter (every lane would empty the pool).
func (c *Catalog) Lanes() []string {
	set := map[string]bool{}
	for _, ch := range c.Champions {
		for _, l := range ch.Lanes {
			set[l] = true
		}
	}
	out := []string{}
	for _, l := range AllLanes {
		if set[l] {
			out = append(out, l)
		}
	}
	return out
}

func sortedKeys(set map[string]bool) []string {
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// FilterChampions returns the champions matching f's seasons, classes,
// regions, lanes, range, resource, damage and difficulty (whether or not
// the champions pack is enabled).
func (c *Catalog) FilterChampions(f Filter) []Champion {
	var out []Champion
	for _, ch := range c.Champions {
		if c.champMatches(ch, f) {
			out = append(out, ch)
		}
	}
	return out
}

func (c *Catalog) champMatches(ch Champion, f Filter) bool {
	if ch.Season < f.ChampSeasons[0] || ch.Season > f.ChampSeasons[1] {
		return false
	}
	if len(f.ChampClasses) > 0 && !slices.ContainsFunc(ch.Tags, func(t string) bool { return containsFold(f.ChampClasses, t) }) {
		return false
	}
	if len(f.ChampRegions) > 0 && !containsFold(f.ChampRegions, ch.Region) {
		return false
	}
	if len(f.ChampLanes) > 0 && !slices.ContainsFunc(ch.Lanes, func(l string) bool { return containsFold(f.ChampLanes, l) }) {
		return false
	}
	// The buckets: an unknown ("") damage or difficulty matches nothing
	// once that filter is active, like an unknown region.
	for _, b := range []struct {
		want []string
		have string
	}{
		{f.ChampRanges, ch.Range}, {f.ChampResources, ch.Resource}, {f.ChampDamage, ch.Damage}, {f.ChampDifficulty, ch.Difficulty},
	} {
		if len(b.want) > 0 && !containsFold(b.want, b.have) {
			return false
		}
	}
	return true
}

func containsFold(list []string, s string) bool {
	return slices.ContainsFunc(list, func(x string) bool { return strings.EqualFold(x, s) })
}

// FilterItems returns the items matching f's seasons and tiers.
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

// FilterAbilities returns the abilities of the champions FilterChampions
// keeps: the champion filters reach this pack through its owner.
func (c *Catalog) FilterAbilities(f Filter) []Entry {
	keep := map[string]bool{}
	for _, ch := range c.FilterChampions(f) {
		keep[ch.Name] = true
	}
	var out []Entry
	for _, a := range c.Abilities {
		if keep[a.Champion] {
			out = append(out, a)
		}
	}
	return out
}

// FilterPack is what a game with filter f can draw from pack p, in
// catalog order. Packs without filters return every member.
func (c *Catalog) FilterPack(p Pack, f Filter) []Word {
	var out []Word
	switch p {
	case PackChampions:
		for _, ch := range c.FilterChampions(f) {
			out = append(out, Word{Name: ch.Name, Icon: ch.Icon})
		}
	case PackItems:
		for _, it := range c.FilterItems(f) {
			out = append(out, Word{Name: it.Name, Icon: it.Icon})
		}
	case PackAbilities:
		out = entryWords(c.FilterAbilities(f))
	default:
		out = entryWords(c.entries(p))
	}
	return out
}

func (c *Catalog) entries(p Pack) []Entry {
	switch p {
	case PackSpells:
		return c.Spells
	case PackRunes:
		return c.Runes
	case PackAbilities:
		return c.Abilities
	case PackSkinLines:
		return c.SkinLines
	case PackMonsters:
		return c.Monsters
	}
	return nil
}

func entryWords(entries []Entry) []Word {
	var out []Word
	for _, e := range entries {
		out = append(out, Word{Name: e.Name, Icon: e.Icon})
	}
	return out
}

// PoolSize counts what a game with these settings could draw from, one
// key per enabled pack. f should already be Normalized.
func (c *Catalog) PoolSize(f Filter) PoolSize {
	p := PoolSize{}
	for _, pack := range f.Packs {
		p[pack] = len(c.FilterPack(pack, f))
	}
	return p
}

type PoolSize map[Pack]int

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

// Sort orders every list by name so output is stable regardless of the
// order the importer produced them in.
func (c *Catalog) Sort() {
	sort.Slice(c.Champions, func(i, j int) bool { return c.Champions[i].Name < c.Champions[j].Name })
	sort.Slice(c.Items, func(i, j int) bool { return c.Items[i].Name < c.Items[j].Name })
	for _, list := range [][]Entry{c.Spells, c.Runes, c.Abilities, c.SkinLines, c.Monsters} {
		sort.Slice(list, func(i, j int) bool { return list[i].Name < list[j].Name })
	}
}

// ---------------------------------------------------------------------------
// Decoys
// ---------------------------------------------------------------------------

// Decoy returns a plausible neighbour of word in the same pack for an
// Undercover to describe, chosen only among words f could draw itself:
//
//	champions: same primary class, then any shared class, then any
//	items:     shares a build edge (From/Into either way), then same tier
//	           within ±40% gold, then same tier, then any
//	runes:     same Group (tree/slot), then same tree, then any
//	abilities: another ability of the same champion, then any
//	monsters:  same Group, then any
//	spells, skin lines: any other member
//
// ok is false only when the pack has no other member under f.
func (c *Catalog) Decoy(pack Pack, word Word, f Filter, rng *rand.Rand) (Word, bool) {
	var ladder [][]Word
	switch pack {
	case PackChampions:
		ladder = c.championLadder(word, f)
	case PackItems:
		ladder = c.itemLadder(word, f)
	case PackRunes:
		ladder = c.runeLadder(word)
	case PackAbilities:
		ladder = groupLadder(c.FilterAbilities(f), word)
	case PackMonsters:
		ladder = groupLadder(c.Monsters, word)
	default:
		ladder = [][]Word{others(c.FilterPack(pack, f), word)}
	}
	for _, rung := range ladder {
		if len(rung) > 0 {
			return rung[rng.IntN(len(rung))], true
		}
	}
	return Word{}, false
}

// others drops word itself from a pool.
func others(pool []Word, word Word) []Word {
	return slices.DeleteFunc(slices.Clone(pool), func(w Word) bool { return strings.EqualFold(w.Name, word.Name) })
}

func (c *Catalog) championLadder(word Word, f Filter) [][]Word {
	pool := c.FilterChampions(f)
	var self *Champion
	rest := make([]Champion, 0, len(pool))
	for i := range pool {
		if strings.EqualFold(pool[i].Name, word.Name) {
			self = &pool[i]
		} else {
			rest = append(rest, pool[i])
		}
	}
	any := champWords(rest, nil)
	if self == nil || len(self.Tags) == 0 {
		return [][]Word{any}
	}
	primary := self.Tags[0]
	return [][]Word{
		champWords(rest, func(ch Champion) bool { return len(ch.Tags) > 0 && ch.Tags[0] == primary }),
		champWords(rest, func(ch Champion) bool {
			return slices.ContainsFunc(ch.Tags, func(t string) bool { return slices.Contains(self.Tags, t) })
		}),
		any,
	}
}

func champWords(list []Champion, keep func(Champion) bool) []Word {
	var out []Word
	for _, ch := range list {
		if keep == nil || keep(ch) {
			out = append(out, Word{Name: ch.Name, Icon: ch.Icon})
		}
	}
	return out
}

func (c *Catalog) itemLadder(word Word, f Filter) [][]Word {
	pool := c.FilterItems(f)
	var self *Item
	rest := make([]Item, 0, len(pool))
	for i := range pool {
		if strings.EqualFold(pool[i].Name, word.Name) {
			self = &pool[i]
		} else {
			rest = append(rest, pool[i])
		}
	}
	any := itemWords(rest, nil)
	if self == nil {
		return [][]Word{any}
	}
	linked := func(it Item) bool {
		return containsFold(self.From, it.Name) || containsFold(self.Into, it.Name) ||
			containsFold(it.From, self.Name) || containsFold(it.Into, self.Name)
	}
	sameTier := func(it Item) bool { return it.Tier == self.Tier }
	lo, hi := self.Gold*6/10, self.Gold*14/10
	return [][]Word{
		itemWords(rest, linked),
		itemWords(rest, func(it Item) bool { return sameTier(it) && self.Gold > 0 && it.Gold >= lo && it.Gold <= hi }),
		itemWords(rest, sameTier),
		any,
	}
}

func itemWords(list []Item, keep func(Item) bool) []Word {
	var out []Word
	for _, it := range list {
		if keep == nil || keep(it) {
			out = append(out, Word{Name: it.Name, Icon: it.Icon})
		}
	}
	return out
}

// groupLadder is "same Group, then any" for the entry packs.
func groupLadder(list []Entry, word Word) [][]Word {
	self, rest := splitEntries(list, word)
	any := entryWords(rest)
	if self == nil {
		return [][]Word{any}
	}
	return [][]Word{filterEntries(rest, func(e Entry) bool { return e.Group == self.Group }), any}
}

func (c *Catalog) runeLadder(word Word) [][]Word {
	self, rest := splitEntries(c.Runes, word)
	any := entryWords(rest)
	if self == nil {
		return [][]Word{any}
	}
	tree, _, _ := strings.Cut(self.Group, "/")
	return [][]Word{
		filterEntries(rest, func(e Entry) bool { return e.Group == self.Group }),
		filterEntries(rest, func(e Entry) bool { t, _, _ := strings.Cut(e.Group, "/"); return t == tree }),
		any,
	}
}

func splitEntries(list []Entry, word Word) (self *Entry, rest []Entry) {
	rest = make([]Entry, 0, len(list))
	for i := range list {
		if self == nil && strings.EqualFold(list[i].Name, word.Name) {
			self = &list[i]
		} else {
			rest = append(rest, list[i])
		}
	}
	return self, rest
}

func filterEntries(list []Entry, keep func(Entry) bool) []Word {
	var out []Word
	for _, e := range list {
		if keep(e) {
			out = append(out, Word{Name: e.Name, Icon: e.Icon})
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Daily theme
// ---------------------------------------------------------------------------

// Theme is a preset filter the lobby screen offers as "today's theme".
type Theme struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Filter      Filter `json:"filter"`
}

// minRegionChampions is how many champions a region (or a lane, or the
// energy resource) needs for its own day.
const minRegionChampions = 5

// Themes lists every theme this catalog can play: one per region with
// enough champions, one per class, one per range/resource/damage/
// difficulty bucket worth a day, one per lane with enough champions, and
// the fixed ones below. Themes whose packs would be empty (an old fallback
// without them) are left out so the daily pick can always start a game.
func (c *Catalog) Themes() []Theme {
	var out []Theme
	byRegion := map[string]int{}
	byLane := map[string]int{}
	energy := 0
	for _, ch := range c.Champions {
		if ch.Region != "" {
			byRegion[ch.Region]++
		}
		for _, l := range ch.Lanes {
			byLane[l]++
		}
		if ch.Resource == ResourceEnergy {
			energy++
		}
	}
	for _, r := range c.Regions() {
		if byRegion[r] >= minRegionChampions {
			out = append(out, Theme{
				ID:          "region-" + slug(r),
				Title:       r + " Day",
				Description: "Only champions from " + r + " and their abilities.",
				Filter:      Filter{Packs: []Pack{PackChampions, PackAbilities}, ChampRegions: []string{r}},
			})
		}
	}
	for _, cl := range c.Classes() {
		out = append(out, Theme{
			ID:          "class-" + slug(cl),
			Title:       cl + " Day",
			Description: "Only " + cl + " champions and their abilities.",
			Filter:      Filter{Packs: []Pack{PackChampions, PackAbilities}, ChampClasses: []string{cl}},
		})
	}
	// "Fresh" is the current season, widened backwards early in a season
	// when it would otherwise be a handful of champions.
	_, current := c.ChampSeasonRange()
	fresh := current
	for fresh > 1 && len(c.FilterChampions(Filter{ChampSeasons: [2]int{fresh, current}}.Normalized(c))) < minRegionChampions {
		fresh--
	}
	freshDesc := "Only champions released in Season " + strconv.Itoa(current) + "."
	if fresh < current {
		freshDesc = "Only champions released in Seasons " + strconv.Itoa(fresh) + " to " + strconv.Itoa(current) + "."
	}
	champs := []Pack{PackChampions, PackAbilities}
	out = append(out,
		Theme{ID: "melee", Title: "Melee day", Description: "Only melee champions and their abilities.",
			Filter: Filter{Packs: champs, ChampRanges: []string{RangeMelee}}},
		Theme{ID: "ranged", Title: "Ranged day", Description: "Only ranged champions and their abilities.",
			Filter: Filter{Packs: champs, ChampRanges: []string{RangeRanged}}},
	)
	if energy >= minRegionChampions {
		out = append(out, Theme{ID: "energy", Title: "Energy day", Description: "Only champions that run on energy, and their abilities.",
			Filter: Filter{Packs: champs, ChampResources: []string{ResourceEnergy}}})
	}
	out = append(out,
		Theme{ID: "manaless", Title: "Manaless day", Description: "Only champions with no resource bar, and their abilities.",
			Filter: Filter{Packs: champs, ChampResources: []string{ResourceNone}}},
		Theme{ID: "spellbound", Title: "Spellbound", Description: "Only magic-damage champions and their abilities.",
			Filter: Filter{Packs: champs, ChampDamage: []string{DamageMagic}}},
		Theme{ID: "steel", Title: "Steel & bone", Description: "Only physical-damage champions and their abilities.",
			Filter: Filter{Packs: champs, ChampDamage: []string{DamagePhysical}}},
		Theme{ID: "easy", Title: "Easy pickings", Description: "Only the easiest champions to pick up, and their abilities.",
			Filter: Filter{Packs: champs, ChampDifficulty: []string{DifficultyEasy}}},
		Theme{ID: "hard", Title: "Hard mode", Description: "Only the hardest champions to master, and their abilities.",
			Filter: Filter{Packs: champs, ChampDifficulty: []string{DifficultyHard}}},
	)
	// One day per lane: "Jungle day" is taken by the monsters pack, so the
	// jungle's is named after its players.
	for _, l := range AllLanes {
		if byLane[l] < minRegionChampions {
			continue
		}
		title, desc := LaneLabel(l)+" lane day", "Only champions played "+l+" and their abilities."
		switch l {
		case LaneJungle:
			title, desc = "Jungler day", "Only junglers and their abilities."
		case LaneSupport:
			title, desc = "Support day", "Only supports and their abilities."
		}
		out = append(out, Theme{ID: "lane-" + l, Title: title, Description: desc,
			Filter: Filter{Packs: champs, ChampLanes: []string{l}}})
	}
	out = append(out,
		Theme{ID: "og", Title: "OG", Description: "Only champions released in Seasons 1 to 3.",
			Filter: Filter{Packs: []Pack{PackChampions}, ChampSeasons: [2]int{1, 3}}},
		Theme{ID: "fresh", Title: "Fresh", Description: freshDesc,
			Filter: Filter{Packs: []Pack{PackChampions}, ChampSeasons: [2]int{fresh, current}}},
		Theme{ID: "boots", Title: "Boots only", Description: "Every pair of boots ever sold.",
			Filter: Filter{Packs: []Pack{PackItems}, ItemTiers: []Tier{TierBoots}}},
		Theme{ID: "components", Title: "Components only", Description: "Only the items you build other items from.",
			Filter: Filter{Packs: []Pack{PackItems}, ItemTiers: []Tier{TierComponent}}},
		Theme{ID: "spells", Title: "Summoner spells only", Description: "Flash, Ignite, Teleport and friends.",
			Filter: Filter{Packs: []Pack{PackSpells}}},
		Theme{ID: "runes", Title: "Runes only", Description: "Keystones and minor runes.",
			Filter: Filter{Packs: []Pack{PackRunes}}},
		Theme{ID: "jungle", Title: "Jungle day", Description: "Camps, drakes, Baron and everything else on the map.",
			Filter: Filter{Packs: []Pack{PackMonsters}}},
		Theme{ID: "fashion", Title: "Fashion week", Description: "Only skin lines.",
			Filter: Filter{Packs: []Pack{PackSkinLines}}},
	)
	return slices.DeleteFunc(out, func(t Theme) bool {
		for _, n := range c.PoolSize(t.Filter.Normalized(c)) {
			if n == 0 {
				return true
			}
		}
		return false
	})
}

// DailyTheme picks today's theme by UTC date, the same for every server
// and every lobby. Returns the zero Theme only when the catalog is empty.
func (c *Catalog) DailyTheme(day time.Time) Theme {
	themes := c.Themes()
	if len(themes) == 0 {
		return Theme{}
	}
	h := fnv.New32a()
	h.Write([]byte(day.UTC().Format("2006-01-02")))
	return themes[int(h.Sum32()%uint32(len(themes)))]
}

func slug(s string) string {
	return strings.ReplaceAll(strings.ToLower(s), " ", "-")
}
