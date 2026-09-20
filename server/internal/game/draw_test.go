package game

import (
	"math"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"
)

// Port of the old test/draw_roles_test.dart: the draws must be uniform.
const trials = 200_000

// within reports whether count is inside 4 sigma of a binomial with the
// given probability over `trials` draws.
func within(count int, p float64) bool {
	mean := trials * p
	sigma := math.Sqrt(trials * p * (1 - p))
	return math.Abs(float64(count)-mean) <= 4*sigma
}

func TestDrawRolesUniform(t *testing.T) {
	players := []string{"Host", "B", "C", "D", "E"}
	rng := rand.New(rand.NewPCG(42, 0))
	undercover := map[string]int{}
	first := map[string]int{}
	position := map[string][]int{}
	for _, p := range players {
		position[p] = make([]int, len(players))
	}
	for range trials {
		order, uc := DrawRoles(players, rng)
		undercover[uc]++
		first[order[0]]++
		for i, p := range order {
			position[p][i]++
		}
	}
	p := 1.0 / float64(len(players))
	for _, name := range players {
		if !within(undercover[name], p) {
			t.Errorf("%s undercover %d times, expected ~%.0f", name, undercover[name], trials*p)
		}
		if !within(first[name], p) {
			t.Errorf("%s first %d times, expected ~%.0f", name, first[name], trials*p)
		}
		for i, n := range position[name] {
			if !within(n, p) {
				t.Errorf("%s at position %d %d times, expected ~%.0f", name, i, n, trials*p)
			}
		}
	}
}

func TestDrawWordPacks(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(7, 0))

	// Every enabled pack comes up equally often whatever its size.
	all := Filter{Packs: AllPacks}.Normalized(c)
	counts := map[Pack]int{}
	for range trials {
		w, pack, err := DrawWord(all, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		if w.Name == "" {
			t.Fatalf("empty word from %s", pack)
		}
		counts[pack]++
	}
	p := 1.0 / float64(len(AllPacks))
	for _, pack := range AllPacks {
		if !within(counts[pack], p) {
			t.Errorf("%s drawn %d times, expected ~%.0f", pack, counts[pack], trials*p)
		}
	}
	both := DefaultFilter().Normalized(c)
	champions := 0
	for range trials {
		_, pack, err := DrawWord(both, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		if pack == PackChampions {
			champions++
		}
	}
	if !within(champions, 0.5) {
		t.Errorf("champions drawn %d of %d, expected ~50%%", champions, trials)
	}

	// A single pack only ever draws from itself.
	for _, single := range AllPacks {
		f := Filter{Packs: []Pack{single}}.Normalized(c)
		members := c.FilterPack(single, f)
		for range 200 {
			w, pack, err := DrawWord(f, rng, c)
			if err != nil || pack != single {
				t.Fatalf("%s-only drew %+v from %s: %v", single, w, pack, err)
			}
			if !slices.Contains(members, w) {
				t.Fatalf("%s-only drew %+v which is not a member", single, w)
			}
			if single != PackMonsters && w.Icon == "" {
				t.Fatalf("%s drew %+v without icon", single, w)
			}
		}
	}
}

func TestDrawWordRespectsFilter(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(11, 0))

	f := Filter{Packs: []Pack{PackChampions, PackItems, PackAbilities}, ChampSeasons: [2]int{1, 7}, ChampRegions: []string{"Ionia", "Targon"}, ItemSeasons: [2]int{3, 4}, ItemTiers: []Tier{TierLegendary}}.Normalized(c)
	seen := map[string]bool{}
	for range 3000 {
		w, pack, err := DrawWord(f, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		seen[w.Name] = true
		switch pack {
		case PackChampions:
			if w.Name != "Ahri" && w.Name != "Zoe" {
				t.Fatalf("champion outside filter: %s", w.Name)
			}
		case PackItems:
			if w.Name != "Deathfire Grasp" && w.Name != "Infinity Edge" {
				t.Fatalf("item outside filter: %s", w.Name)
			}
		case PackAbilities:
			if w.Name != "Charm (Ahri)" && w.Name != "Spirit Rush (Ahri)" && w.Name != "Paddle Star (Zoe)" {
				t.Fatalf("ability outside filter: %s", w.Name)
			}
		default:
			t.Fatalf("drew from %s", pack)
		}
	}
	if len(seen) != 7 {
		t.Errorf("expected all 7 matching words to show up, saw %v", seen)
	}
}

func TestDrawWordEmptyPack(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(11, 0))
	// An enabled pack with nothing in it is refused, not silently skipped,
	// and the error names the pack.
	cases := []struct {
		name string
		f    Filter
		pack string
	}{
		{"champion seasons", Filter{Packs: AllPacks, ChampSeasons: [2]int{2, 2}}, "champions"},
		{"item tiers", Filter{Packs: AllPacks, ItemTiers: []Tier{}}, "items"},
		{"abilities through class", Filter{Packs: []Pack{PackAbilities}, ChampClasses: []string{"Fighter"}}, "abilities"},
		{"missing pack in an old catalog", Filter{Packs: []Pack{PackChampions, PackSkinLines}}, "skin lines"},
		{"no packs", Filter{}, "word pack"},
	}
	for _, tc := range cases {
		cat := c
		if tc.name == "missing pack in an old catalog" {
			cat = &Catalog{Champions: c.Champions}
		}
		f := tc.f
		if tc.name == "no packs" {
			f.Packs = []Pack{} // Normalized would fill nil with the default
		} else {
			f = f.Normalized(cat)
		}
		_, _, err := DrawWord(f, rng, cat)
		if errCode(err) != "invalid" || !strings.Contains(err.Error(), tc.pack) {
			t.Errorf("%s: %v", tc.name, err)
		}
	}
}

func TestDrawWordUniformWithinPack(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(9, 0))
	f := Filter{Packs: []Pack{PackChampions}}.Normalized(c)
	counts := map[string]int{}
	for range trials {
		w, _, err := DrawWord(f, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		counts[w.Name]++
	}
	p := 1.0 / float64(len(c.Champions))
	for _, ch := range c.Champions {
		if !within(counts[ch.Name], p) {
			t.Errorf("%s drawn %d times, expected ~%.0f", ch.Name, counts[ch.Name], trials*p)
		}
	}
}
