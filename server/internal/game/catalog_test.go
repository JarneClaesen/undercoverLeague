package game

import (
	"encoding/json"
	"math/rand/v2"
	"slices"
	"testing"
	"time"
)

// testCatalog is a small hand-built pool covering the season, tier, class,
// region, range, resource, damage and difficulty combinations the filter
// tests need. Names are unique across packs. Yunara has no damage or
// difficulty, like the few champions Data Dragon ships without ratings.
func testCatalog() *Catalog {
	set := func(seasons ...int) SeasonSet {
		var s SeasonSet
		for _, x := range seasons {
			s.Add(x)
		}
		return s
	}
	c := &Catalog{
		Patch: "16.18.1",
		Champions: []Champion{
			{Name: "Annie", Icon: "https://x/Annie_0.jpg", Season: 1, Tags: []string{"Mage"}, Region: "Noxus", ID: "Annie",
				Range: RangeRanged, Resource: ResourceMana, Damage: DamageMagic, Difficulty: DifficultyEasy},
			{Name: "Ahri", Icon: "https://x/Ahri_0.jpg", Season: 1, Tags: []string{"Mage", "Assassin"}, Region: "Ionia", ID: "Ahri",
				Range: RangeRanged, Resource: ResourceMana, Damage: DamageMagic, Difficulty: DifficultyMedium},
			{Name: "Aatrox", Icon: "https://x/Aatrox_0.jpg", Season: 3, Tags: []string{"Fighter"}, Region: "Runeterra", ID: "Aatrox",
				Range: RangeMelee, Resource: ResourceOther, Damage: DamagePhysical, Difficulty: DifficultyMedium},
			{Name: "Zoe", Icon: "https://x/Zoe_0.jpg", Season: 7, Tags: []string{"Mage", "Support"}, Region: "Targon", ID: "Zoe",
				Range: RangeRanged, Resource: ResourceMana, Damage: DamageMagic, Difficulty: DifficultyHard},
			{Name: "Mel", Icon: "https://x/Mel_0.jpg", Season: 15, Tags: []string{"Mage", "Support"}, Region: "Noxus", ID: "Mel",
				Range: RangeRanged, Resource: ResourceMana, Damage: DamageMagic, Difficulty: DifficultyMedium},
			{Name: "Yunara", Icon: "https://x/Yunara_0.jpg", Season: 16, Tags: []string{"Marksman", "Support"}, Region: "Ionia", ID: "Yunara",
				Range: RangeRanged, Resource: ResourceMana},
		},
		Items: []Item{
			{Name: "Doran's Blade", Icon: "https://x/1055.png", Seasons: set(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16), Tier: TierStarter, Gold: 450},
			{Name: "Health Potion", Icon: "https://x/2003.png", Seasons: set(3, 16), Tier: TierConsumable, Gold: 50},
			{Name: "Boots", Icon: "https://x/1001.png", Seasons: set(3, 16), Tier: TierBoots, Gold: 300},
			{Name: "Berserker's Greaves", Icon: "https://x/3006.png", Seasons: set(16), Tier: TierBoots, Gold: 1100},
			{Name: "Long Sword", Icon: "https://x/1036.png", Seasons: set(3, 16), Tier: TierComponent, Into: []string{"Infinity Edge"}, Gold: 350},
			{Name: "Deathfire Grasp", Icon: "https://x/3128.png", Seasons: set(3, 4), Tier: TierLegendary, Gold: 3100},
			{Name: "Infinity Edge", Icon: "https://x/3031.png", Seasons: set(3, 16), Tier: TierLegendary, From: []string{"Long Sword"}, Gold: 3450},
			{Name: "Heartsteel", Icon: "https://x/3084.png", Seasons: set(13, 14, 15, 16), Tier: TierLegendary, Gold: 3000},
			{Name: "Yun Tal Wildarrows", Icon: "https://x/3032.png", Seasons: set(14, 15, 16), Tier: TierLegendary, Gold: 3000},
		},
		Spells: []Entry{
			{Name: "Flash", Icon: "https://x/SummonerFlash.png"},
			{Name: "Ignite", Icon: "https://x/SummonerDot.png"},
		},
		Runes: []Entry{
			{Name: "Conqueror", Icon: "https://x/Conqueror.png", Group: "Precision/keystone"},
			{Name: "Press the Attack", Icon: "https://x/PressTheAttack.png", Group: "Precision/keystone"},
			{Name: "Triumph", Icon: "https://x/Triumph.png", Group: "Precision/1"},
			{Name: "Electrocute", Icon: "https://x/Electrocute.png", Group: "Domination/keystone"},
		},
		Abilities: []Entry{
			{Name: "Charm (Ahri)", Icon: "https://x/AhriE.png", Group: "Ahri", Champion: "Ahri", Season: 1},
			{Name: "Spirit Rush (Ahri)", Icon: "https://x/AhriR.png", Group: "Ahri", Champion: "Ahri", Season: 1},
			{Name: "Disintegrate (Annie)", Icon: "https://x/AnnieQ.png", Group: "Annie", Champion: "Annie", Season: 1},
			{Name: "Paddle Star (Zoe)", Icon: "https://x/ZoeQ.png", Group: "Zoe", Champion: "Zoe", Season: 7},
		},
		SkinLines: []Entry{
			{Name: "PROJECT", Icon: "https://x/Ashe_5.jpg"},
			{Name: "Star Guardian", Icon: "https://x/Ahri_14.jpg"},
		},
		Monsters: []Entry{
			{Name: "Baron Nashor", Group: "epic"},
			{Name: "Rift Herald", Group: "epic"},
			{Name: "Gromp", Group: "camp"},
			{Name: "Nexus", Group: "lane"},
		},
	}
	c.Sort()
	return c
}

func TestCatalogRanges(t *testing.T) {
	c := testCatalog()
	if lo, hi := c.ChampSeasonRange(); lo != 1 || hi != 16 {
		t.Errorf("champ range %d-%d", lo, hi)
	}
	if lo, hi := c.ItemSeasonRange(); lo != 3 || hi != 16 {
		t.Errorf("item range %d-%d", lo, hi)
	}
	empty := &Catalog{}
	if lo, hi := empty.ChampSeasonRange(); lo != 0 || hi != 0 {
		t.Errorf("empty champ range %d-%d", lo, hi)
	}
	if lo, hi := empty.ItemSeasonRange(); lo != 0 || hi != 0 {
		t.Errorf("empty item range %d-%d", lo, hi)
	}
	if got := c.Classes(); !slices.Equal(got, []string{"Assassin", "Fighter", "Mage", "Marksman", "Support"}) {
		t.Errorf("classes %v", got)
	}
	if got := c.Regions(); !slices.Equal(got, []string{"Ionia", "Noxus", "Runeterra", "Targon"}) {
		t.Errorf("regions %v", got)
	}
	if got := empty.Classes(); len(got) != 0 {
		t.Errorf("empty classes %v", got)
	}
	// Resources come in AllResources order and only list what is present.
	if got := c.Resources(); !slices.Equal(got, []string{ResourceMana, ResourceOther}) {
		t.Errorf("resources %v", got)
	}
	if got := empty.Resources(); got == nil || len(got) != 0 {
		t.Errorf("empty resources %#v", got)
	}
}

func TestSeasonSet(t *testing.T) {
	var s SeasonSet
	s.Add(3)
	s.Add(16)
	s.Add(40) // out of range, ignored
	if !s.Has(3) || !s.Has(16) || s.Has(4) || s.Has(40) {
		t.Errorf("membership wrong: %v", s.Seasons())
	}
	if got := s.Seasons(); len(got) != 2 || got[0] != 3 || got[1] != 16 {
		t.Errorf("seasons %v", got)
	}
	if !s.Overlaps(1, 3) || s.Overlaps(4, 15) || !s.Overlaps(10, 20) {
		t.Error("overlap wrong")
	}
}

func TestPoolSize(t *testing.T) {
	c := testCatalog()
	packs := func(p ...Pack) []Pack { return p }
	cases := []struct {
		name string
		f    Filter
		want PoolSize
	}{
		{"everything", DefaultFilter(), PoolSize{PackChampions: 6, PackItems: 9}},
		{"all packs", Filter{Packs: AllPacks}, PoolSize{PackChampions: 6, PackItems: 9, PackSpells: 2, PackRunes: 4, PackAbilities: 4, PackSkinLines: 2, PackMonsters: 4}},
		{"old champions only", Filter{Packs: packs(PackChampions), ChampSeasons: [2]int{1, 3}}, PoolSize{PackChampions: 3}},
		{"new champions", Filter{Packs: packs(PackChampions), ChampSeasons: [2]int{15, 16}}, PoolSize{PackChampions: 2}},
		{"old items", Filter{Packs: packs(PackItems), ItemSeasons: [2]int{3, 10}}, PoolSize{PackItems: 6}},
		{"current legendaries", Filter{Packs: packs(PackItems), ItemSeasons: [2]int{16, 16}, ItemTiers: []Tier{TierLegendary}}, PoolSize{PackItems: 3}},
		{"no tiers", Filter{Packs: packs(PackItems), ItemTiers: []Tier{}}, PoolSize{PackItems: 0}},
		{"season with nothing", Filter{Packs: packs(PackChampions), ChampSeasons: [2]int{2, 2}}, PoolSize{PackChampions: 0}},
		{"mages", Filter{Packs: packs(PackChampions, PackAbilities), ChampClasses: []string{"Mage"}}, PoolSize{PackChampions: 4, PackAbilities: 4}},
		{"supports (secondary class counts)", Filter{Packs: packs(PackChampions), ChampClasses: []string{"support"}}, PoolSize{PackChampions: 3}},
		{"ionia", Filter{Packs: packs(PackChampions, PackAbilities), ChampRegions: []string{"Ionia"}}, PoolSize{PackChampions: 2, PackAbilities: 2}},
		{"noxus mages before S10", Filter{Packs: packs(PackChampions, PackAbilities), ChampRegions: []string{"Noxus"}, ChampClasses: []string{"Mage"}, ChampSeasons: [2]int{1, 10}}, PoolSize{PackChampions: 1, PackAbilities: 1}},
		{"champion filters do not touch other packs", Filter{Packs: packs(PackSpells, PackRunes, PackSkinLines, PackMonsters), ChampSeasons: [2]int{2, 2}, ChampRegions: []string{"Void"}}, PoolSize{PackSpells: 2, PackRunes: 4, PackSkinLines: 2, PackMonsters: 4}},
		{"melee", Filter{Packs: packs(PackChampions, PackAbilities), ChampRanges: []string{"Melee"}}, PoolSize{PackChampions: 1, PackAbilities: 0}},
		{"ranged", Filter{Packs: packs(PackChampions), ChampRanges: []string{"ranged"}}, PoolSize{PackChampions: 5}},
		{"both ranges is everything", Filter{Packs: packs(PackChampions), ChampRanges: []string{"melee", "ranged"}}, PoolSize{PackChampions: 6}},
		{"mana", Filter{Packs: packs(PackChampions, PackAbilities), ChampResources: []string{"mana"}}, PoolSize{PackChampions: 5, PackAbilities: 4}},
		{"energy (none in the fixture)", Filter{Packs: packs(PackChampions), ChampResources: []string{"energy"}}, PoolSize{PackChampions: 0}},
		{"other or none", Filter{Packs: packs(PackChampions), ChampResources: []string{"none", "other"}}, PoolSize{PackChampions: 1}},
		{"magic", Filter{Packs: packs(PackChampions, PackAbilities), ChampDamage: []string{"magic"}}, PoolSize{PackChampions: 4, PackAbilities: 4}},
		{"physical", Filter{Packs: packs(PackChampions), ChampDamage: []string{"physical"}}, PoolSize{PackChampions: 1}},
		{"unrated champion matches no damage", Filter{Packs: packs(PackChampions), ChampDamage: []string{"physical", "magic", "mixed"}}, PoolSize{PackChampions: 5}},
		{"medium", Filter{Packs: packs(PackChampions), ChampDifficulty: []string{"medium"}}, PoolSize{PackChampions: 3}},
		{"easy or hard", Filter{Packs: packs(PackChampions, PackAbilities), ChampDifficulty: []string{"hard", "easy"}}, PoolSize{PackChampions: 2, PackAbilities: 2}},
		{"ranged mana mages of medium difficulty from Noxus", Filter{Packs: packs(PackChampions), ChampRanges: []string{"ranged"}, ChampResources: []string{"mana"}, ChampClasses: []string{"Mage"}, ChampDifficulty: []string{"medium"}, ChampRegions: []string{"Noxus"}}, PoolSize{PackChampions: 1}},
		{"melee magic is nobody", Filter{Packs: packs(PackChampions), ChampRanges: []string{"melee"}, ChampDamage: []string{"magic"}}, PoolSize{PackChampions: 0}},
	}
	for _, tc := range cases {
		got := c.PoolSize(tc.f.Normalized(c))
		if len(got) != len(tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
			continue
		}
		for p, n := range tc.want {
			if got[p] != n {
				t.Errorf("%s: %s = %d, want %d", tc.name, p, got[p], n)
			}
		}
	}
	// An old fallback without the new packs simply has empty pools.
	old := &Catalog{Champions: testCatalog().Champions}
	if got := old.PoolSize(Filter{Packs: AllPacks}.Normalized(old)); got[PackSpells] != 0 || got[PackChampions] != 6 {
		t.Errorf("old catalog %v", got)
	}
	b, _ := json.Marshal(PoolSize{PackChampions: 1, PackItems: 2})
	if string(b) != `{"champions":1,"items":2}` {
		t.Errorf("pool size json %s", b)
	}
}

func TestDecoyLadder(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(3, 0))
	all := Filter{Packs: AllPacks}.Normalized(c)
	word := func(name string) Word { return Word{Name: name} }

	// draws collects every decoy seen over many rolls, so a rung with
	// several members shows all of them and never one from a lower rung.
	draws := func(pack Pack, w Word, f Filter) []string {
		seen := map[string]bool{}
		for range 300 {
			d, ok := c.Decoy(pack, w, f, rng)
			if !ok {
				t.Fatalf("%s %q: no decoy", pack, w.Name)
			}
			if d.Name == w.Name {
				t.Fatalf("%s %q: decoy is the word itself", pack, w.Name)
			}
			seen[d.Name] = true
		}
		return sortedKeys(seen)
	}
	cases := []struct {
		name string
		pack Pack
		word string
		f    Filter
		want []string
	}{
		{"champion: same primary class", PackChampions, "Ahri", all, []string{"Annie", "Mel", "Zoe"}},
		{"champion: shared secondary class when primary is unique", PackChampions, "Yunara", all, []string{"Mel", "Zoe"}},
		{"champion: any when nothing is shared", PackChampions, "Aatrox", all, []string{"Ahri", "Annie", "Mel", "Yunara", "Zoe"}},
		{"champion: filter narrows the ladder", PackChampions, "Zoe", Filter{Packs: AllPacks, ChampSeasons: [2]int{3, 16}}.Normalized(c), []string{"Mel"}},
		{"champion: filter can force the last rung", PackChampions, "Zoe", Filter{Packs: AllPacks, ChampSeasons: [2]int{3, 7}}.Normalized(c), []string{"Aatrox"}},
		{"item: build edge from", PackItems, "Infinity Edge", all, []string{"Long Sword"}},
		{"item: build edge into", PackItems, "Long Sword", all, []string{"Infinity Edge"}},
		{"item: same tier within 40% gold", PackItems, "Heartsteel", all, []string{"Deathfire Grasp", "Infinity Edge", "Yun Tal Wildarrows"}},
		{"item: same tier outside the gold window", PackItems, "Boots", all, []string{"Berserker's Greaves"}},
		{"item: any when alone in its tier", PackItems, "Health Potion", all, []string{"Berserker's Greaves", "Boots", "Deathfire Grasp", "Doran's Blade", "Heartsteel", "Infinity Edge", "Long Sword", "Yun Tal Wildarrows"}},
		{"item: season filter applies to the decoy", PackItems, "Boots", Filter{Packs: AllPacks, ItemSeasons: [2]int{3, 3}}.Normalized(c), []string{"Deathfire Grasp", "Doran's Blade", "Health Potion", "Infinity Edge", "Long Sword"}},
		{"spell: any other", PackSpells, "Flash", all, []string{"Ignite"}},
		{"rune: same slot", PackRunes, "Conqueror", all, []string{"Press the Attack"}},
		{"rune: same tree", PackRunes, "Triumph", all, []string{"Conqueror", "Press the Attack"}},
		{"rune: any", PackRunes, "Electrocute", all, []string{"Conqueror", "Press the Attack", "Triumph"}},
		{"ability: same champion", PackAbilities, "Charm (Ahri)", all, []string{"Spirit Rush (Ahri)"}},
		{"ability: any when the champion has one", PackAbilities, "Paddle Star (Zoe)", all, []string{"Charm (Ahri)", "Disintegrate (Annie)", "Spirit Rush (Ahri)"}},
		{"ability: respects champion filter", PackAbilities, "Charm (Ahri)", Filter{Packs: AllPacks, ChampRegions: []string{"Noxus", "Targon"}}.Normalized(c), []string{"Disintegrate (Annie)", "Paddle Star (Zoe)"}},
		{"skin line: any other", PackSkinLines, "PROJECT", all, []string{"Star Guardian"}},
		{"monster: same group", PackMonsters, "Baron Nashor", all, []string{"Rift Herald"}},
		{"monster: any", PackMonsters, "Gromp", all, []string{"Baron Nashor", "Nexus", "Rift Herald"}},
		{"unknown word: any member", PackChampions, "Nobody", all, []string{"Aatrox", "Ahri", "Annie", "Mel", "Yunara", "Zoe"}},
	}
	for _, tc := range cases {
		if got := draws(tc.pack, word(tc.word), tc.f); !slices.Equal(got, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}

	// The decoy carries its own icon.
	if d, ok := c.Decoy(PackChampions, word("Ahri"), all, rng); !ok || d.Icon == "" {
		t.Errorf("decoy without icon: %+v %v", d, ok)
	}
	// Nothing else to pick from.
	if _, ok := c.Decoy(PackChampions, word("Aatrox"), Filter{Packs: AllPacks, ChampSeasons: [2]int{3, 3}}.Normalized(c), rng); ok {
		t.Error("lone champion should have no decoy")
	}
	if _, ok := c.Decoy(PackSpells, word("Flash"), all, rng); !ok {
		t.Error("two spells should decoy each other")
	}
	if _, ok := (&Catalog{}).Decoy(PackMonsters, word("Gromp"), all, rng); ok {
		t.Error("empty catalog should have no decoy")
	}
}

func TestThemes(t *testing.T) {
	c := testCatalog()
	themes := c.Themes()
	ids := map[string]Theme{}
	for _, th := range themes {
		if th.ID == "" || th.Title == "" || th.Description == "" {
			t.Errorf("incomplete theme %+v", th)
		}
		if _, dup := ids[th.ID]; dup {
			t.Errorf("duplicate theme id %s", th.ID)
		}
		ids[th.ID] = th
		if err := th.Filter.Validate(); err != nil {
			t.Errorf("%s: %v", th.ID, err)
		}
		for p, n := range c.PoolSize(th.Filter.Normalized(c)) {
			if n == 0 {
				t.Errorf("%s: pack %s is empty", th.ID, p)
			}
		}
	}
	// No region reaches 5 champions in the fixture, so no region days.
	// Classes whose champions have no abilities in the fixture (Fighter,
	// Marksman) are dropped: their abilities pack would be empty.
	for id := range ids {
		if len(id) > 7 && id[:7] == "region-" {
			t.Errorf("unexpected %s", id)
		}
	}
	if _, ok := ids["class-fighter"]; ok {
		t.Error("fighter day offered although no fighter has abilities")
	}
	for _, want := range []string{"class-mage", "class-assassin", "class-support", "ranged", "spellbound", "easy", "hard", "og", "fresh", "boots", "components", "spells", "runes", "jungle", "fashion"} {
		if _, ok := ids[want]; !ok {
			t.Errorf("missing theme %s in %v", want, sortedKeys(boolKeys(ids)))
		}
	}
	// Bucket days whose abilities pack would be empty (the only melee and
	// physical champion, Aatrox, has none) or that have too few champions
	// (energy needs five, and nobody is manaless) are dropped too.
	for _, unwanted := range []string{"melee", "steel", "energy", "manaless"} {
		if _, ok := ids[unwanted]; ok {
			t.Errorf("unexpected theme %s", unwanted)
		}
	}
	if th := ids["ranged"]; !slices.Equal(th.Filter.Packs, []Pack{PackChampions, PackAbilities}) || !slices.Equal(th.Filter.ChampRanges, []string{RangeRanged}) || th.Title != "Ranged day" {
		t.Errorf("ranged day %+v", th)
	}
	if th := ids["hard"]; !slices.Equal(th.Filter.ChampDifficulty, []string{DifficultyHard}) || th.Title != "Hard mode" {
		t.Errorf("hard mode %+v", th)
	}
	if th := ids["spellbound"]; !slices.Equal(th.Filter.ChampDamage, []string{DamageMagic}) {
		t.Errorf("spellbound %+v", th)
	}
	// Season 16 alone has one champion, so Fresh reaches back until it
	// has five: S3-S16 is only four (Aatrox, Zoe, Mel, Yunara), so it ends
	// up at S1.
	if th := ids["fresh"]; th.Filter.ChampSeasons != [2]int{1, 16} || th.Description != "Only champions released in Seasons 1 to 16." {
		t.Errorf("fresh %+v", th)
	}
	many := testCatalog()
	for _, n := range []string{"A", "B", "C", "D", "E"} {
		many.Champions = append(many.Champions, Champion{Name: n, Season: 16, Tags: []string{"Mage"}})
	}
	for _, th := range many.Themes() {
		if th.ID == "fresh" && (th.Filter.ChampSeasons != [2]int{16, 16} || th.Description != "Only champions released in Season 16.") {
			t.Errorf("fresh with a full season %+v", th)
		}
	}
	if th := ids["class-mage"]; !slices.Equal(th.Filter.Packs, []Pack{PackChampions, PackAbilities}) || th.Title != "Mage Day" {
		t.Errorf("mage day %+v", th)
	}

	// Enough champions in one region make a region day.
	big := testCatalog()
	for _, n := range []string{"Darius", "Draven", "Swain", "Katarina", "Sion"} {
		big.Champions = append(big.Champions, Champion{Name: n, Season: 1, Tags: []string{"Fighter"}, Region: "Noxus"})
	}
	var noxus *Theme
	for _, th := range big.Themes() {
		if th.ID == "region-noxus" {
			noxus = &th
		}
	}
	if noxus == nil || noxus.Title != "Noxus Day" || !slices.Equal(noxus.Filter.ChampRegions, []string{"Noxus"}) {
		t.Errorf("noxus day %+v", noxus)
	}

	// Five energy champions with abilities make an Energy day; four do not.
	energy := testCatalog()
	for i, n := range []string{"Zed", "Akali", "Shen", "Kennen", "Lee Sin"} {
		energy.Champions = append(energy.Champions, Champion{Name: n, Season: 1, Tags: []string{"Assassin"}, Range: RangeMelee, Resource: ResourceEnergy, Damage: DamagePhysical, Difficulty: DifficultyHard})
		energy.Abilities = append(energy.Abilities, Entry{Name: "Q (" + n + ")", Group: n, Champion: n, Season: 1})
		if i == 3 {
			if slices.ContainsFunc(energy.Themes(), func(t Theme) bool { return t.ID == "energy" }) {
				t.Error("energy day with four champions")
			}
		}
	}
	var energyDay *Theme
	for _, th := range energy.Themes() {
		if th.ID == "energy" {
			energyDay = &th
		}
	}
	if energyDay == nil || energyDay.Title != "Energy day" || !slices.Equal(energyDay.Filter.ChampResources, []string{ResourceEnergy}) {
		t.Errorf("energy day %+v", energyDay)
	}
	// ... and now melee and physical champions have abilities too.
	for _, want := range []string{"melee", "steel"} {
		if !slices.ContainsFunc(energy.Themes(), func(t Theme) bool { return t.ID == want }) {
			t.Errorf("missing theme %s", want)
		}
	}

	// A catalog without the new packs drops the themes that need them.
	old := &Catalog{Champions: c.Champions, Items: c.Items}
	for _, th := range old.Themes() {
		if th.ID == "spells" || th.ID == "runes" || th.ID == "jungle" || th.ID == "fashion" {
			t.Errorf("old catalog offers %s", th.ID)
		}
	}
	if len(old.Themes()) == 0 {
		t.Error("old catalog has no themes at all")
	}
	if th := (&Catalog{}).DailyTheme(time.Now()); th.ID != "" {
		t.Errorf("empty catalog theme %+v", th)
	}
}

func TestDailyThemeDeterministic(t *testing.T) {
	c := testCatalog()
	day := time.Date(2026, 9, 20, 23, 30, 0, 0, time.FixedZone("CEST", 2*3600))
	a := c.DailyTheme(day)
	// Same UTC date regardless of zone and time of day.
	if b := c.DailyTheme(day.UTC()); b.ID != a.ID {
		t.Errorf("zone changed the theme: %s vs %s", a.ID, b.ID)
	}
	if b := c.DailyTheme(time.Date(2026, 9, 20, 0, 0, 1, 0, time.UTC)); b.ID != a.ID {
		t.Errorf("time of day changed the theme: %s vs %s", a.ID, b.ID)
	}
	// The pick is a hash of the date, so a run of days covers the list.
	seen := map[string]bool{}
	for i := range 200 {
		seen[c.DailyTheme(day.AddDate(0, 0, i)).ID] = true
	}
	if len(seen) != len(c.Themes()) {
		t.Errorf("200 days hit %d of %d themes", len(seen), len(c.Themes()))
	}
	b, err := json.Marshal(a)
	if err != nil || !json.Valid(b) {
		t.Fatal(err)
	}
	var back Theme
	if err := json.Unmarshal(b, &back); err != nil || back.ID != a.ID || !slices.Equal(back.Filter.Packs, a.Filter.Packs) {
		t.Errorf("theme round trip: %s -> %+v (%v)", b, back, err)
	}
}

func boolKeys(m map[string]Theme) map[string]bool {
	out := map[string]bool{}
	for k := range m {
		out[k] = true
	}
	return out
}
