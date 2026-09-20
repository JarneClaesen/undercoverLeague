package catalog

import (
	"regexp"
	"strconv"
)

// Seasons are numbered by year (S1 = 2011) and from Season 3 on Riot's
// patch major version is the season number, so 3.15.5 is the last patch
// of Season 3 and 16.x is Season 16 (2026). Data Dragon has nothing
// before 3.6, so item history starts at Season 3.
const FirstSeason = 3

var patchRE = regexp.MustCompile(`^(\d+)\.\d+\.\d+$`)

// SeasonVersions picks one item snapshot per season from the version list
// (newest first, as Data Dragon serves it): the last patch of every past
// season and the newest patch of the current one. Entries that are not a
// plain x.y.z patch (e.g. "lolpatch_3.7") or predate Season 3 are skipped.
// Returns the map and the current season; current is 0 when nothing parsed.
func SeasonVersions(versions []string) (bySeason map[int]string, current int) {
	bySeason = map[int]string{}
	for _, v := range versions {
		m := patchRE.FindStringSubmatch(v)
		if m == nil {
			continue
		}
		season, _ := strconv.Atoi(m[1])
		if season < FirstSeason {
			continue
		}
		if _, seen := bySeason[season]; !seen {
			bySeason[season] = v
		}
		if season > current {
			current = season
		}
	}
	return bySeason, current
}

// SeasonOfYear maps a release date's year to a season, clamping the 2009
// and 2010 champions into Season 1.
func SeasonOfYear(year int) int {
	return max(year-2010, 1)
}
