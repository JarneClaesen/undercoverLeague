package catalog

import "github.com/JarneClaesen/underCoverLeague/server/internal/game"

// monsters is the static "monsters" pack: everything on Summoner's Rift
// that is not a champion. Data Dragon has no data or art for these, so the
// list lives here and the icons are empty (the client shows its default).
// Group is what Decoy pairs: epic objectives, drakes, jungle camps and
// lane structures.
var monsters = []game.Entry{
	{Name: "Baron Nashor", Group: "epic"},
	{Name: "Rift Herald", Group: "epic"},
	{Name: "Voidgrubs", Group: "epic"},
	{Name: "Atakhan", Group: "epic"},
	{Name: "Elder Dragon", Group: "drake"},
	{Name: "Infernal Drake", Group: "drake"},
	{Name: "Ocean Drake", Group: "drake"},
	{Name: "Mountain Drake", Group: "drake"},
	{Name: "Cloud Drake", Group: "drake"},
	{Name: "Hextech Drake", Group: "drake"},
	{Name: "Chemtech Drake", Group: "drake"},
	{Name: "Blue Sentinel", Group: "camp"},
	{Name: "Red Brambleback", Group: "camp"},
	{Name: "Gromp", Group: "camp"},
	{Name: "Krugs", Group: "camp"},
	{Name: "Murk Wolves", Group: "camp"},
	{Name: "Raptors", Group: "camp"},
	{Name: "Scuttle Crab", Group: "camp"},
	{Name: "Melee Minion", Group: "lane"},
	{Name: "Caster Minion", Group: "lane"},
	{Name: "Siege Minion", Group: "lane"},
	{Name: "Super Minion", Group: "lane"},
	{Name: "Outer Turret", Group: "lane"},
	{Name: "Inner Turret", Group: "lane"},
	{Name: "Inhibitor Turret", Group: "lane"},
	{Name: "Nexus Turret", Group: "lane"},
	{Name: "Inhibitor", Group: "lane"},
	{Name: "Nexus", Group: "lane"},
	{Name: "Turret Plating", Group: "lane"},
	{Name: "Ward", Group: "lane"},
}

// Monsters returns a copy of the static list.
func Monsters() []game.Entry {
	out := make([]game.Entry, len(monsters))
	copy(out, monsters)
	return out
}
