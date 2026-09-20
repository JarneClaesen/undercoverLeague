package game

import (
	_ "embed"
	"encoding/json"
	"sync"
)

//go:embed words.json
var wordsJSON []byte

type Word struct {
	Name string `json:"name"`
	// Icon is the asset path inside the Flutter app, e.g.
	// assets/champions/ahri.jpg. The server never serves it; clients bundle it.
	Icon string `json:"icon"`
}

type Words struct {
	Champions []Word `json:"champions"`
	Items     []Word `json:"items"`
}

var (
	loadOnce sync.Once
	loaded   *Words
)

// LoadWords parses the embedded list once. It panics on a malformed embed,
// which can only happen at build time.
func LoadWords() *Words {
	loadOnce.Do(func() {
		var w Words
		if err := json.Unmarshal(wordsJSON, &w); err != nil {
			panic("words.json: " + err.Error())
		}
		if len(w.Champions) == 0 || len(w.Items) == 0 {
			panic("words.json: empty category")
		}
		loaded = &w
	})
	return loaded
}
