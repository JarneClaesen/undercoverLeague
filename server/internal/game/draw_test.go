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
	words := LoadWords()
	rng := rand.New(rand.NewPCG(7, 0))

	champions := 0
	for range trials {
		if _, isChampion := DrawWord(true, true, rng, words); isChampion {
			champions++
		}
	}
	if !within(champions, 0.5) {
		t.Errorf("champions drawn %d of %d, expected ~50%%", champions, trials)
	}

	for range 1000 {
		if w, isChampion := DrawWord(true, false, rng, words); !isChampion || w.Icon[:17] != "assets/champions/" {
			t.Fatalf("champions-only drew %+v", w)
		}
		if w, isChampion := DrawWord(false, true, rng, words); isChampion || w.Icon[:13] != "assets/items/" {
			t.Fatalf("items-only drew %+v", w)
		}
	}
}

func TestDrawWordUniformWithinCategory(t *testing.T) {
	words := LoadWords()
	rng := rand.New(rand.NewPCG(9, 0))
	counts := map[string]int{}
	for range trials {
		w, _ := DrawWord(true, false, rng, words)
		counts[w.Name]++
	}
	p := 1.0 / float64(len(words.Champions))
	for _, w := range words.Champions {
		if !within(counts[w.Name], p) {
			t.Errorf("%s drawn %d times, expected ~%.0f", w.Name, counts[w.Name], trials*p)
		}
	}
}
