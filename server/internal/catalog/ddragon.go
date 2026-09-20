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

func (f *Fetcher) Items(ctx context.Context, version string) (map[string]rawItem, error) {
	var body struct {
		Data map[string]rawItem `json:"data"`
	}
	err := f.getJSON(ctx, "/cdn/"+version+"/data/en_US/item.json", &body)
	return body.Data, err
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
