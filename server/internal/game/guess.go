package game

import (
	"strings"
	"unicode"
)

// WordMatches decides a last guess. Case, spaces and punctuation are
// ignored ("kaisa" is Kai'Sa, "infinity edge" is Infinity Edge); an ability
// may be named with or without its champion ("Charm" or "Charm (Ahri)").
func WordMatches(target, guess string, pack Pack) bool {
	g := foldWord(guess)
	if g == "" {
		return false
	}
	if g == foldWord(target) {
		return true
	}
	if pack == PackAbilities {
		if i := strings.LastIndex(target, " ("); i > 0 {
			return g == foldWord(target[:i])
		}
	}
	return false
}

// foldWord keeps only letters and digits, lower-cased.
func foldWord(s string) string {
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(unicode.ToLower(r))
		}
	}
	return b.String()
}
