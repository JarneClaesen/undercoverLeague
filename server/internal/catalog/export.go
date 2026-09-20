package catalog

import (
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

// Export is the human-readable shape served at GET /catalog for checking
// what the filters can draw from and tuning the overrides file.
type Export struct {
	Patch     string           `json:"patch"`
	Source    string           `json:"source"`
	UpdatedAt *time.Time       `json:"updatedAt"`
	Seasons   game.SeasonRange `json:"seasons"`
	Classes   []string         `json:"classes"`
	Regions   []string         `json:"regions"`
	Champions []game.Champion  `json:"champions"`
	Items     []ExportItem     `json:"items"`
	Spells    []game.Entry     `json:"spells"`
	Runes     []game.Entry     `json:"runes"`
	Abilities []game.Entry     `json:"abilities"`
	SkinLines []game.Entry     `json:"skinLines"`
	Monsters  []game.Entry     `json:"monsters"`
}

type ExportItem struct {
	Name    string    `json:"name"`
	Icon    string    `json:"icon"`
	Seasons []int     `json:"seasons"`
	Tier    game.Tier `json:"tier"`
	From    []string  `json:"from,omitempty"`
	Into    []string  `json:"into,omitempty"`
	Gold    int       `json:"gold,omitempty"`
}

func (s *Service) Export() Export {
	c := s.Current()
	st := s.Status()
	e := Export{
		Patch: st.Patch, Source: st.Source, Classes: []string{}, Regions: []string{},
		Champions: []game.Champion{}, Items: []ExportItem{},
		Spells: []game.Entry{}, Runes: []game.Entry{}, Abilities: []game.Entry{}, SkinLines: []game.Entry{}, Monsters: []game.Entry{},
	}
	if !st.UpdatedAt.IsZero() {
		at := st.UpdatedAt
		e.UpdatedAt = &at
	}
	if c == nil {
		return e
	}
	e.Seasons = c.SeasonRange()
	e.Classes, e.Regions = c.Classes(), c.Regions()
	e.Champions = c.Champions
	for _, it := range c.Items {
		e.Items = append(e.Items, ExportItem{Name: it.Name, Icon: it.Icon, Seasons: it.Seasons.Seasons(), Tier: it.Tier, From: it.From, Into: it.Into, Gold: it.Gold})
	}
	e.Spells = append(e.Spells, c.Spells...)
	e.Runes = append(e.Runes, c.Runes...)
	e.Abilities = append(e.Abilities, c.Abilities...)
	e.SkinLines = append(e.SkinLines, c.SkinLines...)
	e.Monsters = append(e.Monsters, c.Monsters...)
	return e
}
