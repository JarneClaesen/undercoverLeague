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
	Champions []game.Champion  `json:"champions"`
	Items     []ExportItem     `json:"items"`
}

type ExportItem struct {
	Name    string    `json:"name"`
	Icon    string    `json:"icon"`
	Seasons []int     `json:"seasons"`
	Tier    game.Tier `json:"tier"`
}

func (s *Service) Export() Export {
	c := s.Current()
	st := s.Status()
	e := Export{Patch: st.Patch, Source: st.Source, Champions: []game.Champion{}, Items: []ExportItem{}}
	if !st.UpdatedAt.IsZero() {
		at := st.UpdatedAt
		e.UpdatedAt = &at
	}
	if c == nil {
		return e
	}
	e.Seasons = c.SeasonRange()
	e.Champions = c.Champions
	for _, it := range c.Items {
		e.Items = append(e.Items, ExportItem{Name: it.Name, Icon: it.Icon, Seasons: it.Seasons.Seasons(), Tier: it.Tier})
	}
	return e
}
