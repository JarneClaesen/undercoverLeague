package game

import (
	"strings"
	"testing"
)

func TestWords(t *testing.T) {
	w := LoadWords()
	if len(w.Champions) != 167 || len(w.Items) != 202 {
		t.Errorf("got %d champions and %d items", len(w.Champions), len(w.Items))
	}
	for label, list := range map[string][]Word{"champions": w.Champions, "items": w.Items} {
		seen := map[string]bool{}
		for _, word := range list {
			if word.Name == "" || !strings.HasPrefix(word.Icon, "assets/"+label+"/") {
				t.Errorf("%s: bad entry %+v", label, word)
			}
			key := strings.ToLower(word.Name)
			if seen[key] {
				t.Errorf("%s: duplicate %q", label, word.Name)
			}
			seen[key] = true
		}
	}
}
