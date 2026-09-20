# Undercover League — notes for Claude

Flutter app + Go server; see `README.md` for layout, local dev and deploy.
Checks: `flutter analyze && flutter test` and `cd server && go vet ./... && go test ./...`.
Deploy: `sh server/deploy/deploy.sh` (add `SKIP_WEB=1` to reuse the last `flutter build web`).

## Web build cache refresh (keep this working)

Every deploy must replace what browsers already hold. Two pieces do that:

1. **Server headers** — `webHandler`/`cacheControl` in `server/cmd/undercover/main.go`
   serve `index.html`, `/`, `flutter_bootstrap.js`, `flutter_service_worker.js` and
   `version.json` as `Cache-Control: no-store`, everything else as `no-cache`
   (kept, revalidated on every load). `main_test.go` pins these.
2. **Loader in `web/index.html`** — instead of `<script src="flutter_bootstrap.js">`,
   an inline script first checks for a service worker (old Flutter builds shipped a
   caching one that answers fetches from its cache regardless of fetch options): if
   one is registered or still controls the page it unregisters it, deletes all
   Cache Storage caches and reloads once (guarded by `sessionStorage`). It then
   fetches `flutter_bootstrap.js?t=<now>` with `cache: 'no-store'` (the query keeps a
   lingering worker from matching its cache), hashes the text and compares it with
   `localStorage['undercover.build']`. On a change it clears caches again, refetches
   the core files (`main.dart.js`, `flutter.js`, the asset/font manifests,
   `MaterialIcons-Regular.otf`) with `cache: 'reload'` so the HTTP cache is
   overwritten, stores the new hash, and only then runs the bootstrap inline. If the
   fetch fails it falls back to a plain script tag.

Rules: don't reintroduce a plain bootstrap `<script>` tag; if Flutter adds another
unhashed core file that changes between builds, add it to the `CORE` list; keep the
`no-store` set in sync with the loader. Verified on 2026-09-20 with Flutter 3.47.5,
whose `flutter_service_worker.js` is a self-unregistering stub (no caching).
CanvasKit comes from gstatic under an engine-revision URL, so it needs no handling.

## Design system

- Tokens live in `lib/theme/` (`HextechColors`, `hextechTextTheme`, `Motion`,
  `hextechTheme()`); shared components in `lib/widgets/` (`Hextech*`, `PlayerTile`,
  `RevealCard`, `PhaseHeader`, `PhaseSwitcher`, `StatusNotice`, `ReadyMeter`,
  `TurnOrderStrip`, `VoteTile`). Use them; no hard-coded colours or font sizes in
  screens, and every animation checks `Motion.reduced(context)`.
- Fonts are bundled variable TTFs under `assets/fonts/` (Cinzel, Source Sans 3, OFL);
  weights are chosen with `FontVariation('wght', …)` in `app_text.dart`.
- `GameScreen` is the shell: it owns the lobby stream and switches phase bodies via
  `PhaseSwitcher`; the compact peek card is its footer during rounds and voting.
- Privacy: the server broadcasts the live `votes` map to everyone during voting.
  Screens may only use `containsKey` and the viewer's own entry until the tally;
  `lastVotes` (sent after the tally) is the one that may be shown in full.

## Server contract notes

- All game rules run in `server/internal/game`; the client only renders `View`.
- The word pool is a `game.Catalog` built by `server/internal/catalog` from
  Data Dragon (see README "Word pool"); `internal/game` never does I/O, the
  hub holds the catalog in an `atomic.Pointer` and `catalog.Service.Run`
  swaps it. Icons are https URLs; only `assets/default_icon.jpg` is bundled.
- `{"type":"settings","settings":{…Filter…}}` is a host-only lobby mutation;
  `start` has no payload. The view carries `settings` (normalized), and in
  the lobby phase `poolSize` and `seasonRange`. Zero season bounds mean
  "all"; `itemTiers` null = all, `[]` = none. `lib/models/game_settings.dart`
  mirrors this.
- Item names are the identity across seasons (case-insensitive); Data
  Dragon champion ids key `champion_seasons.json` and
  `champions.seasons` in the overrides, display names key the excludes.
- `create` with an empty `lobbyId` returns a generated 5-letter code in the
  `joined` event; the client reads it from `GameConnection.session.lobbyId`.
- `lastVotes` is the tallied ballot of the previous vote; `lastEliminated` is
  `null` before the first vote, `""` for no elimination, else a name.
