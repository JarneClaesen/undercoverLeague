// catalogtool regenerates the two JSON files embedded in internal/catalog.
//
//	go run ./cmd/catalogtool -seasons > internal/catalog/champion_seasons.json
//	go run ./cmd/catalogtool -dump    > internal/catalog/fallback.json
//
// -seasons scrapes release dates from the LoL wiki's ChampionData module
// and cross-checks the ids against Data Dragon; -dump runs a full refresh
// (without a database, so nothing is cached) and prints the catalog.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strconv"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/catalog"
)

const wikiURL = "https://wiki.leagueoflegends.com/en-us/Module:ChampionData/data?action=raw"

func main() {
	seasons := flag.Bool("seasons", false, "print champion_seasons.json")
	dump := flag.Bool("dump", false, "print fallback.json")
	overrides := flag.String("overrides", "deploy/catalog_overrides.json", "overrides file used by -dump")
	base := flag.String("ddragon", catalog.DefaultBase, "Data Dragon base URL")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	var err error
	switch {
	case *seasons:
		err = printSeasons(ctx, *base)
	case *dump:
		err = printDump(ctx, *base, *overrides)
	default:
		flag.Usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "catalogtool:", err)
		os.Exit(1)
	}
}

var (
	// One champion block in the Lua table: ["Ahri"] = { ... ["apiname"] = "Ahri", ... ["date"] = "2011-12-14", ... }.
	// Blocks are separated by a line starting with a quoted key at two-space indent.
	blockRE   = regexp.MustCompile(`(?m)^  \["[^"]+"\]\s*=\s*\{`)
	apinameRE = regexp.MustCompile(`\["apiname"\]\s*=\s*"([^"]+)"`)
	dateRE    = regexp.MustCompile(`\["date"\]\s*=\s*"(\d{4})-\d{2}-\d{2}"`)
)

func printSeasons(ctx context.Context, base string) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, wikiURL, nil)
	req.Header.Set("User-Agent", "undercover-catalogtool/1.0 (+https://github.com/JarneClaesen/undercoverLeague)")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("wiki: %s", res.Status)
	}
	lua, err := io.ReadAll(res.Body)
	if err != nil {
		return err
	}

	seasons := map[string]int{}
	starts := blockRE.FindAllIndex(lua, -1)
	for i, loc := range starts {
		end := len(lua)
		if i+1 < len(starts) {
			end = starts[i+1][0]
		}
		block := lua[loc[0]:end]
		api := apinameRE.FindSubmatch(block)
		date := dateRE.FindSubmatch(block)
		if api == nil || date == nil {
			continue
		}
		year, _ := strconv.Atoi(string(date[1]))
		seasons[string(api[1])] = catalog.SeasonOfYear(year)
	}
	if len(seasons) == 0 {
		return fmt.Errorf("wiki: no champion blocks parsed")
	}

	// Cross-check against Data Dragon so a renamed apiname is noticed.
	f := catalog.NewFetcher(base)
	versions, err := f.Versions(ctx)
	if err != nil {
		return err
	}
	bySeason, current := catalog.SeasonVersions(versions)
	champs, err := f.Champions(ctx, bySeason[current])
	if err != nil {
		return err
	}
	out := map[string]int{}
	for id := range champs {
		s, ok := seasons[id]
		if !ok {
			fmt.Fprintf(os.Stderr, "warning: %s not found on the wiki; it will be tagged as season %d at runtime\n", id, current)
			continue
		}
		out[id] = s
	}
	for id := range seasons {
		if _, ok := champs[id]; !ok {
			fmt.Fprintf(os.Stderr, "note: wiki entry %q is not a Data Dragon champion, skipped\n", id)
		}
	}
	return printJSON(out)
}

func printDump(ctx context.Context, base, overrides string) error {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	svc := catalog.New(catalog.NewFetcher(base), nil, overrides, log)
	c, err := svc.Refresh(ctx)
	if err != nil {
		return err
	}
	return printJSON(c)
}

func printJSON(v any) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if m, ok := v.(map[string]int); ok {
		// Sorted keys make the diff reviewable.
		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		fmt.Println("{")
		for i, k := range keys {
			sep := ","
			if i == len(keys)-1 {
				sep = ""
			}
			fmt.Printf("  %q: %d%s\n", k, m[k], sep)
		}
		fmt.Println("}")
		return nil
	}
	return enc.Encode(v)
}
