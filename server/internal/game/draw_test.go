package game

import (
	"math"
	"math/rand/v2"
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

func TestDrawWordCategories(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(7, 0))
	both := DefaultFilter().Normalized(c)

	champions := 0
	for range trials {
		_, isChampion, err := DrawWord(both, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		if isChampion {
			champions++
		}
	}
	if !within(champions, 0.5) {
		t.Errorf("champions drawn %d of %d, expected ~50%%", champions, trials)
	}

	onlyChampions := Filter{UseChampions: true}.Normalized(c)
	onlyItems := Filter{UseItems: true}.Normalized(c)
	for range 1000 {
		if w, isChampion, err := DrawWord(onlyChampions, rng, c); err != nil || !isChampion || w.Icon == "" {
			t.Fatalf("champions-only drew %+v %v", w, err)
		}
		if w, isChampion, err := DrawWord(onlyItems, rng, c); err != nil || isChampion || w.Icon == "" {
			t.Fatalf("items-only drew %+v %v", w, err)
		}
	}
}

func TestDrawWordRespectsFilter(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(11, 0))

	f := Filter{UseChampions: true, UseItems: true, ChampSeasons: [2]int{15, 16}, ItemSeasons: [2]int{3, 4}, ItemTiers: []Tier{TierLegendary}}.Normalized(c)
	seen := map[string]bool{}
	for range 2000 {
		w, isChampion, err := DrawWord(f, rng, c)
		if err != nil {
			t.Fatal(err)
		}
		seen[w.Name] = true
		if isChampion && w.Name != "Mel" && w.Name != "Yunara" {
			t.Fatalf("champion outside seasons: %s", w.Name)
		}
		if !isChampion && w.Name != "Deathfire Grasp" && w.Name != "Infinity Edge" {
			t.Fatalf("item outside filter: %s", w.Name)
		}
	}
	if len(seen) != 4 {
		t.Errorf("expected all 4 matching words to show up, saw %v", seen)
	}

	// An enabled category with nothing in it is refused, not silently skipped.
	empty := Filter{UseChampions: true, UseItems: true, ChampSeasons: [2]int{2, 2}}.Normalized(c)
	if _, _, err := DrawWord(empty, rng, c); errCode(err) != "invalid" {
		t.Errorf("empty champion pool: %v", err)
	}
	empty = Filter{UseChampions: true, UseItems: true, ItemTiers: []Tier{}}.Normalized(c)
	if _, _, err := DrawWord(empty, rng, c); errCode(err) != "invalid" {
		t.Errorf("empty item pool: %v", err)
	}
}

func TestDrawWordUniformWithinCategory(t *testing.T) {
	c := testCatalog()
	rng := rand.New(rand.NewPCG(9, 0))
	f := Filter{UseChampions: true}.Normalized(c)
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
