// Command undercover is the Undercover League game server: a WebSocket
// endpoint at /ws, a health probe at /healthz and, when a web directory is
// present, the Flutter web build at /.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/JarneClaesen/underCoverLeague/server/internal/hub"
	"github.com/JarneClaesen/underCoverLeague/server/internal/store"
	"github.com/JarneClaesen/underCoverLeague/server/internal/ws"
)

const (
	purgeInterval = time.Hour
	purgeAfter    = 24 * time.Hour
)

func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe the running server and exit (for the container healthcheck)")
	flag.Parse()

	addr := env("UNDERCOVER_ADDR", ":8080")
	if *healthcheck {
		os.Exit(probe(addr))
	}

	log := slog.New(slog.NewTextHandler(os.Stdout, nil))
	dbPath := env("UNDERCOVER_DB", "/data/undercover.db")
	webDir := env("UNDERCOVER_WEB_DIR", "/web")
	grace, err := time.ParseDuration(env("UNDERCOVER_GRACE", "45s"))
	if err != nil {
		log.Error("bad UNDERCOVER_GRACE", "err", err)
		os.Exit(2)
	}

	st, err := store.Open(dbPath)
	if err != nil {
		log.Error("open database", "path", dbPath, "err", err)
		os.Exit(1)
	}
	defer st.Close()

	h := hub.New(st, grace, log)

	mux := http.NewServeMux()
	mux.Handle("/ws", &ws.Handler{Hub: h, Log: log})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := st.Ping(); err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ok")
	})
	if info, err := os.Stat(webDir); err == nil && info.IsDir() {
		mux.Handle("/", webHandler(webDir))
		log.Info("serving web build", "dir", webDir)
	}

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go purgeLoop(ctx, st, h, log)

	go func() {
		log.Info("listening", "addr", addr, "db", dbPath, "grace", grace)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("serve", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	log.Info("shutting down")
	// Closing the sockets first makes clients reconnect straight into the
	// next process instead of waiting for the listener to drain.
	h.Shutdown()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(shutdownCtx)
}

// webHandler serves the Flutter web build. Anything that is not an existing
// file and looks like a route falls back to index.html. The entry files that
// decide which build runs are never stored by the browser; everything else
// is no-cache (kept, but revalidated on every load) so a deploy is picked up
// on the next visit. index.html's loader does the rest for browsers that
// still hold copies from before these headers existed.
func webHandler(dir string) http.Handler {
	fs := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := path.Clean("/" + r.URL.Path)
		full := filepath.Join(dir, filepath.FromSlash(p))
		if info, err := os.Stat(full); err != nil || info.IsDir() && p != "/" {
			if path.Ext(p) == "" {
				r.URL.Path = "/"
				p = "/"
			}
		}
		w.Header().Set("Cache-Control", cacheControl(p))
		fs.ServeHTTP(w, r)
	})
}

// cacheControl picks the caching policy for one path of the web build.
func cacheControl(p string) string {
	switch p {
	case "/", "/index.html", "/flutter_bootstrap.js", "/flutter_service_worker.js", "/version.json":
		return "no-store"
	}
	return "no-cache"
}

func purgeLoop(ctx context.Context, st *store.Store, h *hub.Hub, log *slog.Logger) {
	t := time.NewTicker(purgeInterval)
	defer t.Stop()
	for {
		n, err := st.Purge(time.Now().Add(-purgeAfter), h.LiveIDs())
		if err != nil {
			log.Error("purge", "err", err)
		} else if n > 0 {
			log.Info("purged stale lobbies", "count", n)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func probe(addr string) int {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return 1
	}
	if host == "" {
		host = "127.0.0.1"
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://" + net.JoinHostPort(host, port) + "/healthz")
	if err != nil || resp.StatusCode != http.StatusOK {
		return 1
	}
	resp.Body.Close()
	return 0
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}
