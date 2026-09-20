package catalog

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

type fakeStore struct {
	mu      sync.Mutex
	blobs   map[string][]byte
	seasons map[string]int
}

func (f *fakeStore) SaveBlob(key string, b []byte) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.blobs == nil {
		f.blobs = map[string][]byte{}
	}
	f.blobs[key] = b
	return nil
}

func (f *fakeStore) LoadBlob(key string) ([]byte, time.Time, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	b, ok := f.blobs[key]
	if !ok {
		return nil, time.Time{}, nil
	}
	return b, time.Now(), nil
}

func (f *fakeStore) ChampionSeasons() (map[string]int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := map[string]int{}
	for k, v := range f.seasons {
		out[k] = v
	}
	return out, nil
}

func (f *fakeStore) SetChampionSeason(id string, season int) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.seasons == nil {
		f.seasons = map[string]int{}
	}
	f.seasons[id] = season
	return nil
}

func writeTemp(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "f.json")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// ddragonStub serves the fixtures (Data Dragon and, on the same host, the
// Meraki play-rate feed) and counts requests per path. merakiDown makes
// the feed answer 503.
type ddragonStub struct {
	*httptest.Server
	mu         sync.Mutex
	hits       map[string]int
	merakiDown bool
}

func newDDragon(t *testing.T) *ddragonStub {
	t.Helper()
	s := &ddragonStub{hits: map[string]int{}}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		s.hits[r.URL.Path]++
		down := s.merakiDown
		s.mu.Unlock()
		switch p := r.URL.Path; {
		case p == championRatesPath:
			if down {
				http.Error(w, "meraki down", http.StatusServiceUnavailable)
				return
			}
			w.Write([]byte(championRates))
		case p == "/api/versions.json":
			w.Write([]byte(`["16.18.1","16.17.1","3.15.5","lolpatch_3.7"]`))
		case strings.HasSuffix(p, "/championFull.json"):
			w.Write([]byte(championsFull))
		case strings.HasSuffix(p, "/summoner.json"):
			w.Write([]byte(summonerSpells))
		case strings.HasSuffix(p, "/runesReforged.json"):
			w.Write([]byte(runesReforged))
		case p == "/cdn/16.18.1/data/en_US/item.json":
			w.Write([]byte(items16))
		case p == "/cdn/3.15.5/data/en_US/item.json":
			w.Write([]byte(items3))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *ddragonStub) count(path string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.hits[path]
}

func (s *ddragonStub) setMerakiDown(down bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.merakiDown = down
}

// fetcher points both bases at the stub.
func fetcher(url string) *Fetcher { return NewFetcher(url, url) }

func lanesOf(c *game.Catalog, name string) []string {
	for _, ch := range c.Champions {
		if ch.Name == name {
			return ch.Lanes
		}
	}
	return nil
}

func TestServiceRefreshAndCache(t *testing.T) {
	dd := newDDragon(t)
	st := &fakeStore{}
	ov := writeTemp(t, `{"items":{"exclude":["Health Potion"]}}`)
	svc := New(fetcher(dd.URL), st, ov, nil)

	c, err := svc.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if c.Patch != "16.18.1" || len(c.Champions) != 5 {
		t.Errorf("catalog %s %d champions", c.Patch, len(c.Champions))
	}
	if len(c.Spells) != 3 || len(c.Runes) != 6 || len(c.Abilities) != 20 || len(c.SkinLines) != 4 || len(c.Monsters) == 0 {
		t.Errorf("packs: %d spells %d runes %d abilities %d skin lines %d monsters", len(c.Spells), len(c.Runes), len(c.Abilities), len(c.SkinLines), len(c.Monsters))
	}
	for _, ch := range c.Champions {
		if ch.Name == "Newbie" && ch.Season != 16 {
			t.Errorf("unknown champion got season %d", ch.Season)
		}
		if ch.Name == "Wukong" && (ch.Season != 1 || !strings.HasPrefix(ch.Icon, dd.URL+"/cdn/img/champion/loading/MonkeyKing_0.jpg")) {
			t.Errorf("Wukong %+v", ch)
		}
	}
	if st.seasons["Newbie"] != 16 {
		t.Errorf("new champion not remembered: %v", st.seasons)
	}
	for _, it := range c.Items {
		if it.Name == "Health Potion" {
			t.Error("override not applied")
		}
	}
	if st.blobs[currentKey] == nil || st.blobs[itemsKey("3.15.5")] == nil || st.blobs[itemsKey("16.18.1")] == nil ||
		st.blobs[championsKey] == nil || st.blobs[spellsKey] == nil || st.blobs[runesKey] == nil || st.blobs[ratesKey] == nil {
		t.Errorf("cache keys: %v", keys(st.blobs))
	}
	if svc.Status().Source != "ddragon" || svc.Status().Patch != "16.18.1" || svc.Status().LanesPatch != "16.3" {
		t.Errorf("status %+v", svc.Status())
	}
	// Lanes come from the play-rate feed and are part of the catalog.
	if c.LanesPatch != "16.3" || !slices.Equal(lanesOf(c, "Wukong"), []string{"top", "jungle"}) || lanesOf(c, "Newbie") != nil {
		t.Errorf("lanes: patch %q Wukong %v Newbie %v", c.LanesPatch, lanesOf(c, "Wukong"), lanesOf(c, "Newbie"))
	}
	if got := c.Lanes(); !slices.Equal(got, []string{"top", "jungle", "mid", "support"}) {
		t.Errorf("catalog lanes %v", got)
	}

	// Second refresh: the finished season comes from the cache, the current
	// patch and the champion list are fetched again.
	if _, err := svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if n := dd.count("/cdn/3.15.5/data/en_US/item.json"); n != 1 {
		t.Errorf("old season fetched %d times", n)
	}
	if n := dd.count("/cdn/16.18.1/data/en_US/item.json"); n != 2 {
		t.Errorf("current season fetched %d times", n)
	}
	// The per-patch files are cached by patch: fetched once while the
	// patch stays the same, and the cached copy still yields every pack.
	for _, f := range []string{"championFull.json", "summoner.json", "runesReforged.json"} {
		if n := dd.count("/cdn/16.18.1/data/en_US/" + f); n != 1 {
			t.Errorf("%s fetched %d times", f, n)
		}
	}
	if c2 := svc.Current(); len(c2.Abilities) != 20 || len(c2.SkinLines) != 4 || len(c2.Runes) != 6 {
		t.Errorf("second refresh from cache: %d abilities %d skin lines %d runes", len(c2.Abilities), len(c2.SkinLines), len(c2.Runes))
	}
	// The play-rate feed is not versioned by patch, so it is fetched on
	// every refresh.
	if n := dd.count(championRatesPath); n != 2 {
		t.Errorf("play rates fetched %d times", n)
	}
	// A stale cached copy (other patch) is replaced.
	st.SaveBlob(championsKey, []byte(`{"version":"16.17.1","data":{}}`))
	if _, err := svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if n := dd.count("/cdn/16.18.1/data/en_US/championFull.json"); n != 2 {
		t.Errorf("stale champion cache not refetched: %d", n)
	}

	// A new server process boots from the cache without touching the
	// network, lanes included.
	svc2 := New(fetcher("http://127.0.0.1:1"), st, ov, nil)
	boot := svc2.Bootstrap()
	if boot.Patch != "16.18.1" || svc2.Status().Source != "cache" || svc2.Status().LanesPatch != "16.3" || len(boot.Lanes()) != 4 {
		t.Errorf("bootstrap from cache: %s %+v %v", boot.Patch, svc2.Status(), boot.Lanes())
	}

	// Export lists seasons as numbers, not bitmasks.
	e := svc.Export()
	if e.Source != "ddragon" || len(e.Items) == 0 || e.Items[0].Seasons == nil {
		t.Errorf("export %+v", e)
	}
	if b, _ := json.Marshal(e); strings.Contains(string(b), `"seasons":8,`) {
		t.Error("export leaked a bitmask")
	}
}

func TestServiceMerakiOutage(t *testing.T) {
	dd := newDDragon(t)
	st := &fakeStore{}
	svc := New(fetcher(dd.URL), st, "", nil)

	// Nothing cached and Meraki down: the refresh still succeeds, just
	// without lanes, so the client offers no lane filter.
	dd.setMerakiDown(true)
	c, err := svc.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if c.LanesPatch != "" || len(c.Lanes()) != 0 || lanesOf(c, "Wukong") != nil || svc.Status().LanesPatch != "" {
		t.Errorf("lanes without a feed: %q %v %v", c.LanesPatch, c.Lanes(), lanesOf(c, "Wukong"))
	}
	if st.blobs[ratesKey] != nil {
		t.Error("a failed fetch was cached")
	}
	if p := c.PoolSize(game.Filter{Packs: []game.Pack{game.PackChampions}, ChampLanes: []string{"top"}}.Normalized(c)); p[game.PackChampions] != 0 {
		t.Errorf("lane filter without lanes should empty the pool, got %v", p)
	}

	// Meraki back: lanes arrive and the feed is cached.
	dd.setMerakiDown(false)
	if c, err = svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if c.LanesPatch != "16.3" || !slices.Equal(lanesOf(c, "Wukong"), []string{"top", "jungle"}) || st.blobs[ratesKey] == nil {
		t.Errorf("lanes after recovery: %q %v cached=%v", c.LanesPatch, lanesOf(c, "Wukong"), st.blobs[ratesKey] != nil)
	}

	// Meraki down again: the cached feed keeps the lanes and the patch.
	dd.setMerakiDown(true)
	if c, err = svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if c.LanesPatch != "16.3" || !slices.Equal(lanesOf(c, "Wukong"), []string{"top", "jungle"}) || !slices.Equal(lanesOf(c, "Blitzcrank"), []string{"support"}) {
		t.Errorf("lanes from the cached feed: %q %v %v", c.LanesPatch, lanesOf(c, "Wukong"), lanesOf(c, "Blitzcrank"))
	}
	if n := dd.count(championRatesPath); n != 3 {
		t.Errorf("play rates fetched %d times", n)
	}

	// A lane override wins over the feed, and [] takes every lane away.
	ov := writeTemp(t, `{"champions":{"lanes":{"MonkeyKing":["MID"],"Blitzcrank":[]}}}`)
	svc = New(fetcher(dd.URL), st, ov, nil)
	if c, err = svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(lanesOf(c, "Wukong"), []string{"mid"}) || len(lanesOf(c, "Blitzcrank")) != 0 || !slices.Equal(lanesOf(c, "Master Yi"), []string{"jungle"}) {
		t.Errorf("overrides: Wukong %v Blitzcrank %v Master Yi %v", lanesOf(c, "Wukong"), lanesOf(c, "Blitzcrank"), lanesOf(c, "Master Yi"))
	}
	if got := c.Lanes(); !slices.Equal(got, []string{"jungle", "mid", "support"}) {
		t.Errorf("catalog lanes %v", got)
	}
}

func TestServiceBootstrapOldCache(t *testing.T) {
	// A catalog cached by a server from before the new packs existed
	// still boots; the packs are simply empty until the next refresh.
	st := &fakeStore{}
	st.SaveBlob(currentKey, []byte(`{"patch":"16.17.1","champions":[{"name":"Ahri","icon":"https://x","season":1}],"items":[]}`))
	svc := New(fetcher("http://127.0.0.1:1"), st, "", nil)
	c := svc.Bootstrap()
	if c.Patch != "16.17.1" || svc.Status().Source != "cache" || len(c.Spells) != 0 || len(c.Champions[0].Tags) != 0 {
		t.Errorf("old cache: %+v %+v", c, svc.Status())
	}
	if p := c.PoolSize(game.Filter{Packs: game.AllPacks}.Normalized(c)); p[game.PackChampions] != 1 || p[game.PackMonsters] != 0 {
		t.Errorf("pool %v", p)
	}
}

func TestServiceBootstrapEmbedded(t *testing.T) {
	svc := New(fetcher("http://127.0.0.1:1"), &fakeStore{}, "", nil)
	c := svc.Bootstrap()
	if len(c.Champions) < 150 || len(c.Items) < 300 || svc.Status().Source != "embedded" {
		t.Errorf("embedded: %d champions, %d items, %+v", len(c.Champions), len(c.Items), svc.Status())
	}
	// Refresh failure keeps the current catalog.
	if _, err := svc.Refresh(context.Background()); err == nil {
		t.Error("unreachable ddragon should fail")
	}
	if svc.Current() != c || svc.Status().Source != "embedded" {
		t.Error("failed refresh replaced the catalog")
	}
}

func TestServiceRunPublishes(t *testing.T) {
	dd := newDDragon(t)
	svc := New(fetcher(dd.URL), &fakeStore{}, "", nil)
	ctx, cancel := context.WithCancel(context.Background())
	got := make(chan *game.Catalog, 1)
	go svc.Run(ctx, time.Hour, func(c *game.Catalog) { got <- c })
	select {
	case c := <-got:
		if c.Patch != "16.18.1" {
			t.Errorf("published %s", c.Patch)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Run never published")
	}
	cancel()

	// every <= 0 means never fetch.
	done := make(chan struct{})
	go func() { svc.Run(context.Background(), 0, func(*game.Catalog) { t.Error("published") }); close(done) }()
	<-done
}

func TestEmbeddedFallback(t *testing.T) {
	var c game.Catalog
	if err := json.Unmarshal(fallbackJSON, &c); err != nil {
		t.Fatal(err)
	}
	if c.Patch == "" || len(c.Champions) < 150 || len(c.Items) < 300 {
		t.Fatalf("fallback has %d champions, %d items, patch %q", len(c.Champions), len(c.Items), c.Patch)
	}
	seen := map[string]bool{}
	for _, ch := range c.Champions {
		if !strings.HasPrefix(ch.Icon, "https://") || ch.Season < 1 || seen[strings.ToLower(ch.Name)] {
			t.Errorf("champion %+v", ch)
		}
		seen[strings.ToLower(ch.Name)] = true
	}
	for _, it := range c.Items {
		if !strings.HasPrefix(it.Icon, "https://") || it.Seasons == 0 || !game.ValidTier(it.Tier) || seen[strings.ToLower(it.Name)] {
			t.Errorf("item %+v", it)
		}
		seen[strings.ToLower(it.Name)] = true
	}
	lo, hi := c.ItemSeasonRange()
	if lo != FirstSeason || hi < 16 {
		t.Errorf("item seasons %d-%d", lo, hi)
	}
	// The newer packs are in the fallback too, with the metadata the
	// decoys and the class/region filters need.
	if len(c.Spells) < 8 || len(c.Runes) < 60 || len(c.Abilities) < 5*len(c.Champions)-5 || len(c.SkinLines) < 150 || len(c.Monsters) < 20 {
		t.Errorf("packs: %d spells %d runes %d abilities %d skin lines %d monsters", len(c.Spells), len(c.Runes), len(c.Abilities), len(c.SkinLines), len(c.Monsters))
	}
	unrated := 0
	for _, ch := range c.Champions {
		if len(ch.Tags) == 0 || ch.Region == "" || ch.ID == "" || !game.ValidRange(ch.Range) || !game.ValidResource(ch.Resource) {
			t.Errorf("champion without tags/region/id/range/resource: %+v", ch)
		}
		if (ch.Damage == "") != (ch.Difficulty == "") || (ch.Damage != "" && (!game.ValidDamage(ch.Damage) || !game.ValidDifficulty(ch.Difficulty))) {
			t.Errorf("champion with odd damage/difficulty: %+v", ch)
		}
		if ch.Damage == "" {
			unrated++
		}
	}
	// Riot ships a handful of champions with all-zero ratings; if this
	// grows, the ratings feed has probably changed shape.
	if unrated > 6 {
		t.Errorf("%d champions without damage/difficulty", unrated)
	}
	if got := c.Resources(); !slices.Equal(got, game.AllResources) {
		t.Errorf("resources %v", got)
	}
	// Lanes: every lane is played by someone and nearly every champion has
	// at least one (a champion released after Meraki's last patch may lack
	// them for a while).
	if c.LanesPatch == "" || !slices.Equal(c.Lanes(), game.AllLanes) {
		t.Errorf("lanes patch %q lanes %v", c.LanesPatch, c.Lanes())
	}
	laneless := 0
	for _, ch := range c.Champions {
		if len(ch.Lanes) == 0 {
			laneless++
			continue
		}
		for _, l := range ch.Lanes {
			if !game.ValidLane(l) {
				t.Errorf("%s has lane %q", ch.Name, l)
			}
		}
	}
	if laneless > 5 {
		t.Errorf("%d champions without lanes", laneless)
	}
	linked := 0
	for _, it := range c.Items {
		if len(it.From) > 0 || len(it.Into) > 0 {
			linked++
		}
	}
	if linked < len(c.Items)/2 {
		t.Errorf("only %d of %d items have a recipe edge", linked, len(c.Items))
	}
	// Names are unique within a pack (a rune and a skin line may share one:
	// "Conqueror").
	for _, list := range [][]game.Entry{c.Spells, c.Runes, c.Abilities, c.SkinLines} {
		inPack := map[string]bool{}
		for _, e := range list {
			if e.Name == "" || !strings.HasPrefix(e.Icon, "https://") || inPack[strings.ToLower(e.Name)] {
				t.Errorf("entry %+v", e)
			}
			inPack[strings.ToLower(e.Name)] = true
		}
	}
	for _, a := range c.Abilities {
		if a.Champion == "" || a.Group != a.Champion || a.Season < 1 || !strings.HasSuffix(a.Name, " ("+a.Champion+")") {
			t.Errorf("ability %+v", a)
		}
	}
	if len(c.Classes()) != len(game.AllClasses) || len(c.Regions()) != len(game.AllRegions) {
		t.Errorf("classes %v regions %v", c.Classes(), c.Regions())
	}
	if th := c.DailyTheme(time.Now()); th.ID == "" || th.Filter.Validate() != nil {
		t.Errorf("daily theme %+v", th)
	}
	// The static season table covers everything in the fallback: only
	// champions released after both were generated should be "new".
	if len(staticSeasons) < len(c.Champions) {
		t.Errorf("champion_seasons.json has %d entries, fallback %d champions", len(staticSeasons), len(c.Champions))
	}
}

func keys(m map[string][]byte) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
