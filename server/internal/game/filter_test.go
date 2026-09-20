package game

import (
	"encoding/json"
	"slices"
	"testing"
)

func TestFilterValidate(t *testing.T) {
	cases := []struct {
		name string
		f    Filter
		code string
	}{
		{"default", DefaultFilter(), ""},
		{"both off", Filter{}, "invalid"},
		{"reversed range", Filter{UseItems: true, ItemSeasons: [2]int{10, 3}}, "invalid"},
		{"negative", Filter{UseItems: true, ChampSeasons: [2]int{-1, 0}}, "invalid"},
		{"unknown tier", Filter{UseItems: true, ItemTiers: []Tier{"mythic"}}, "invalid"},
		{"half-open range is fine", Filter{UseItems: true, ItemSeasons: [2]int{0, 5}}, ""},
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

	// Out-of-range and half-open bounds are clamped, not rejected.
	n = Filter{UseItems: true, ChampSeasons: [2]int{0, 40}, ItemSeasons: [2]int{1, 0}}.Normalized(c)
	if n.ChampSeasons != [2]int{1, 16} || n.ItemSeasons != [2]int{3, 16} {
		t.Errorf("clamp: %+v", n)
	}
	n = Filter{UseItems: true, ItemSeasons: [2]int{20, 25}}.Normalized(c)
	if n.ItemSeasons != [2]int{16, 16} {
		t.Errorf("clamp above: %+v", n.ItemSeasons)
	}

	// Tiers are deduped, ordered like AllTiers, and unknown ones dropped.
	n = Filter{UseItems: true, ItemTiers: []Tier{TierLegendary, TierBoots, TierLegendary, "x"}}.Normalized(c)
	if !slices.Equal(n.ItemTiers, []Tier{TierBoots, TierLegendary}) {
		t.Errorf("tiers %v", n.ItemTiers)
	}
	n = Filter{UseItems: true, ItemTiers: []Tier{}}.Normalized(c)
	if n.ItemTiers == nil || len(n.ItemTiers) != 0 {
		t.Errorf("empty tiers should stay empty, got %v", n.ItemTiers)
	}

	// Without a catalog nothing can be filled in but nothing breaks either.
	n = DefaultFilter().Normalized(nil)
	if n.ChampSeasons != [2]int{0, 0} || len(n.ItemTiers) != len(AllTiers) {
		t.Errorf("nil catalog: %+v", n)
	}
}

func TestFilterJSON(t *testing.T) {
	// The wire shape is a contract with lib/models/lobby.dart.
	b, err := json.Marshal(DefaultFilter().Normalized(testCatalog()))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"useChampions":true,"useItems":true,"champSeasons":[1,16],"itemSeasons":[3,16],"itemTiers":["starter","consumable","boots","component","legendary"]}`
	if string(b) != want {
		t.Errorf("got  %s\nwant %s", b, want)
	}

	var f Filter
	if err := json.Unmarshal([]byte(`{"useChampions":true,"useItems":false,"champSeasons":[15,16]}`), &f); err != nil {
		t.Fatal(err)
	}
	if f.ItemTiers != nil || f.ItemSeasons != [2]int{0, 0} || f.ChampSeasons != [2]int{15, 16} {
		t.Errorf("partial filter parsed as %+v", f)
	}
}
