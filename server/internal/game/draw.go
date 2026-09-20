package game

import (
	"math/rand/v2"
	"slices"
)

// DrawWord picks the word for a game. When both categories are enabled the
// category is chosen first with a coin flip, then a member of it, so
// champions and items each come up 50% of the time even though there are
// more items than champions.
func DrawWord(useChampions, useItems bool, rng *rand.Rand, words *Words) (word Word, isChampion bool) {
	isChampion = useChampions && (!useItems || rng.IntN(2) == 0)
	pool := words.Items
	if isChampion {
		pool = words.Champions
	}
	return pool[rng.IntN(len(pool))], isChampion
}

// DrawRoles picks the round order and the Undercover. Both are uniform:
// every permutation is equally likely and every player has exactly 1/n
// chance of being the Undercover, independent of join order or host status.
func DrawRoles(players []string, rng *rand.Rand) (order []string, undercover string) {
	order = slices.Clone(players)
	rng.Shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })
	return order, order[rng.IntN(len(order))]
}
