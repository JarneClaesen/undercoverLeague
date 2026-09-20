package catalog

import (
	"encoding/json"
	"slices"
	"testing"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

func TestSeasonVersions(t *testing.T) {
	versions := []string{"16.18.1", "16.17.1", "15.24.1", "15.1.1", "4.21.5", "4.1.2", "3.15.5", "3.6.14", "lolpatch_3.11", "0.154.3"}
	bySeason, current := SeasonVersions(versions)
	if current != 16 {
		t.Errorf("current %d", current)
	}
	want := map[int]string{16: "16.18.1", 15: "15.24.1", 4: "4.21.5", 3: "3.15.5"}
	if len(bySeason) != len(want) {
		t.Errorf("got %v", bySeason)
	}
	for s, v := range want {
		if bySeason[s] != v {
			t.Errorf("season %d: got %q want %q", s, bySeason[s], v)
		}
	}
	if _, cur := SeasonVersions([]string{"lolpatch_3.7"}); cur != 0 {
		t.Errorf("garbage list gave current %d", cur)
	}
	if SeasonOfYear(2009) != 1 || SeasonOfYear(2011) != 1 || SeasonOfYear(2013) != 3 || SeasonOfYear(2026) != 16 {
		t.Error("SeasonOfYear")
	}
}

func rawItems(t *testing.T, src string) map[string]rawItem {
	t.Helper()
	var body struct {
		Data map[string]rawItem `json:"data"`
	}
	if err := json.Unmarshal([]byte(src), &body); err != nil {
		t.Fatal(err)
	}
	return body.Data
}

// A trimmed 16.x item.json: the shapes the importer must handle today.
const items16 = `{"data":{
 "1001": {"name":"Boots","gold":{"total":300,"purchasable":true},"tags":["Boots"],"into":["3006"],"maps":{"11":true,"12":true}},
 "1036": {"name":"Long Sword","gold":{"total":350,"purchasable":true},"tags":["Damage","Lane"],"into":["3134","6692"],"maps":{"11":true}},
 "1055": {"name":"Doran's Blade","gold":{"total":450,"purchasable":true},"tags":["Health","Damage","Lane"],"maps":{"11":true}},
 "1082": {"name":"Dark Seal","gold":{"total":350,"purchasable":true},"tags":["SpellDamage","Lane"],"into":["3041"],"maps":{"11":true}},
 "2003": {"name":"Health Potion","gold":{"total":50,"purchasable":true},"tags":["Consumable","Lane"],"maps":{"11":true}},
 "3340": {"name":"Stealth Ward","gold":{"total":0,"purchasable":true},"tags":["Trinket","Vision"],"maps":{"11":true}},
 "3067": {"name":"Kindlegem","gold":{"total":800,"purchasable":true},"tags":["Health"],"from":["1028"],"into":["3084"],"maps":{"11":true}},
 "3003": {"name":"Archangel's Staff","gold":{"total":2900,"purchasable":true},"tags":["SpellDamage","Mana"],"from":["3070","1052"],"into":["3040"],"maps":{"11":true}},
 "3040": {"name":"Seraph's Embrace","gold":{"total":2900,"purchasable":false},"tags":["SpellDamage"],"from":["3003"],"maps":{"11":true}},
 "3031": {"name":"Infinity Edge","gold":{"total":3500,"purchasable":true},"tags":["CriticalStrike","Damage"],"from":["1038","1018"],"maps":{"11":true}},
 "3153": {"name":"Blade of The Ruined King","gold":{"total":3200,"purchasable":true},"tags":["Damage"],"from":["1053"],"maps":{"11":true}},
 "3174": {"name":"Armored Advance","gold":{"total":1200,"purchasable":true},"tags":["Armor","Boots"],"from":["3047"],"maps":{"11":true}},
 "3128": {"name":"Deathfire Grasp","gold":{"total":2900,"purchasable":true},"tags":["SpellDamage"],"from":["1058"],"maps":{"11":false,"30":true}},
 "3600": {"name":"Kalista's Black Spear","gold":{"total":0,"purchasable":true},"tags":[],"maps":{"11":true},"requiredChampion":"Kalista"},
 "7001": {"name":"Syzygy","gold":{"total":3200,"purchasable":true},"tags":["Damage"],"maps":{"11":true},"requiredAlly":"Ornn"},
 "223153": {"name":"Blade of The Ruined King","gold":{"total":3200,"purchasable":true},"tags":["Damage"],"maps":{"11":true}},
 "9999": {"name":"  ","gold":{"total":1,"purchasable":true},"maps":{"11":true}},
 "4001": {"name":"Hidden","gold":{"total":1,"purchasable":true},"maps":{"11":true},"hideFromAll":true},
 "4002": {"name":"Not in store","gold":{"total":1,"purchasable":true},"maps":{"11":true},"inStore":false}
}}`

// A trimmed 3.15 item.json: no maps key for SR items, "1" for the rest,
// no Lane/Jungle tags.
const items3 = `{"data":{
 "1001": {"name":"Boots of Speed","gold":{"total":325,"purchasable":true},"tags":["Boots"],"into":["3006"]},
 "1055": {"name":"Doran's Blade","gold":{"total":440,"purchasable":true},"tags":["Health","Damage"]},
 "1036": {"name":"Long Sword","gold":{"total":360,"purchasable":true},"tags":["Damage"],"into":["3134"]},
 "3128": {"name":"Deathfire Grasp","gold":{"total":3100,"purchasable":true},"tags":["SpellDamage"],"from":["1058"],"maps":{"8":false,"10":false}},
 "3153": {"name":"Blade of the Ruined King","gold":{"total":2850,"purchasable":true},"tags":["Damage"],"from":["1053"]},
 "3131": {"name":"Sword of the Divine","gold":{"total":2150,"purchasable":true},"tags":["AttackSpeed"],"from":["1043"]},
 "3104": {"name":"Lord Van Damm's Pillager","gold":{"total":3000,"purchasable":true},"tags":["Damage"],"from":["1037"],"maps":{"1":false,"8":true}},
 "2044": {"name":"Stealth Ward","gold":{"total":75,"purchasable":true},"tags":["Consumable","Vision"]}
}}`

func names(items []snapItem) []string {
	out := make([]string, len(items))
	for i, it := range items {
		out[i] = it.Name
	}
	return out
}

func TestImportItems(t *testing.T) {
	got := importItems("https://dd", "16.18.1", rawItems(t, items16))
	want := []string{"Archangel's Staff", "Armored Advance", "Blade of The Ruined King", "Boots", "Dark Seal", "Doran's Blade", "Health Potion", "Infinity Edge", "Kindlegem", "Long Sword", "Stealth Ward"}
	if !slices.Equal(names(got), want) {
		t.Errorf("16.x import:\n got %v\nwant %v", names(got), want)
	}
	tiers := map[string]game.Tier{}
	for _, it := range got {
		tiers[it.Name] = it.Tier
		if it.Icon == "" || it.Icon[:len("https://dd/cdn/16.18.1/img/item/")] != "https://dd/cdn/16.18.1/img/item/" {
			t.Errorf("%s icon %q", it.Name, it.Icon)
		}
	}
	wantTiers := map[string]game.Tier{
		"Boots": game.TierBoots, "Armored Advance": game.TierBoots,
		"Health Potion": game.TierConsumable, "Stealth Ward": game.TierConsumable,
		"Doran's Blade": game.TierStarter, "Dark Seal": game.TierStarter,
		"Long Sword": game.TierComponent, "Kindlegem": game.TierComponent,
		"Archangel's Staff": game.TierLegendary, "Infinity Edge": game.TierLegendary, "Blade of The Ruined King": game.TierLegendary,
	}
	for n, tier := range wantTiers {
		if tiers[n] != tier {
			t.Errorf("%s: tier %s, want %s", n, tiers[n], tier)
		}
	}
	// The six-digit duplicate lost to the four-digit original.
	for _, it := range got {
		if it.Name == "Blade of The Ruined King" && it.Icon != "https://dd/cdn/16.18.1/img/item/3153.png" {
			t.Errorf("duplicate resolution picked %s", it.Icon)
		}
	}

	got = importItems("https://dd", "3.15.5", rawItems(t, items3))
	want = []string{"Blade of the Ruined King", "Boots of Speed", "Deathfire Grasp", "Doran's Blade", "Long Sword", "Stealth Ward", "Sword of the Divine"}
	if !slices.Equal(names(got), want) {
		t.Errorf("3.x import:\n got %v\nwant %v", names(got), want)
	}
	for _, it := range got {
		switch it.Name {
		case "Doran's Blade":
			if it.Tier != game.TierStarter {
				t.Errorf("3.x Doran's Blade tier %s", it.Tier)
			}
		case "Long Sword":
			if it.Tier != game.TierComponent {
				t.Errorf("3.x Long Sword tier %s", it.Tier)
			}
		case "Deathfire Grasp":
			if it.Tier != game.TierLegendary {
				t.Errorf("3.x DFG tier %s", it.Tier)
			}
		}
	}
}

func TestImportChampions(t *testing.T) {
	raw := map[string]rawChampion{
		"MonkeyKing": {ID: "MonkeyKing", Name: "Wukong"},
		"Ahri":       {ID: "Ahri", Name: "Ahri"},
		"Broken":     {ID: "", Name: "x"},
	}
	got := importChampions("https://dd", raw, func(id string) int { return map[string]int{"MonkeyKing": 1, "Ahri": 1}[id] })
	if len(got) != 2 || got[0].Name != "Ahri" || got[1].Name != "Wukong" {
		t.Fatalf("got %+v", got)
	}
	if got[1].Icon != "https://dd/cdn/img/champion/loading/MonkeyKing_0.jpg" || got[1].Season != 1 {
		t.Errorf("Wukong %+v", got[1])
	}
}

func TestBuild(t *testing.T) {
	snaps := map[int][]snapItem{
		3:  importItems("https://dd", "3.15.5", rawItems(t, items3)),
		16: importItems("https://dd", "16.18.1", rawItems(t, items16)),
	}
	champs := []game.Champion{{Name: "Ahri", Icon: "a", Season: 1}, {Name: "Wukong", Icon: "w", Season: 1}}
	ov := Overrides{
		Items: ItemOverrides{
			Exclude:        []string{" health potion "},
			ExcludeSeasons: map[string][]int{"Sword of the Divine": {3}},
			Include:        []IncludedItem{{Name: "Seraph's Embrace", Icon: "https://dd/3040.png", Tier: game.TierLegendary, Seasons: [2]int{3, 16}}},
			Tiers:          map[string]game.Tier{"long sword": game.TierStarter},
		},
		Champions: ChampionOverrides{Exclude: []string{"wukong"}},
	}
	c := Build("16.18.1", snaps, champs, ov)

	if c.Patch != "16.18.1" || len(c.Champions) != 1 || c.Champions[0].Name != "Ahri" {
		t.Errorf("champions %+v", c.Champions)
	}
	byName := map[string]game.Item{}
	for _, it := range c.Items {
		byName[it.Name] = it
	}
	// Renamed across seasons: merged by case-insensitive name, newest name and icon win.
	if _, old := byName["Blade of the Ruined King"]; old {
		t.Error("old capitalisation survived the merge")
	}
	if it := byName["Blade of The Ruined King"]; !it.Seasons.Has(3) || !it.Seasons.Has(16) || it.Icon != "https://dd/cdn/16.18.1/img/item/3153.png" {
		t.Errorf("BotRK %+v", it)
	}
	// Removed item keeps the icon of its last season.
	if it := byName["Deathfire Grasp"]; !it.Seasons.Has(3) || it.Seasons.Has(16) || it.Icon != "https://dd/cdn/3.15.5/img/item/3128.png" {
		t.Errorf("DFG %+v", it)
	}
	if _, ok := byName["Health Potion"]; ok {
		t.Error("exclude ignored")
	}
	if _, ok := byName["Sword of the Divine"]; ok {
		t.Error("excludeSeasons should drop an item with no seasons left")
	}
	if it, ok := byName["Seraph's Embrace"]; !ok || it.Seasons.Seasons()[0] != 3 || !it.Seasons.Has(16) || it.Seasons.Has(17) {
		t.Errorf("include %+v %v", it, ok)
	}
	if byName["Long Sword"].Tier != game.TierStarter {
		t.Error("tier override ignored")
	}
	if !slices.IsSortedFunc(c.Items, func(a, b game.Item) int {
		if a.Name < b.Name {
			return -1
		}
		if a.Name > b.Name {
			return 1
		}
		return 0
	}) {
		t.Error("items not sorted")
	}
}

func TestLoadOverrides(t *testing.T) {
	if ov, err := LoadOverrides(t.TempDir() + "/missing.json"); err != nil || len(ov.Items.Exclude) != 0 {
		t.Errorf("missing file: %+v %v", ov, err)
	}
	if _, err := LoadOverrides(""); err != nil {
		t.Errorf("empty path: %v", err)
	}
	bad := writeTemp(t, `{"items":{"tiers":{"Boots":"mythic"}}}`)
	if _, err := LoadOverrides(bad); err == nil {
		t.Error("unknown tier accepted")
	}
	bad = writeTemp(t, `{"items":{"include":[{"name":"X","icon":"i","tier":"boots","seasons":[5,4]}]}}`)
	if _, err := LoadOverrides(bad); err == nil {
		t.Error("reversed include range accepted")
	}
	bad = writeTemp(t, `{not json`)
	if _, err := LoadOverrides(bad); err == nil {
		t.Error("malformed accepted")
	}
	good := writeTemp(t, `{"items":{"exclude":["A"]},"champions":{"seasons":{"Mel":15}}}`)
	ov, err := LoadOverrides(good)
	if err != nil || !ov.Items.excluded("a") || ov.Champions.Seasons["Mel"] != 15 {
		t.Errorf("good file: %+v %v", ov, err)
	}
}

func TestSeasonResolver(t *testing.T) {
	st := &fakeStore{seasons: map[string]int{"Learned": 12}}
	r := newSeasonResolver(ChampionOverrides{Seasons: map[string]int{"Aatrox": 9}}, st, 16, nil)
	if r.season("Aatrox") != 9 {
		t.Error("override should win over the static table")
	}
	if r.season("Ahri") != 1 {
		t.Error("static table")
	}
	if r.season("Learned") != 12 {
		t.Error("store")
	}
	if r.season("Brandnew") != 16 || st.seasons["Brandnew"] != 16 {
		t.Errorf("new champion: %d, stored %v", r.season("Brandnew"), st.seasons)
	}
}
