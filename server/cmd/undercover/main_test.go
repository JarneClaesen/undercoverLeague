package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/game"
)

func TestWebHandlerCacheHeaders(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"index.html", "flutter_bootstrap.js", "main.dart.js", "main.dart.wasm", "main.dart.mjs", "version.json"} {
		if err := os.WriteFile(filepath.Join(dir, f), []byte(f), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	h := webHandler(dir)

	cases := map[string]string{
		"/":                     "no-store",
		"/index.html":           "no-store",
		"/flutter_bootstrap.js": "no-store",
		"/version.json":         "no-store",
		"/main.dart.js":         "no-cache",
		"/main.dart.wasm":       "no-cache",
		"/main.dart.mjs":        "no-cache",
		"/lobby/ABCDE":          "no-store", // route fallback serves index.html
	}
	for url, want := range cases {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, url, nil))
		if got := rec.Header().Get("Cache-Control"); got != want {
			t.Errorf("%s: Cache-Control = %q, want %q", url, got, want)
		}
	}
}

// The wasm build needs exact types: WebAssembly.compileStreaming rejects
// anything but application/wasm and the ES-module import of main.dart.mjs
// needs a JavaScript type, whatever the host's mime tables say.
func TestWebHandlerWasmContentTypes(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"main.dart.wasm", "main.dart.mjs", "main.dart.js"} {
		if err := os.WriteFile(filepath.Join(dir, f), []byte(f), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	h := webHandler(dir)

	cases := map[string]string{
		"/main.dart.wasm": "application/wasm",
		"/main.dart.mjs":  "text/javascript",
		"/main.dart.js":   "text/javascript",
	}
	for url, want := range cases {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, url, nil))
		if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, want) {
			t.Errorf("%s: Content-Type = %q, want prefix %q", url, got, want)
		}
	}
}

func TestDailyHandler(t *testing.T) {
	c := &game.Catalog{Champions: []game.Champion{
		{Name: "Ahri", Icon: "https://x", Season: 1, Tags: []string{"Mage"}, Region: "Ionia"},
		{Name: "Yasuo", Icon: "https://x", Season: 3, Tags: []string{"Fighter"}, Region: "Ionia"},
	}}
	day := time.Date(2026, 9, 20, 12, 0, 0, 0, time.UTC)
	h := dailyHandler(func() *game.Catalog { return c }, func() time.Time { return day })

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/daily", nil))
	if rec.Code != http.StatusOK || rec.Header().Get("Cache-Control") != "no-cache" || rec.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("status %d headers %v", rec.Code, rec.Header())
	}
	var th game.Theme
	if err := json.Unmarshal(rec.Body.Bytes(), &th); err != nil {
		t.Fatal(err)
	}
	want := c.DailyTheme(day)
	if th.ID == "" || th.ID != want.ID || th.Title != want.Title || len(th.Filter.Packs) == 0 {
		t.Errorf("got %+v, want %+v", th, want)
	}

	// Before the first catalog there is nothing to pick from: still valid JSON.
	rec = httptest.NewRecorder()
	dailyHandler(func() *game.Catalog { return nil }, time.Now).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/daily", nil))
	if rec.Code != http.StatusOK || !json.Valid(rec.Body.Bytes()) {
		t.Errorf("nil catalog: %d %s", rec.Code, rec.Body.String())
	}
}
