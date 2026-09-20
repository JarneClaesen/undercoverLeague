package catalog

import (
	"encoding/json"
	"slices"
	"strings"
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
 "1028": {"name":"Ruby Crystal","gold":{"total":400,"purchasable":true},"tags":["Health"],"into":["3067"],"maps":{"11":true}},
 "3067": {"name":"Kindlegem","gold":{"total":800,"purchasable":true},"tags":["Health"],"from":["1028"],"into":["3084"],"maps":{"11":true}},
 "3084": {"name":"Heartsteel","gold":{"total":3000,"purchasable":true},"tags":["Health"],"from":["3067"],"maps":{"11":true}},
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
	want := []string{"Archangel's Staff", "Armored Advance", "Blade of The Ruined King", "Boots", "Dark Seal", "Doran's Blade", "Health Potion", "Heartsteel", "Infinity Edge", "Kindlegem", "Long Sword", "Ruby Crystal", "Stealth Ward"}
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
		"Ruby Crystal": game.TierComponent, "Heartsteel": game.TierLegendary,
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
		// Recipes are resolved to names; ids the file lacks are dropped.
		switch it.Name {
		case "Kindlegem":
			if !slices.Equal(it.From, []string{"Ruby Crystal"}) || !slices.Equal(it.Into, []string{"Heartsteel"}) || it.Gold != 800 {
				t.Errorf("Kindlegem %+v", it)
			}
		case "Archangel's Staff":
			if len(it.From) != 0 || !slices.Equal(it.Into, []string{"Seraph's Embrace"}) {
				t.Errorf("Archangel's %+v", it)
			}
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

// championsFull is a trimmed championFull.json: tags, partype, info,
// stats, spells, passive and skins in the shapes the importer reads. Skin
// names cover the forms the line heuristic must handle; info and stats are
// the real values of patch 16.18 (Newbie's zeros are what Riot ships for
// Akshan, Rell, Seraphine and Vex).
const championsFull = `{"data":{
 "Ahri":{"id":"Ahri","name":"Ahri","tags":["Mage","Assassin"],"partype":"Mana",
   "info":{"attack":3,"defense":4,"magic":8,"difficulty":5},"stats":{"attackrange":550},
   "passive":{"name":"Essence Theft","image":{"full":"Ahri_SoulEater2.png"}},
   "spells":[{"name":"Orb of Deception","image":{"full":"AhriQ.png"}},{"name":"Fox-Fire","image":{"full":"AhriW.png"}},{"name":"Charm","image":{"full":"AhriE.png"}},{"name":"Spirit Rush","image":{"full":"AhriR.png"}}],
   "skins":[{"num":0,"name":"default"},{"num":1,"name":"Dynasty Ahri"},{"num":4,"name":"Star Guardian Ahri"},{"num":7,"name":"K/DA Ahri"},{"num":8,"name":"Prestige K/DA Ahri"},{"num":9,"name":"K/DA Ahri (2022)"},{"num":10,"name":"Ahri Snow Day"},{"num":11,"name":"Ahri's Fox Party"}]},
 "MonkeyKing":{"id":"MonkeyKing","name":"Wukong","tags":["Fighter","Tank"],"partype":"Mana",
   "info":{"attack":8,"defense":5,"magic":2,"difficulty":3},"stats":{"attackrange":175},
   "passive":{"name":"Stone Skin","image":{"full":"MonkeyKingStoneSkin.png"}},
   "spells":[{"name":"Crushing Blow","image":{"full":"MonkeyKingDoubleAttack.png"}},{"name":"Warrior Trickster","image":{"full":"MonkeyKingDecoy.png"}},{"name":"Nimbus Strike","image":{"full":"MonkeyKingNimbus.png"}},{"name":"Cyclone","image":{"full":"MonkeyKingSpinToWin.png"}}],
   "skins":[{"num":0,"name":"default"},{"num":3,"name":"Star Guardian Wukong"},{"num":6,"name":"Wukong Snow Day (Ruby)"},{"num":8,"name":"Radiant Wukong"}]},
 "MasterYi":{"id":"MasterYi","name":"Master Yi","tags":["Assassin","Fighter"],"partype":"Mana",
   "info":{"attack":10,"defense":4,"magic":2,"difficulty":4},"stats":{"attackrange":125},
   "passive":{"name":"Double Strike","image":{"full":"MasterYi_Passive1.png"}},
   "spells":[{"name":"Alpha Strike","image":{"full":"AlphaStrike.png"}},{"name":"Meditate","image":{"full":"Meditate.png"}},{"name":"Wuju Style","image":{"full":"WujuStyle.png"}},{"name":"Highlander","image":{"full":"Highlander.png"}}],
   "skins":[{"num":0,"name":"default"},{"num":5,"name":"PROJECT: Yi"},{"num":9,"name":"Snow Man Yi"},{"num":12,"name":"K/DA Master Yi"}]},
 "Blitzcrank":{"id":"Blitzcrank","name":"Blitzcrank","tags":["Tank","Support"],"partype":"Mana",
   "info":{"attack":4,"defense":8,"magic":5,"difficulty":4},"stats":{"attackrange":125},
   "passive":{"name":"Mana Barrier","image":{"full":"Blitzcrank_ManaBarrier.png"}},
   "spells":[{"name":"Rocket Grab","image":{"full":"RocketGrab.png"}},{"name":"Overdrive","image":{"full":"Overdrive.png"}},{"name":"Power Fist","image":{"full":"PowerFist.png"}},{"name":"Static Field","image":{"full":"StaticField.png"}}],
   "skins":[{"num":0,"name":"default"},{"num":2,"name":"Beezcrank"},{"num":3,"name":"PROJECT: Blitzcrank"},{"num":4,"name":"Blitzcrank"}]},
 "Newbie":{"id":"Newbie","name":"Newbie","tags":["Marksman"],"partype":"Blood Well","info":{"attack":0,"defense":0,"magic":0,"difficulty":0},"stats":{"attackrange":300},"passive":{"name":"","image":{"full":""}},"spells":[],"skins":[{"num":0,"name":"default"}]},
 "Broken":{"id":"","name":"x","tags":[],"skins":[]}
}}`

const summonerSpells = `{"data":{
 "SummonerFlash":{"name":"Flash","modes":["ARAM","CLASSIC","URF"],"image":{"full":"SummonerFlash.png"}},
 "SummonerFlash_Jade":{"name":"Flash","modes":["KIWI"],"image":{"full":"SummonerFlash_Jade.png"}},
 "SummonerDot":{"name":"Ignite","modes":["CLASSIC"],"image":{"full":"SummonerDot.png"}},
 "SummonerSnowball":{"name":"Mark","modes":["ARAM"],"image":{"full":"SummonerSnowball.png"}},
 "SummonerSmite":{"name":"Smite","modes":["CLASSIC"],"image":{"full":"SummonerSmite.png"}}
}}`

const runesReforged = `[
 {"id":8000,"key":"Precision","name":"Precision","icon":"perk-images/Styles/7201_Precision.png","slots":[
   {"runes":[{"name":"Press the Attack","icon":"perk-images/Styles/Precision/PressTheAttack/PressTheAttack.png"},{"name":"Conqueror","icon":"perk-images/Styles/Precision/Conqueror/Conqueror.png"}]},
   {"runes":[{"name":"Triumph","icon":"perk-images/Styles/Precision/Triumph.png"}]},
   {"runes":[{"name":"Legend: Alacrity","icon":"perk-images/Styles/Precision/LegendAlacrity/LegendAlacrity.png"}]}]},
 {"id":8100,"key":"Domination","name":"Domination","icon":"perk-images/Styles/7200_Domination.png","slots":[
   {"runes":[{"name":"Electrocute","icon":"perk-images/Styles/Domination/Electrocute/Electrocute.png"}]},
   {"runes":[{"name":"Cheap Shot","icon":"perk-images/Styles/Domination/CheapShot/CheapShot.png"},{"name":"","icon":"x.png"}]}]}
]`

func rawChampionsFull(t *testing.T) map[string]rawChampionFull {
	t.Helper()
	var body struct {
		Data map[string]rawChampionFull `json:"data"`
	}
	if err := json.Unmarshal([]byte(championsFull), &body); err != nil {
		t.Fatal(err)
	}
	return body.Data
}

func entryNames(entries []game.Entry) []string {
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.Name
	}
	return out
}

func champNames(champs []game.Champion) []string {
	out := make([]string, len(champs))
	for i, ch := range champs {
		out[i] = ch.Name
	}
	return out
}

func testSeason(id string) int {
	return map[string]int{"MonkeyKing": 1, "Ahri": 1, "MasterYi": 1, "Blitzcrank": 1}[id]
}

func TestImportChampions(t *testing.T) {
	got := importChampions("https://dd", rawChampionsFull(t), testSeason, ChampionOverrides{Regions: map[string]string{"newbie": "Void"}}.region)
	if !slices.Equal(champNames(got), []string{"Ahri", "Blitzcrank", "Master Yi", "Newbie", "Wukong"}) {
		t.Fatalf("got %v", champNames(got))
	}
	wukong := got[4]
	if wukong.Icon != "https://dd/cdn/img/champion/loading/MonkeyKing_0.jpg" || wukong.Season != 1 || wukong.ID != "MonkeyKing" {
		t.Errorf("Wukong %+v", wukong)
	}
	if !slices.Equal(wukong.Tags, []string{"Fighter", "Tank"}) || wukong.Region != "Ionia" {
		t.Errorf("Wukong tags/region %+v", wukong)
	}
	// Regions: static table, override for an id the table lacks.
	if got[0].Region != "Ionia" || got[3].Region != "Void" || got[3].Season != 0 {
		t.Errorf("regions %+v %+v", got[0], got[3])
	}
	// Buckets from partype, info and stats.
	ahri, newbie := got[0], got[3]
	if ahri.Range != game.RangeRanged || ahri.Resource != game.ResourceMana || ahri.Damage != game.DamageMagic || ahri.Difficulty != game.DifficultyMedium {
		t.Errorf("Ahri buckets %+v", ahri)
	}
	if wukong.Range != game.RangeMelee || wukong.Resource != game.ResourceMana || wukong.Damage != game.DamagePhysical || wukong.Difficulty != game.DifficultyEasy {
		t.Errorf("Wukong buckets %+v", wukong)
	}
	// 300 is the shortest ranged range; a Blood Well is "other"; all-zero
	// ratings leave damage and difficulty unknown.
	if newbie.Range != game.RangeRanged || newbie.Resource != game.ResourceOther || newbie.Damage != "" || newbie.Difficulty != "" {
		t.Errorf("Newbie buckets %+v", newbie)
	}
}

// TestClassifyChampion pins the bucket rules against real patch 16.18
// ratings so the thresholds stay sane when they are tuned.
func TestClassifyChampion(t *testing.T) {
	champ := func(partype string, attack, magic, difficulty int, attackRange float64) rawChampionFull {
		return rawChampionFull{Partype: partype, Info: rawInfo{Attack: attack, Magic: magic, Difficulty: difficulty}, Stats: rawStats{AttackRange: attackRange}}
	}
	cases := []struct {
		name                              string
		in                                rawChampionFull
		rng, resource, damage, difficulty string
	}{
		{"Riven", champ("None", 8, 1, 8, 125), "melee", "none", "physical", "hard"},
		{"Ahri", champ("Mana", 3, 8, 5, 550), "ranged", "mana", "magic", "medium"},
		{"Jax", champ("Mana", 7, 7, 5, 125), "melee", "mana", "mixed", "medium"},
		{"Zed", champ("Energy", 9, 1, 7, 125), "melee", "energy", "physical", "hard"},
		{"Lux", champ("Mana", 2, 9, 5, 550), "ranged", "mana", "magic", "medium"},
		{"Garen", champ("None", 7, 1, 5, 175), "melee", "none", "physical", "medium"},
		{"Kayle", champ("Mana", 6, 7, 7, 175), "melee", "mana", "mixed", "hard"},
		{"Corki", champ("Mana", 8, 6, 6, 550), "ranged", "mana", "mixed", "medium"},
		{"Kai'Sa (lean of exactly 5)", champ("Mana", 8, 3, 6, 525), "ranged", "mana", "physical", "medium"},
		{"Amumu (lean of exactly -6)", champ("Mana", 2, 8, 3, 125), "melee", "mana", "magic", "easy"},
		{"Katarina", champ("None", 4, 9, 8, 125), "melee", "none", "magic", "hard"},
		{"Bel'Veth (empty partype)", champ("", 4, 7, 10, 150), "melee", "none", "magic", "hard"},
		{"Tryndamere", champ("Fury", 10, 2, 5, 175), "melee", "other", "physical", "medium"},
		{"Gnar", champ("Rage", 6, 5, 8, 175), "melee", "other", "mixed", "hard"},
		{"Yasuo", champ("Flow", 8, 4, 10, 175), "melee", "other", "physical", "hard"},
		{"Rakan (300 is ranged)", champ("Mana", 2, 8, 5, 300), "ranged", "mana", "magic", "medium"},
		{"Nilah (225 is melee)", champ("Mana", 9, 2, 8, 225), "melee", "mana", "physical", "hard"},
		{"Rell (no ratings)", champ("Mana", 0, 0, 0, 175), "melee", "mana", "", ""},
		{"lean of 2 is mixed", champ("mana", 6, 4, 6, 125), "melee", "mana", "mixed", "medium"},
		{"lean of 3 is physical", champ("MANA", 6, 3, 3, 125), "melee", "mana", "physical", "easy"},
		{"difficulty 1 and 10", champ("Mana", 5, 5, 1, 125), "melee", "mana", "mixed", "easy"},
		{"difficulty 10", champ("Mana", 5, 5, 10, 125), "melee", "mana", "mixed", "hard"},
		{"difficulty 7", champ("Mana", 5, 5, 7, 125), "melee", "mana", "mixed", "hard"},
	}
	for _, tc := range cases {
		rng, resource, damage, difficulty := classifyChampion(tc.in)
		if rng != tc.rng || resource != tc.resource || damage != tc.damage || difficulty != tc.difficulty {
			t.Errorf("%s: got %s/%s/%s/%s, want %s/%s/%s/%s", tc.name, rng, resource, damage, difficulty, tc.rng, tc.resource, tc.damage, tc.difficulty)
		}
		if (rng != "" && !game.ValidRange(rng)) || !game.ValidResource(resource) || (damage != "" && !game.ValidDamage(damage)) || (difficulty != "" && !game.ValidDifficulty(difficulty)) {
			t.Errorf("%s: bucket outside the enums: %s/%s/%s/%s", tc.name, rng, resource, damage, difficulty)
		}
	}
}

func TestImportAbilities(t *testing.T) {
	raw := rawChampionsFull(t)
	champs := importChampions("https://dd", raw, testSeason, ChampionOverrides{}.region)
	got := importAbilities("https://dd", "16.18.1", raw, champs)
	byName := map[string]game.Entry{}
	for _, e := range got {
		byName[e.Name] = e
	}
	if len(got) != 20 {
		t.Errorf("got %d abilities: %v", len(got), entryNames(got))
	}
	charm := byName["Charm (Ahri)"]
	if charm.Icon != "https://dd/cdn/16.18.1/img/spell/AhriE.png" || charm.Group != "Ahri" || charm.Champion != "Ahri" || charm.Season != 1 {
		t.Errorf("Charm %+v", charm)
	}
	passive := byName["Stone Skin (Wukong)"]
	if passive.Icon != "https://dd/cdn/16.18.1/img/passive/MonkeyKingStoneSkin.png" || passive.Champion != "Wukong" {
		t.Errorf("passive %+v", passive)
	}
	if _, ok := byName["Double Strike (Master Yi)"]; !ok {
		t.Error("multi-word champion name")
	}
	// A champion without spells contributes nothing, and neither does one
	// that is not in champs.
	for n := range byName {
		if strings.Contains(n, "Newbie") {
			t.Errorf("unexpected %s", n)
		}
	}
	if got := importAbilities("https://dd", "16.18.1", raw, champs[:1]); len(got) != 5 {
		t.Errorf("abilities for Ahri only: %v", entryNames(got))
	}
	if !slices.IsSorted(entryNames(got)) {
		t.Error("abilities not sorted")
	}
}

func TestImportSkinLines(t *testing.T) {
	got := importSkinLines("https://dd", rawChampionsFull(t))
	// Star Guardian: Ahri + Wukong. K/DA: Ahri (prestige and 2022 fold into
	// one skin) + Master Yi. Snow Day: "Ahri Snow Day" + "Wukong Snow Day
	// (Ruby)". PROJECT: "PROJECT: Yi" + "PROJECT: Blitzcrank". Dynasty,
	// Radiant, Snow Man, Fox Party have one skin; Beezcrank has no line.
	want := []string{"K/DA", "PROJECT", "Snow Day", "Star Guardian"}
	if !slices.Equal(entryNames(got), want) {
		t.Fatalf("got %v, want %v", entryNames(got), want)
	}
	// The icon is the splash of the first skin in champion-name order.
	icons := map[string]string{}
	for _, e := range got {
		icons[e.Name] = e.Icon
	}
	if icons["Star Guardian"] != "https://dd/cdn/img/champion/splash/Ahri_4.jpg" {
		t.Errorf("Star Guardian icon %s", icons["Star Guardian"])
	}
	if icons["PROJECT"] != "https://dd/cdn/img/champion/splash/Blitzcrank_3.jpg" {
		t.Errorf("PROJECT icon %s", icons["PROJECT"])
	}

	cases := map[string]string{
		"PROJECT: Ahri":             "PROJECT",
		"Star Guardian Ahri":        "Star Guardian",
		"Ahri Star Guardian":        "Star Guardian",
		"K/DA ALL OUT Ahri":         "K/DA ALL OUT",
		"Ahri's Fox Party":          "Fox Party",
		"Prestige K/DA Ahri":        "K/DA",
		"Prestige K/DA Ahri (2022)": "K/DA",
		"Ahri":                      "",
		"Ahri (Ruby)":               "",
		"Ahriman":                   "",
	}
	cutters := nameCutters("Ahri")
	for skin, want := range cases {
		name := skinPrefixRE.ReplaceAllString(skinSuffixRE.ReplaceAllString(skin, ""), "")
		rest, _ := cutName(name, cutters)
		if rest != want {
			t.Errorf("%q: got %q, want %q", skin, rest, want)
		}
	}
	for skin, want := range map[string]string{"PROJECT: Yi": "PROJECT", "Snow Man Yi": "Snow Man", "K/DA Master Yi": "K/DA", "Master Chef Tahm Kench": "Chef Tahm Kench"} {
		// "Master Chef" is the price of the first-word fallback; it only
		// applies when neither the full name nor the last word matched, and
		// the real data has no such skin.
		if rest, _ := cutName(skin, nameCutters("Master Yi")); rest != want {
			t.Errorf("%q: got %q, want %q", skin, rest, want)
		}
	}
	if rest, ok := cutName("Corporate Mundo", nameCutters("Dr. Mundo")); !ok || rest != "Corporate" {
		t.Errorf("Dr. Mundo: %q %v", rest, ok)
	}
	if rest, ok := cutName("Nunu & Willump Bot", nameCutters("Nunu & Willump")); !ok || rest != "Bot" {
		t.Errorf("Nunu: %q %v", rest, ok)
	}
	if rest, ok := cutName("Pug'Maw", nameCutters("Kog'Maw")); ok || rest != "" {
		t.Errorf("pun skin: %q %v", rest, ok)
	}
}

func TestImportSpellsAndRunes(t *testing.T) {
	var body struct {
		Data map[string]rawSpell `json:"data"`
	}
	if err := json.Unmarshal([]byte(summonerSpells), &body); err != nil {
		t.Fatal(err)
	}
	spells := importSpells("https://dd", "16.18.1", body.Data)
	if !slices.Equal(entryNames(spells), []string{"Flash", "Ignite", "Smite"}) {
		t.Errorf("spells %v", entryNames(spells))
	}
	if spells[0].Icon != "https://dd/cdn/16.18.1/img/spell/SummonerFlash.png" || spells[0].Group != "" {
		t.Errorf("Flash %+v", spells[0])
	}

	var trees []rawRuneTree
	if err := json.Unmarshal([]byte(runesReforged), &trees); err != nil {
		t.Fatal(err)
	}
	runes := importRunes("https://dd", trees)
	if !slices.Equal(entryNames(runes), []string{"Cheap Shot", "Conqueror", "Electrocute", "Legend: Alacrity", "Press the Attack", "Triumph"}) {
		t.Errorf("runes %v", entryNames(runes))
	}
	groups := map[string]string{}
	for _, r := range runes {
		groups[r.Name] = r.Group
	}
	if groups["Conqueror"] != "Precision/keystone" || groups["Triumph"] != "Precision/1" || groups["Legend: Alacrity"] != "Precision/2" || groups["Cheap Shot"] != "Domination/1" {
		t.Errorf("groups %v", groups)
	}
	if runes[1].Icon != "https://dd/cdn/img/perk-images/Styles/Precision/Conqueror/Conqueror.png" {
		t.Errorf("Conqueror icon %s", runes[1].Icon)
	}
}

func TestMonsters(t *testing.T) {
	m := Monsters()
	if len(m) < 20 {
		t.Errorf("only %d monsters", len(m))
	}
	seen := map[string]bool{}
	groups := map[string]bool{}
	for _, e := range m {
		if e.Name == "" || seen[e.Name] || e.Icon != "" {
			t.Errorf("monster %+v", e)
		}
		seen[e.Name] = true
		groups[e.Group] = true
	}
	for _, g := range []string{"epic", "drake", "camp", "lane"} {
		if !groups[g] {
			t.Errorf("no %s monsters", g)
		}
	}
	m[0].Name = "changed"
	if Monsters()[0].Name == "changed" {
		t.Error("Monsters returned the shared slice")
	}
}

func TestBuild(t *testing.T) {
	snaps := map[int][]snapItem{
		3:  importItems("https://dd", "3.15.5", rawItems(t, items3)),
		16: importItems("https://dd", "16.18.1", rawItems(t, items16)),
	}
	champs := []game.Champion{{Name: "Ahri", Icon: "a", Season: 1}, {Name: "Wukong", Icon: "w", Season: 1}}
	packs := Packs{
		Spells:    []game.Entry{{Name: "Flash"}},
		Runes:     []game.Entry{{Name: "Conqueror", Group: "Precision/keystone"}},
		Abilities: []game.Entry{{Name: "Cyclone (Wukong)", Champion: "Wukong"}, {Name: "Charm (Ahri)", Champion: "Ahri"}},
		SkinLines: []game.Entry{{Name: "PROJECT"}, {Name: "Count"}},
		Monsters:  Monsters(),
	}
	ov := Overrides{
		Items: ItemOverrides{
			Exclude:        []string{" health potion "},
			ExcludeSeasons: map[string][]int{"Sword of the Divine": {3}},
			Include:        []IncludedItem{{Name: "Seraph's Embrace", Icon: "https://dd/3040.png", Tier: game.TierLegendary, Seasons: [2]int{3, 16}}},
			Tiers:          map[string]game.Tier{"long sword": game.TierStarter},
		},
		Champions: ChampionOverrides{Exclude: []string{"wukong"}},
		SkinLines: SkinLineOverrides{Exclude: []string{"count"}},
	}
	c := Build("16.18.1", snaps, champs, packs, ov)

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
	// Removed item keeps the icon (and price) of its last season.
	if it := byName["Deathfire Grasp"]; !it.Seasons.Has(3) || it.Seasons.Has(16) || it.Icon != "https://dd/cdn/3.15.5/img/item/3128.png" || it.Gold != 3100 {
		t.Errorf("DFG %+v", it)
	}
	// Recipes and prices follow the newest season.
	if it := byName["Kindlegem"]; it.Gold != 800 || !slices.Equal(it.Into, []string{"Heartsteel"}) || !slices.Equal(it.From, []string{"Ruby Crystal"}) {
		t.Errorf("Kindlegem %+v", it)
	}
	if it := byName["Boots"]; it.Gold != 300 {
		t.Errorf("Boots (renamed from Boots of Speed, 325g in S3) %+v", it)
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
	// The other packs come through, minus the excluded champion's
	// abilities and the excluded skin line.
	if !slices.Equal(entryNames(c.Abilities), []string{"Charm (Ahri)"}) {
		t.Errorf("abilities %v", entryNames(c.Abilities))
	}
	if !slices.Equal(entryNames(c.SkinLines), []string{"PROJECT"}) {
		t.Errorf("skin lines %v", entryNames(c.SkinLines))
	}
	if len(c.Spells) != 1 || len(c.Runes) != 1 || len(c.Monsters) != len(monsters) {
		t.Errorf("packs %d %d %d", len(c.Spells), len(c.Runes), len(c.Monsters))
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
	bad = writeTemp(t, `{"champions":{"regions":{"Zaahen":"Camavor"}}}`)
	if _, err := LoadOverrides(bad); err == nil {
		t.Error("unknown region accepted")
	}
	good := writeTemp(t, `{"items":{"exclude":["A"]},"champions":{"seasons":{"Mel":15},"regions":{"Zaahen":"Shurima"}},"skinLines":{"exclude":["Count"]}}`)
	ov, err := LoadOverrides(good)
	if err != nil || !ov.Items.excluded("a") || ov.Champions.Seasons["Mel"] != 15 || !ov.SkinLines.excluded("count") {
		t.Errorf("good file: %+v %v", ov, err)
	}
	if ov.Champions.region("zaahen") != "Shurima" || ov.Champions.region("Ahri") != "Ionia" || ov.Champions.region("Nobody") != "" {
		t.Errorf("region resolution %+v", ov.Champions)
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
