package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestWebHandlerCacheHeaders(t *testing.T) {
	dir := t.TempDir()
	for _, f := range []string{"index.html", "flutter_bootstrap.js", "main.dart.js", "version.json"} {
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
