package game

import (
	"math/rand/v2"
	"slices"
)

// DrawWord picks the word for a game. When both categories are enabled the
// category is chosen first with a coin flip, then a member of it, so
// champions and items each come up 50% of the time even though the pools
// differ in size. f must be Normalized. An enabled category with nothing
// in it is an error rather than a silent fallback to the other one: the
// host asked for it, so they should hear that the filters are too tight.
func DrawWord(f Filter, rng *rand.Rand, c *Catalog) (word Word, isChampion bool, err error) {
	var champions []Champion
	var items []Item
	if f.UseChampions {
		if champions = c.FilterChampions(f); len(champions) == 0 {
			return Word{}, false, invalid("No champions match the selected seasons.")
		}
	}
	if f.UseItems {
		if items = c.FilterItems(f); len(items) == 0 {
			return Word{}, false, invalid("No items match the selected seasons and tiers.")
		}
	}
	if !f.UseChampions && !f.UseItems {
		return Word{}, false, invalid("At least one of champions or items must be enabled.")
	}

	isChampion = f.UseChampions && (!f.UseItems || rng.IntN(2) == 0)
	if isChampion {
		ch := champions[rng.IntN(len(champions))]
		return Word{Name: ch.Name, Icon: ch.Icon}, true, nil
	}
	it := items[rng.IntN(len(items))]
	return Word{Name: it.Name, Icon: it.Icon}, false, nil
}

// DrawRoles picks the round order and the Undercover. Both are uniform:
// every permutation is equally likely and every player has exactly 1/n
// chance of being the Undercover, independent of join order or host status.
func DrawRoles(players []string, rng *rand.Rand) (order []string, undercover string) {
	order = slices.Clone(players)
	rng.Shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })
	return order, order[rng.IntN(len(order))]
}
