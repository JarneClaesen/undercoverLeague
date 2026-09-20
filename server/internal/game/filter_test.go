package game

import (
	"encoding/json"
	"slices"
	"testing"
)

func TestFilterValidate(t *testing.T) {
	items := []Pack{PackItems}
	cases := []struct {
		name string
		f    Filter
		code string
	}{
		{"default", DefaultFilter(), ""},
		{"all packs", Filter{Packs: AllPacks}, ""},
		{"no packs", Filter{}, "invalid"},
		{"empty packs", Filter{Packs: []Pack{}}, "invalid"},
		{"unknown pack", Filter{Packs: []Pack{"emotes"}}, "invalid"},
		{"reversed range", Filter{Packs: items, ItemSeasons: [2]int{10, 3}}, "invalid"},
		{"negative", Filter{Packs: items, ChampSeasons: [2]int{-1, 0}}, "invalid"},
		{"unknown tier", Filter{Packs: items, ItemTiers: []Tier{"mythic"}}, "invalid"},
		{"half-open range is fine", Filter{Packs: items, ItemSeasons: [2]int{0, 5}}, ""},
		{"classes", Filter{Packs: items, ChampClasses: []string{"Mage", "tank"}}, ""},
		{"unknown class", Filter{Packs: items, ChampClasses: []string{"Bruiser"}}, "invalid"},
		{"regions", Filter{Packs: items, ChampRegions: []string{"Shadow Isles", "void"}}, ""},
		{"unknown region", Filter{Packs: items, ChampRegions: []string{"Camavor"}}, "invalid"},
	}
	for _, tc := range cases {
		if got := errCode(tc.f.Validate()); got != tc.code {
			t.Errorf("%s: got %q, want %q", tc.name, got, tc.code)
		}
	}
}

func TestFilterNormalized(t *testing.T) {
	c := testCatalog()

	n := DefaultFilter().Normalized(c)
	if n.ChampSeasons != [2]int{1, 16} || n.ItemSeasons != [2]int{3, 16} {
		t.Errorf("zero bounds not filled: %+v", n)
	}
	if !slices.Equal(n.ItemTiers, AllTiers) {
		t.Errorf("nil tiers should mean all, got %v", n.ItemTiers)
	}
	if n.ChampClasses == nil || len(n.ChampClasses) != 0 || n.ChampRegions == nil || len(n.ChampRegions) != 0 {
		t.Errorf("nil classes/regions should become empty lists: %+v", n)
	}

	// Out-of-range and half-open bounds are clamped, not rejected.
	n = Filter{Packs: []Pack{PackItems}, ChampSeasons: [2]int{0, 40}, ItemSeasons: [2]int{1, 0}}.Normalized(c)
	if n.ChampSeasons != [2]int{1, 16} || n.ItemSeasons != [2]int{3, 16} {
		t.Errorf("clamp: %+v", n)
	}
	n = Filter{Packs: []Pack{PackItems}, ItemSeasons: [2]int{20, 25}}.Normalized(c)
	if n.ItemSeasons != [2]int{16, 16} {
		t.Errorf("clamp above: %+v", n.ItemSeasons)
	}

	// Tiers are deduped, ordered like AllTiers, and unknown ones dropped.
	n = Filter{Packs: []Pack{PackItems}, ItemTiers: []Tier{TierLegendary, TierBoots, TierLegendary, "x"}}.Normalized(c)
	if !slices.Equal(n.ItemTiers, []Tier{TierBoots, TierLegendary}) {
		t.Errorf("tiers %v", n.ItemTiers)
	}
	n = Filter{Packs: []Pack{PackItems}, ItemTiers: []Tier{}}.Normalized(c)
	if n.ItemTiers == nil || len(n.ItemTiers) != 0 {
		t.Errorf("empty tiers should stay empty, got %v", n.ItemTiers)
	}

	// Packs likewise; nil packs (old row) become the default.
	n = Filter{Packs: []Pack{PackMonsters, PackChampions, PackMonsters, "x"}}.Normalized(c)
	if !slices.Equal(n.Packs, []Pack{PackChampions, PackMonsters}) {
		t.Errorf("packs %v", n.Packs)
	}
	if n = (Filter{}).Normalized(c); !slices.Equal(n.Packs, []Pack{PackChampions, PackItems}) {
		t.Errorf("nil packs %v", n.Packs)
	}
	if n = (Filter{Packs: []Pack{}}).Normalized(c); n.Packs == nil || len(n.Packs) != 0 {
		t.Errorf("empty packs should stay empty (Validate rejects them), got %v", n.Packs)
	}

	// Classes and regions are deduped, spelled canonically and ordered.
	n = Filter{Packs: AllPacks, ChampClasses: []string{"tank", "Mage", "MAGE", "x"}, ChampRegions: []string{"zaun", "Ionia", "shadow isles", "Ionia"}}.Normalized(c)
	if !slices.Equal(n.ChampClasses, []string{"Mage", "Tank"}) || !slices.Equal(n.ChampRegions, []string{"Ionia", "Shadow Isles", "Zaun"}) {
		t.Errorf("classes %v regions %v", n.ChampClasses, n.ChampRegions)
	}

	// Without a catalog nothing can be filled in but nothing breaks either.
	n = DefaultFilter().Normalized(nil)
	if n.ChampSeasons != [2]int{0, 0} || len(n.ItemTiers) != len(AllTiers) {
		t.Errorf("nil catalog: %+v", n)
	}
}

func TestFilterJSON(t *testing.T) {
	// The wire shape is a contract with lib/models/game_settings.dart.
	b, err := json.Marshal(DefaultFilter().Normalized(testCatalog()))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"packs":["champions","items"],"champSeasons":[1,16],"itemSeasons":[3,16],"itemTiers":["starter","consumable","boots","component","legendary"],"champClasses":[],"champRegions":[]}`
	if string(b) != want {
		t.Errorf("got  %s\nwant %s", b, want)
	}

	cases := []struct {
		name  string
		src   string
		packs []Pack
	}{
		{"current shape", `{"packs":["runes","champions"],"champSeasons":[15,16]}`, []Pack{PackRunes, PackChampions}},
		{"legacy both", `{"useChampions":true,"useItems":true,"champSeasons":[15,16]}`, []Pack{PackChampions, PackItems}},
		{"legacy champions only", `{"useChampions":true,"useItems":false,"champSeasons":[15,16]}`, []Pack{PackChampions}},
		{"legacy items only", `{"useItems":true}`, []Pack{PackItems}},
		{"legacy both off", `{"useChampions":false,"useItems":false}`, []Pack{}},
		{"packs win over legacy", `{"packs":["spells"],"useChampions":true,"useItems":true}`, []Pack{PackSpells}},
		{"explicit empty packs stay empty", `{"packs":[],"useChampions":true}`, []Pack{}},
		{"row from before filters", `{}`, nil},
		{"null packs without legacy", `{"packs":null}`, nil},
	}
	for _, tc := range cases {
		var f Filter
		if err := json.Unmarshal([]byte(tc.src), &f); err != nil {
			t.Fatalf("%s: %v", tc.name, err)
		}
		if (f.Packs == nil) != (tc.packs == nil) || !slices.Equal(f.Packs, tc.packs) {
			t.Errorf("%s: packs %#v, want %#v", tc.name, f.Packs, tc.packs)
		}
		if tc.name == "legacy champions only" && (f.ItemTiers != nil || f.ItemSeasons != [2]int{0, 0} || f.ChampSeasons != [2]int{15, 16}) {
			t.Errorf("partial filter parsed as %+v", f)
		}
	}
	// Legacy keys never come back out.
	var f Filter
	json.Unmarshal([]byte(`{"useChampions":true,"useItems":false}`), &f)
	if b, _ := json.Marshal(f); string(b) != `{"packs":["champions"],"champSeasons":[0,0],"itemSeasons":[0,0],"itemTiers":null,"champClasses":null,"champRegions":null}` {
		t.Errorf("legacy round trip: %s", b)
	}
	if err := json.Unmarshal([]byte(`{"packs":"champions"}`), &f); err == nil {
		t.Error("malformed packs accepted")
	}
}
