// Package catalog builds the word pool from Riot's Data Dragon CDN: one
// champion list (with release seasons) and one item snapshot per season,
// merged into a game.Catalog. Everything that touches the network or the
// database lives here; internal/game only ever sees the finished value.
package catalog

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"
)

const DefaultBase = "https://ddragon.leagueoflegends.com"

// Fetcher is the thin HTTP client for Data Dragon. Base has no trailing
// slash; tests point it at an httptest server.
type Fetcher struct {
	Base   string
	Client *http.Client
}

func NewFetcher(base string) *Fetcher {
	if base == "" {
		base = DefaultBase
	}
	return &Fetcher{Base: base, Client: &http.Client{Timeout: 30 * time.Second}}
}

// Versions lists every patch, newest first, e.g. ["16.18.1", "16.17.1", ...].
func (f *Fetcher) Versions(ctx context.Context) ([]string, error) {
	var v []string
	return v, f.getJSON(ctx, "/api/versions.json", &v)
}

type rawChampion struct {
	ID   string `json:"id"`   // e.g. MonkeyKing; used in image URLs
	Name string `json:"name"` // e.g. Wukong; shown to players
}

// rawChampionFull is one entry of championFull.json: the champion list
// plus, per champion, classes, ratings, base stats, abilities and skins in
// a single file.
type rawChampionFull struct {
	ID      string     `json:"id"`
	Name    string     `json:"name"`
	Tags    []string   `json:"tags"`    // Fighter, Mage, ... primary first
	Partype string     `json:"partype"` // resource bar: Mana, Energy, None, Fury, ...
	Info    rawInfo    `json:"info"`
	Stats   rawStats   `json:"stats"`
	Spells  []rawSpell `json:"spells"`
	Passive rawSpell   `json:"passive"`
	Skins   []rawSkin  `json:"skins"`
}

// rawInfo is Riot's 0-10 champion ratings (the bars on the collection
// page). A few champions ship with all zeros.
type rawInfo struct {
	Attack     int `json:"attack"`
	Defense    int `json:"defense"`
	Magic      int `json:"magic"`
	Difficulty int `json:"difficulty"`
}

type rawStats struct {
	AttackRange float64 `json:"attackrange"` // base auto-attack range
}

type rawSpell struct {
	Name  string   `json:"name"`
	Image rawImage `json:"image"`
	Modes []string `json:"modes"` // summoner spells only
}

type rawImage struct {
	Full string `json:"full"` // file name, e.g. AhriE.png
}

type rawSkin struct {
	Num  int    `json:"num"`  // 0 is the base skin
	Name string `json:"name"` // "default" for the base skin
}

// rawRuneTree is one entry of runesReforged.json: a tree with its slots,
// the first slot holding the keystones.
type rawRuneTree struct {
	Key   string `json:"key"` // Precision, Domination, ...
	Name  string `json:"name"`
	Slots []struct {
		Runes []rawRune `json:"runes"`
	} `json:"slots"`
}

type rawRune struct {
	Name string `json:"name"`
	Icon string `json:"icon"` // path under /cdn/img/, e.g. perk-images/Styles/...
}

type rawItem struct {
	Name string `json:"name"`
	Gold struct {
		Total       int  `json:"total"`
		Purchasable bool `json:"purchasable"`
	} `json:"gold"`
	Tags []string `json:"tags"`
	From []string `json:"from"`
	Into []string `json:"into"`
	// Maps is per-map availability. Summoner's Rift is "11" from patch 4.x
	// on and "1" in 3.x; 3.x omits the key entirely for SR items.
	Maps             map[string]bool `json:"maps"`
	RequiredChampion string          `json:"requiredChampion"`
	RequiredAlly     string          `json:"requiredAlly"`
	InStore          *bool           `json:"inStore"`
	HideFromAll      bool            `json:"hideFromAll"`
}

func (f *Fetcher) Champions(ctx context.Context, version string) (map[string]rawChampion, error) {
	var body struct {
		Data map[string]rawChampion `json:"data"`
	}
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/champion.json", &body)
	return body.Data, err
}

// ChampionsFull fetches championFull.json (about 2 MB), the one file that
// has tags, spells, passives and skins for every champion.
func (f *Fetcher) ChampionsFull(ctx context.Context, version string) (map[string]rawChampionFull, error) {
	var body struct {
		Data map[string]rawChampionFull `json:"data"`
	}
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/championFull.json", &body)
	return body.Data, err
}

func (f *Fetcher) Items(ctx context.Context, version string) (map[string]rawItem, error) {
	var body struct {
		Data map[string]rawItem `json:"data"`
	}
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/item.json", &body)
	return body.Data, err
}

func (f *Fetcher) SummonerSpells(ctx context.Context, version string) (map[string]rawSpell, error) {
	var body struct {
		Data map[string]rawSpell `json:"data"`
	}
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/summoner.json", &body)
	return body.Data, err
}

func (f *Fetcher) Runes(ctx context.Context, version string) ([]rawRuneTree, error) {
	var trees []rawRuneTree
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/runesReforged.json", &trees)
	return trees, err
}

func (f *Fetcher) getJSON(ctx context.Context, path string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, f.Base+path, nil)
	if err != nil {
		return err
	}
	res, err := f.Client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", path, res.Status)
	}
	if err := json.NewDecoder(res.Body).Decode(v); err != nil {
		return fmt.Errorf("GET %s: %w", path, err)
	}
	return nil
}

// ChampionArt is the unversioned loading-screen portrait of the base skin,
// the same art the app used to bundle.
func ChampionArt(base, id string) string {
	return base + "/cdn/img/champion/loading/" + id + "_0.jpg"
}

// ItemIcon is versioned so that items removed from the game keep the icon
// of the last patch they were in.
func ItemIcon(base, version, id string) string {
	return base + "/cdn/" + version + "/img/item/" + id + ".png"
}

// SpellIcon is the versioned icon of a champion ability or summoner spell.
func SpellIcon(base, version, file string) string {
	return base + "/cdn/" + version + "/img/spell/" + file
}

// PassiveIcon is the versioned icon of a champion passive.
func PassiveIcon(base, version, file string) string {
	return base + "/cdn/" + version + "/img/passive/" + file
}

// RuneIcon is unversioned: runesReforged.json gives the path under /cdn/img/.
func RuneIcon(base, path string) string {
	return base + "/cdn/img/" + path
}

// SkinSplash is the unversioned splash art of one skin of a champion.
func SkinSplash(base, id string, num int) string {
	return base + "/cdn/img/champion/splash/" + id + "_" + strconv.Itoa(num) + ".jpg"
}
