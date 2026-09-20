package game

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

func TestSettingsValidate(t *testing.T) {
	base := DefaultSettings()
	with := func(f func(*Settings)) Settings {
		s := base
		f(&s)
		return s
	}
	cases := []struct {
		name string
		s    Settings
		ok   bool
	}{
		{"defaults", base, true},
		{"no packs", with(func(s *Settings) { s.Packs = nil }), false},
		{"unknown pack", with(func(s *Settings) { s.Packs = []Pack{"pets"} }), false},
		{"zero undercovers", with(func(s *Settings) { s.Undercovers = 0 }), false},
		{"two undercovers", with(func(s *Settings) { s.Undercovers = 2 }), true},
		{"negative mr whites", with(func(s *Settings) { s.MrWhites = -1 }), false},
		{"mr white without decoy", with(func(s *Settings) { s.MrWhites = 1 }), false},
		{"mr white with decoy", with(func(s *Settings) { s.MrWhites = 1; s.DecoyWord = true }), true},
		{"timer off", with(func(s *Settings) { s.TurnSeconds = 0 }), true},
		{"timer too short", with(func(s *Settings) { s.TurnSeconds = 9 }), false},
		{"timer minimum", with(func(s *Settings) { s.TurnSeconds = 10 }), true},
		{"timer maximum", with(func(s *Settings) { s.TurnSeconds = 300 }), true},
		{"timer too long", with(func(s *Settings) { s.TurnSeconds = 301 }), false},
		{"timer negative", with(func(s *Settings) { s.TurnSeconds = -10 }), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.s.Validate()
			if (err == nil) != tc.ok {
				t.Errorf("Validate(%+v) = %v, want ok=%v", tc.s, err, tc.ok)
			}
			if err != nil && errCode(err) != "invalid" {
				t.Errorf("code %q", errCode(err))
			}
		})
	}
	if err := with(func(s *Settings) { s.MrWhites = 1 }).Validate(); err == nil || !strings.Contains(err.Error(), "Mixed mode") {
		t.Errorf("mixed mode message: %v", err)
	}
}

func TestSettingsJSONRoundTrip(t *testing.T) {
	in := Settings{
		Filter: Filter{
			Packs: []Pack{PackChampions, PackSpells}, ChampSeasons: [2]int{3, 10}, ItemSeasons: [2]int{5, 6},
			ItemTiers: []Tier{TierBoots}, ChampClasses: []string{"Mage"}, ChampRegions: []string{"Ionia"},
		},
		Undercovers: 2, MrWhites: 1, DecoyWord: true, RandomOrder: false, TurnSeconds: 45, ClueLog: true, RotateHost: true,
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatal(err)
	}
	// Filter fields are flattened next to the rules, exactly as the
	// "settings" command sends them.
	for _, key := range []string{`"packs":["champions","spells"]`, `"champSeasons":[3,10]`, `"undercovers":2`, `"mrWhites":1`,
		`"decoyWord":true`, `"randomOrder":false`, `"turnSeconds":45`, `"clueLog":true`, `"rotateHost":true`, `"champRegions":["Ionia"]`} {
		if !strings.Contains(string(b), key) {
			t.Errorf("JSON lacks %s: %s", key, b)
		}
	}
	var out Settings
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(out.Packs, in.Packs) || out.ChampSeasons != in.ChampSeasons || out.ItemSeasons != in.ItemSeasons ||
		!slices.Equal(out.ItemTiers, in.ItemTiers) || !slices.Equal(out.ChampClasses, in.ChampClasses) ||
		!slices.Equal(out.ChampRegions, in.ChampRegions) {
		t.Errorf("filter changed: %+v -> %+v", in.Filter, out.Filter)
	}
	if out.Undercovers != 2 || out.MrWhites != 1 || !out.DecoyWord || out.RandomOrder || out.TurnSeconds != 45 || !out.ClueLog || !out.RotateHost {
		t.Errorf("rules changed: %+v", out)
	}
}

func TestSettingsLegacyJSON(t *testing.T) {
	cases := []struct {
		name        string
		json        string
		packs       []Pack
		randomOrder bool
		undercovers int
	}{
		{"pre-packs row", `{"useChampions":true,"useItems":false,"champSeasons":[0,0]}`, []Pack{PackChampions}, false, 0},
		{"packs without rules", `{"packs":["items"]}`, []Pack{PackItems}, false, 0},
		{"explicit random order false", `{"packs":["items"],"randomOrder":false,"undercovers":1}`, []Pack{PackItems}, false, 1},
		{"explicit random order true", `{"packs":["items"],"randomOrder":true}`, []Pack{PackItems}, true, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var s Settings
			if err := json.Unmarshal([]byte(tc.json), &s); err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(s.Packs, tc.packs) || s.RandomOrder != tc.randomOrder || s.Undercovers != tc.undercovers {
				t.Errorf("got %+v", s)
			}
			// A zero undercover count from an old row reads as one.
			if n := s.Normalized(testCatalog()); n.Undercovers < 1 {
				t.Errorf("normalized undercovers %d", n.Undercovers)
			}
		})
	}
}

// Rows saved before any setting existed have no "settings" at all, which
// Normalize must turn into the defaults (including RandomOrder = true,
// which a zero struct would get wrong).
func TestNormalizeOldSettings(t *testing.T) {
	var l Lobby
	if err := json.Unmarshal([]byte(`{"id":"L","host":"A","players":["A"]}`), &l); err != nil {
		t.Fatal(err)
	}
	l.Normalize()
	if l.Settings.Undercovers != 1 || l.Settings.RandomOrder || !slices.Equal(l.Settings.Packs, DefaultFilter().Packs) {
		t.Errorf("old row settings %+v", l.Settings)
	}

	var withFilter Lobby
	if err := json.Unmarshal([]byte(`{"id":"L","host":"A","players":["A"],"settings":{"packs":["items"],"randomOrder":true}}`), &withFilter); err != nil {
		t.Fatal(err)
	}
	withFilter.Normalize()
	if s := withFilter.Settings; s.Undercovers != 1 || !s.RandomOrder || !slices.Equal(s.Packs, []Pack{PackItems}) {
		t.Errorf("row with a filter but no rules %+v", s)
	}
}

func TestSetSettingsRejectsBadRules(t *testing.T) {
	l := New("L", "A", t0)
	s := DefaultSettings()
	s.MrWhites = 1
	if err := l.SetSettings("A", s); errCode(err) != "invalid" {
		t.Errorf("mixed mode without decoy: %v", err)
	}
	s.DecoyWord = true
	s.TurnSeconds = 30
	if err := l.SetSettings("A", s); err != nil {
		t.Fatal(err)
	}
	if l.Settings.MrWhites != 1 || l.Settings.TurnSeconds != 30 || !l.Settings.DecoyWord {
		t.Errorf("settings not stored: %+v", l.Settings)
	}
}
