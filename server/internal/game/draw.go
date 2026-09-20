package game

import (
	"math/rand/v2"
	"slices"
)

// DrawWord picks the word for a game: first a pack, uniformly among the
// enabled ones, then a member of it, so every enabled pack comes up
// equally often however the pools differ in size. f must be Normalized.
// An enabled pack with nothing in it is an error rather than a silent
// fallback to the others: the host asked for it, so they should hear that
// the filters are too tight.
func DrawWord(f Filter, rng *rand.Rand, c *Catalog) (word Word, pack Pack, err error) {
	if len(f.Packs) == 0 {
		return Word{}, "", invalid("Enable at least one word pack.")
	}
	pools := make([][]Word, len(f.Packs))
	for i, p := range f.Packs {
		if pools[i] = c.FilterPack(p, f); len(pools[i]) == 0 {
			return Word{}, "", invalid("No " + p.Label() + " match the current filters.")
		}
	}
	i := rng.IntN(len(f.Packs))
	return pools[i][rng.IntN(len(pools[i]))], f.Packs[i], nil
}

// DrawRoles picks the round order and the Undercover. Both are uniform:
// every permutation is equally likely and every player has exactly 1/n
// chance of being the Undercover, independent of join order or host status.
func DrawRoles(players []string, rng *rand.Rand) (order []string, undercover string) {
	order = slices.Clone(players)
	rng.Shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })
	return order, order[rng.IntN(len(order))]
}

// DrawCast is DrawRoles for any number of impostors: the round order is a
// uniform permutation and the undercovers + mrWhites impostor seats are a
// uniform choice among the players, independent of the order. Everyone
// else is a Civilian. The caller guarantees undercovers+mrWhites <= len.
func DrawCast(players []string, undercovers, mrWhites int, rng *rand.Rand) (order []string, roles map[string]string) {
	order = slices.Clone(players)
	rng.Shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })
	seats := slices.Clone(players)
	rng.Shuffle(len(seats), func(i, j int) { seats[i], seats[j] = seats[j], seats[i] })
	roles = make(map[string]string, len(players))
	for i, p := range seats {
		switch {
		case i < undercovers:
			roles[p] = RoleUndercover
		case i < undercovers+mrWhites:
			roles[p] = RoleMrWhite
		default:
			roles[p] = RoleCivilian
		}
	}
	return order, roles
}
