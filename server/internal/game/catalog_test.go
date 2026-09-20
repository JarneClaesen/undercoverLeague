package game

import "testing"

// testCatalog is a small hand-built pool covering the season and tier
// combinations the filter tests need. Names are unique across categories.
func testCatalog() *Catalog {
	set := func(seasons ...int) SeasonSet {
		var s SeasonSet
		for _, x := range seasons {
			s.Add(x)
		}
		return s
	}
	c := &Catalog{
		Patch: "16.18.1",
		Champions: []Champion{
			{Name: "Annie", Icon: "https://x/Annie_0.jpg", Season: 1},
			{Name: "Ahri", Icon: "https://x/Ahri_0.jpg", Season: 1},
			{Name: "Aatrox", Icon: "https://x/Aatrox_0.jpg", Season: 3},
			{Name: "Zoe", Icon: "https://x/Zoe_0.jpg", Season: 7},
			{Name: "Mel", Icon: "https://x/Mel_0.jpg", Season: 15},
			{Name: "Yunara", Icon: "https://x/Yunara_0.jpg", Season: 16},
		},
		Items: []Item{
			{Name: "Doran's Blade", Icon: "https://x/1055.png", Seasons: set(3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16), Tier: TierStarter},
			{Name: "Health Potion", Icon: "https://x/2003.png", Seasons: set(3, 16), Tier: TierConsumable},
			{Name: "Boots", Icon: "https://x/1001.png", Seasons: set(3, 16), Tier: TierBoots},
			{Name: "Long Sword", Icon: "https://x/1036.png", Seasons: set(3, 16), Tier: TierComponent},
			{Name: "Deathfire Grasp", Icon: "https://x/3128.png", Seasons: set(3, 4), Tier: TierLegendary},
			{Name: "Infinity Edge", Icon: "https://x/3031.png", Seasons: set(3, 16), Tier: TierLegendary},
			{Name: "Heartsteel", Icon: "https://x/3084.png", Seasons: set(13, 14, 15, 16), Tier: TierLegendary},
			{Name: "Yun Tal Wildarrows", Icon: "https://x/3032.png", Seasons: set(14, 15, 16), Tier: TierLegendary},
		},
	}
	c.Sort()
	return c
}

func TestCatalogRanges(t *testing.T) {
	c := testCatalog()
	if lo, hi := c.ChampSeasonRange(); lo != 1 || hi != 16 {
		t.Errorf("champ range %d-%d", lo, hi)
	}
	if lo, hi := c.ItemSeasonRange(); lo != 3 || hi != 16 {
		t.Errorf("item range %d-%d", lo, hi)
	}
	empty := &Catalog{}
	if lo, hi := empty.ChampSeasonRange(); lo != 0 || hi != 0 {
		t.Errorf("empty champ range %d-%d", lo, hi)
	}
	if lo, hi := empty.ItemSeasonRange(); lo != 0 || hi != 0 {
		t.Errorf("empty item range %d-%d", lo, hi)
	}
}

func TestSeasonSet(t *testing.T) {
	var s SeasonSet
	s.Add(3)
	s.Add(16)
	s.Add(40) // out of range, ignored
	if !s.Has(3) || !s.Has(16) || s.Has(4) || s.Has(40) {
		t.Errorf("membership wrong: %v", s.Seasons())
	}
	if got := s.Seasons(); len(got) != 2 || got[0] != 3 || got[1] != 16 {
		t.Errorf("seasons %v", got)
	}
	if !s.Overlaps(1, 3) || s.Overlaps(4, 15) || !s.Overlaps(10, 20) {
		t.Error("overlap wrong")
	}
}

func TestPoolSize(t *testing.T) {
	c := testCatalog()
	cases := []struct {
		name  string
		f     Filter
		champ int
		items int
	}{
		{"everything", DefaultFilter(), 6, 8},
		{"old champions only", Filter{UseChampions: true, ChampSeasons: [2]int{1, 3}}, 3, 0},
		{"new champions", Filter{UseChampions: true, ChampSeasons: [2]int{15, 16}}, 2, 0},
		{"old items", Filter{UseItems: true, ItemSeasons: [2]int{3, 10}}, 0, 6},
		{"current legendaries", Filter{UseItems: true, ItemSeasons: [2]int{16, 16}, ItemTiers: []Tier{TierLegendary}}, 0, 3},
		{"no tiers", Filter{UseItems: true, ItemTiers: []Tier{}}, 0, 0},
		{"season with nothing", Filter{UseChampions: true, ChampSeasons: [2]int{2, 2}}, 0, 0},
	}
	for _, tc := range cases {
		got := c.PoolSize(tc.f.Normalized(c))
		if got.Champions != tc.champ || got.Items != tc.items {
			t.Errorf("%s: got %+v, want %d/%d", tc.name, got, tc.champ, tc.items)
		}
	}
}
