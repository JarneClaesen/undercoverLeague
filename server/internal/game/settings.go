package game

import (
	"encoding/json"
)

// Settings is everything the host configures for a lobby: the word-pool
// Filter plus the game rules. It is persisted with the lobby and kept
// between games. Filter is embedded so its fields sit next to these on the
// wire, exactly as the "settings" command sends them.
type Settings struct {
	Filter
	// Undercovers get a word (a decoy, or none) and try to blend in; >= 1.
	Undercovers int `json:"undercovers"`
	// MrWhites get no word at all ("mixed mode"); only meaningful with
	// DecoyWord, otherwise they are Undercovers by another name.
	MrWhites int `json:"mrWhites"`
	// DecoyWord gives Undercovers a neighbour of the word instead of nothing.
	DecoyWord bool `json:"decoyWord"`
	// RandomOrder reshuffles the round order after every tally; false keeps
	// the Start order and rotates the first speaker by one each round.
	RandomOrder bool `json:"randomOrder"`
	// TurnSeconds bounds a describing turn; voting and a last guess get
	// twice as long. 0 turns the timer off, otherwise 10..300.
	TurnSeconds int `json:"turnSeconds"`
	// ClueLog makes turns end with a typed clue that everyone can read back.
	ClueLog bool `json:"clueLog"`
	// RotateHost passes the host seat on after every "play again".
	RotateHost bool `json:"rotateHost"`
}

const (
	MinTurnSeconds = 10
	MaxTurnSeconds = 300
)

func DefaultSettings() Settings {
	return Settings{Filter: DefaultFilter(), Undercovers: 1, RandomOrder: true}
}

// UnmarshalJSON decodes the Filter part through Filter's own decoder (which
// the embedding would otherwise promote to the whole struct) and the rule
// fields separately. A missing "randomOrder" key, as on rows saved before it
// existed, means the old behaviour, true; an explicit false is kept.
func (s *Settings) UnmarshalJSON(b []byte) error {
	if err := s.Filter.UnmarshalJSON(b); err != nil {
		return err
	}
	var aux struct {
		Undercovers int   `json:"undercovers"`
		MrWhites    int   `json:"mrWhites"`
		DecoyWord   bool  `json:"decoyWord"`
		RandomOrder *bool `json:"randomOrder"`
		TurnSeconds int   `json:"turnSeconds"`
		ClueLog     bool  `json:"clueLog"`
		RotateHost  bool  `json:"rotateHost"`
	}
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	s.Undercovers = aux.Undercovers
	s.MrWhites = aux.MrWhites
	s.DecoyWord = aux.DecoyWord
	s.RandomOrder = aux.RandomOrder == nil || *aux.RandomOrder
	s.TurnSeconds = aux.TurnSeconds
	s.ClueLog = aux.ClueLog
	s.RotateHost = aux.RotateHost
	return nil
}

// Validate rejects what a client should never send. Whether the impostor
// count fits the table is checked at Start, when the head count is known.
func (s Settings) Validate() error {
	if err := s.Filter.Validate(); err != nil {
		return err
	}
	switch {
	case s.Undercovers < 1:
		return invalid("At least one undercover is needed.")
	case s.MrWhites < 0:
		return invalid("Invalid number of Mr. Whites.")
	case s.MrWhites > 0 && !s.DecoyWord:
		return invalid("Mixed mode needs decoy words, otherwise Undercover and Mr. White are the same role.")
	case s.TurnSeconds != 0 && (s.TurnSeconds < MinTurnSeconds || s.TurnSeconds > MaxTurnSeconds):
		return invalid("Turn timer must be off or between 10 and 300 seconds.")
	}
	return nil
}

// Normalized is the Filter's Normalized with the rule fields carried along
// and a zero Undercovers (rows from before the setting existed) read as 1.
func (s Settings) Normalized(c *Catalog) Settings {
	out := s
	out.Filter = s.Filter.Normalized(c)
	if out.Undercovers < 1 {
		out.Undercovers = 1
	}
	return out
}

// Impostors is how many players get something other than the real word.
func (s Settings) Impostors() int { return s.Undercovers + s.MrWhites }
