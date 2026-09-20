# Undercover League

A party game for 3+ players: everyone gets the same League of Legends
champion or item except the Undercover, who has to blend in. Flutter app
(Android, iOS, web, desktop) talking over a WebSocket to a small Go server.

- Play in the browser: https://undercover.jarneclaesen.be
- Server code: [`server/`](server/) — Go, SQLite, no other dependencies.

## Layout

| Path | What |
|---|---|
| `lib/` | Flutter app. `services/game_connection.dart` owns the socket; `services/lobby_service.dart` sends commands; screens render `models/lobby.dart`. `theme/` holds the Hextech design tokens (colours, type, motion) and `widgets/` the shared Hextech components; fonts are bundled under `assets/fonts/` (OFL). |
| `server/internal/game` | Game rules (pure, table-tested), the `Catalog` value type and the host's `Filter`. |
| `server/internal/catalog` | Builds the word pool from Riot's Data Dragon: champions with release seasons, one item snapshot per season, tiers; cached in SQLite, embedded `fallback.json` for offline boots, `champion_seasons.json` static table. |
| `server/internal/hub` | Live lobbies: who is connected, disconnect grace, persistence, per-player broadcasts. |
| `server/internal/ws` | WebSocket transport and message shapes. |
| `server/cmd/undercover` | The server binary: `/ws`, `/healthz`, `/catalog` (the current pool as JSON), and the Flutter web build at `/`. |
| `server/cmd/catalogtool` | Regenerates the embedded catalog files (`-seasons`, `-dump`). |
| `server/deploy` | `docker-compose.yml`, `deploy.sh` and `catalog_overrides.json` (hand curation of the imported pool). |

All game logic runs on the server; clients only see their own role, and
the Undercover never receives the word. Creating a lobby with an empty
code makes the server pick a 5-letter one; after every vote the tallied
ballot is sent to everyone as `lastVotes` so the app can replay it. Dropped connections keep their
seat for 45 s and resume with a token; rejoining under the same name also
takes the seat back.

### Word pool

Champions and items come from [Data Dragon](https://developer.riotgames.com/docs/lol#data-dragon),
fetched by the server at start and every 12 h, so a new champion shows up
without an app release. Pictures are Data Dragon URLs (loading-screen art
for champions, versioned item icons, so removed items keep theirs). The
host filters the pool per lobby: champions by release season, items by
the seasons they were in the Summoner's Rift shop (S3 = 2013 is the
oldest Data Dragon has) and by tier (starter, consumables & trinkets,
boots, components, legendary). Everyone in the lobby sees the settings
and the resulting counts; the host's last choice is remembered on the
device.

The import is heuristic (Riot flags some Arena items as Rift items, and
transformed items like Muramana as unpurchasable), so
`server/deploy/catalog_overrides.json` corrects it: `items.exclude`,
`items.excludeSeasons` (name → seasons to drop), `items.include`
(name, icon, tier, `[from, to]` seasons), `items.tiers` (name → tier),
`champions.exclude` (display names) and `champions.seasons` (Data Dragon
id → season). Names match case-insensitively. Check the result at
`/catalog`; the file is re-read on every refresh, and `SKIP_WEB=1 sh
server/deploy/deploy.sh` ships an edit. Champions missing from
`champion_seasons.json` get the current season and are remembered in
SQLite; regenerate the table with `go run ./cmd/catalogtool -seasons`
and the offline fallback with `go run ./cmd/catalogtool -dump`.

## Local development

Server (needs Go):

```bash
cd server
go test ./...
UNDERCOVER_DB=./dev.db UNDERCOVER_WEB_DIR=../build/web UNDERCOVER_ADDR=127.0.0.1:8080 go run ./cmd/undercover
```

App against the local server:

```bash
flutter run -d chrome --dart-define=UNDERCOVER_WS_URL=ws://localhost:8080/ws
```

On an Android emulator use `ws://10.0.2.2:8080/ws` (debug builds allow
cleartext to that host only; see `android/app/src/debug/res/xml/`). Without
the define, web builds connect to the origin they were served from and
native builds to `wss://undercover.jarneclaesen.be/ws`.

`go run ./cmd/wsprobe -url ws://localhost:8080/ws -create -lobby t1 -name Alice`
opens a raw session for poking the protocol by hand.

Server settings (env): `UNDERCOVER_ADDR` (`:8080`), `UNDERCOVER_DB`
(`/data/undercover.db`), `UNDERCOVER_GRACE` (`45s`), `UNDERCOVER_WEB_DIR` (`/web`),
`UNDERCOVER_CATALOG_REFRESH` (`12h`; `0` never fetches, handy offline),
`UNDERCOVER_CATALOG_OVERRIDES` (`/config/catalog_overrides.json`; locally
pass `deploy/catalog_overrides.json`), `UNDERCOVER_DDRAGON` (base URL).
`/healthz` reports the catalog's patch and where it came from
(`embedded`, `cache` or `ddragon`).

## Deploying

```bash
sh server/deploy/deploy.sh
```

builds the web app, ships `server/` to `/opt/undercover` on the Hetzner
server and rebuilds the container there. The container joins the
`phonetracker_default` Docker network and is reached only through that
stack's Caddy (`undercover.jarneclaesen.be { reverse_proxy undercover:8080 }`
in its Caddyfile — kept in both the phonetracker repo and `/opt/phonetracker`).
Lobbies live in a named volume and survive redeploys; clients reconnect
within seconds.

## Tests

```bash
cd server && go vet ./... && go test ./...
flutter analyze && flutter test
```
