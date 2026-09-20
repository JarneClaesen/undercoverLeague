package game

import (
	"math/rand/v2"
	"testing"
)

func TestWordMatches(t *testing.T) {
	cases := []struct {
		target, guess string
		pack          Pack
		want          bool
	}{
		{"Kai'Sa", "kaisa", PackChampions, true},
		{"Kai'Sa", "KAI SA", PackChampions, true},
		{"Kai'Sa", "Kai'Sa", PackChampions, true},
		{"Kai'Sa", "Kayn", PackChampions, false},
		{"Infinity Edge", "infinity edge", PackItems, true},
		{"Infinity Edge", "infinityedge!", PackItems, true},
		{"Infinity Edge", "Infinity", PackItems, false},
		{"Charm (Ahri)", "Charm", PackAbilities, true},
		{"Charm (Ahri)", "charm (ahri)", PackAbilities, true},
		{"Charm (Ahri)", "Charm Ahri", PackAbilities, true},
		{"Charm (Ahri)", "Ahri", PackAbilities, false},
		// The champion shorthand is for abilities only.
		{"Charm (Ahri)", "Charm", PackSpells, false},
		{"Baron Nashor", "", PackMonsters, false},
		{"Baron Nashor", "   ", PackMonsters, false},
		{"Rek'Sai", "REK'SAI", PackChampions, true},
		{"Nunu & Willump", "nunu willump", PackChampions, true},
	}
	for _, tc := range cases {
		if got := WordMatches(tc.target, tc.guess, tc.pack); got != tc.want {
			t.Errorf("WordMatches(%q, %q, %s) = %v, want %v", tc.target, tc.guess, tc.pack, got, tc.want)
		}
	}
}

func TestDrawCastUniform(t *testing.T) {
	players := []string{"Host", "B", "C", "D", "E"}
	rng := rand.New(rand.NewPCG(9, 0))
	undercover := map[string]int{}
	mrWhite := map[string]int{}
	first := map[string]int{}
	for range trials {
		order, roles := DrawCast(players, 1, 1, rng)
		if len(order) != len(players) || len(roles) != len(players) {
			t.Fatalf("cast %v %v", order, roles)
		}
		u, m, c := 0, 0, 0
		for p, r := range roles {
			switch r {
			case RoleUndercover:
				u++
				undercover[p]++
			case RoleMrWhite:
				m++
				mrWhite[p]++
			case RoleCivilian:
				c++
			}
		}
		if u != 1 || m != 1 || c != 3 {
			t.Fatalf("roles %v", roles)
		}
		first[order[0]]++
	}
	p := 1.0 / float64(len(players))
	for _, name := range players {
		if !within(undercover[name], p) {
			t.Errorf("%s undercover %d times, expected ~%.0f", name, undercover[name], trials*p)
		}
		if !within(mrWhite[name], p) {
			t.Errorf("%s mr white %d times, expected ~%.0f", name, mrWhite[name], trials*p)
		}
		if !within(first[name], p) {
			t.Errorf("%s first %d times, expected ~%.0f", name, first[name], trials*p)
		}
	}
	// Everyone is a civilian with nothing to draw.
	_, roles := DrawCast(players, 0, 0, rng)
	for p, r := range roles {
		if r != RoleCivilian {
			t.Errorf("%s is %s", p, r)
		}
	}
}
