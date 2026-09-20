package catalog

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

// ddragonStub serves the fixtures and counts requests per path.
type ddragonStub struct {
	*httptest.Server
	mu   sync.Mutex
	hits map[string]int
}

func newDDragon(t *testing.T) *ddragonStub {
	t.Helper()
	s := &ddragonStub{hits: map[string]int{}}
	const champs = `{"data":{"Ahri":{"id":"Ahri","name":"Ahri"},"MonkeyKing":{"id":"MonkeyKing","name":"Wukong"},"Newbie":{"id":"Newbie","name":"Newbie"}}}`
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		s.hits[r.URL.Path]++
		s.mu.Unlock()
		switch p := r.URL.Path; {
		case p == "/api/versions.json":
			w.Write([]byte(`["16.18.1","16.17.1","3.15.5","lolpatch_3.7"]`))
		case strings.HasSuffix(p, "/champion.json"):
			w.Write([]byte(champs))
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

func TestServiceRefreshAndCache(t *testing.T) {
	dd := newDDragon(t)
	st := &fakeStore{}
	ov := writeTemp(t, `{"items":{"exclude":["Health Potion"]}}`)
	svc := New(NewFetcher(dd.URL), st, ov, nil)

	c, err := svc.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if c.Patch != "16.18.1" || len(c.Champions) != 3 {
		t.Errorf("catalog %s %d champions", c.Patch, len(c.Champions))
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
	if st.blobs[currentKey] == nil || st.blobs[itemsKey("3.15.5")] == nil || st.blobs[itemsKey("16.18.1")] == nil {
		t.Errorf("cache keys: %v", keys(st.blobs))
	}
	if svc.Status().Source != "ddragon" || svc.Status().Patch != "16.18.1" {
		t.Errorf("status %+v", svc.Status())
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

	// A new server process boots from the cache without touching the network.
	svc2 := New(NewFetcher("http://127.0.0.1:1"), st, ov, nil)
	boot := svc2.Bootstrap()
	if boot.Patch != "16.18.1" || svc2.Status().Source != "cache" {
		t.Errorf("bootstrap from cache: %s %+v", boot.Patch, svc2.Status())
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

func TestServiceBootstrapEmbedded(t *testing.T) {
	svc := New(NewFetcher("http://127.0.0.1:1"), &fakeStore{}, "", nil)
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
	svc := New(NewFetcher(dd.URL), &fakeStore{}, "", nil)
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
