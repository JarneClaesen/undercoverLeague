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
   an inline script fetches the bootstrap with `cache: 'no-store'`, hashes its text
   and compares it with `localStorage['undercover.build']`. On a change it
   unregisters any service worker (old Flutter builds shipped a caching one; if one
   was registered it reloads the page once, guarded by `sessionStorage`), deletes
   all Cache Storage caches, refetches the core files (`main.dart.js`, `flutter.js`,
   the asset/font manifests, `MaterialIcons-Regular.otf`) with `cache: 'reload'` so
   the HTTP cache is overwritten, stores the new hash, and only then runs the
   bootstrap inline. If the fetch fails it falls back to a plain script tag.

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
- `create` with an empty `lobbyId` returns a generated 5-letter code in the
  `joined` event; the client reads it from `GameConnection.session.lobbyId`.
- `lastVotes` is the tallied ballot of the previous vote; `lastEliminated` is
  `null` before the first vote, `""` for no elimination, else a name.
