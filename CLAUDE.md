# Undercover League — working notes

Party game for 3+ players (League of Legends champions/items). Everyone gets
the same word except the Undercover, who has to blend in. Flutter app for
Android/iOS/web/desktop; game state lives on a small Go server.

- Production: https://undercover.jarneclaesen.be (web build at `/`, WebSocket at `/ws`)
- Repo: https://github.com/JarneClaesen/undercoverLeague (branch `master`)
- The README covers the user-facing basics; this file is the system runbook.

## Architecture in one paragraph

One Go process per deployment. Clients open a single WebSocket, send JSON
commands, and receive a **per-player view** of their lobby after every
change. All rules run on the server (`server/internal/game`, pure and
table-tested). The hub (`server/internal/hub`) maps connections to seats,
keeps a disconnect grace timer per seat, persists every mutation to SQLite
and broadcasts views. The Flutter side is a thin layer: one connection
singleton, one typed model, screens rendering whatever view arrives. There
is no auth; identity is (lobby ID, player name) plus a per-session resume
token. Firebase was removed entirely in Sept 2026 (commits `bfdfc2f`, `03fffac`).

## Repository layout

```
lib/
  main.dart                       no init needed; just runApp
  models/lobby.dart               Lobby.fromJson — the per-player view
  services/game_connection.dart   the singleton WebSocket (connect/request/send/leave, resume with backoff)
  services/lobby_service.dart     command layer used by screens; static name/lobby validators
  screens/                        home (create/join), lobby, game (phase switch), player_role, round, voting
  widgets/                        role_card, responsive_layout, connection_banner ("Reconnecting…")
test/data_test.dart               checks words.json against the bundled icon assets
server/
  go.mod                          module github.com/JarneClaesen/underCoverLeague/server (Go 1.27)
  cmd/undercover/main.go          HTTP server: /ws, /healthz, static web at /; -healthcheck flag; purge loop
  cmd/wsprobe/main.go             hand-driven client for poking the protocol
  internal/game/                  Lobby state machine, View, DrawWord/DrawRoles, words.json (167 champions, 202 items)
  internal/hub/                   rooms, seats, grace timers, tokens, persistence, broadcast
  internal/store/                 SQLite (modernc, pure Go): lobbies(id, state JSON, updated_at)
  internal/ws/                    coder/websocket handler, Command struct, dispatch
  Dockerfile                      multi-stage → distroless static, runs vet+test during build
  deploy/docker-compose.yml       project `undercover`, joins external network phonetracker_default
  deploy/deploy.sh                flutter build web → tar server/ to the box → docker compose up --build
  web/                            (gitignored) Flutter web build staged by deploy.sh, copied into the image
assets/champions, assets/items    icons; the server only knows their paths, clients bundle them
```

## Game model (`server/internal/game/lobby.go`)

Fields keep the old Firestore names so the client model barely changed:
`host, players, gameStarted, gamePhase, roles, selectedWord, selectedIcon,
selectedIsChampion, alivePlayers, roundOrder, currentPlayerIndex,
roundFinished, votes, rolesAcknowledged, winner, lastEliminated`, plus
`sessions` (token → player, never sent) and `version` (monotonic per lobby).

Phases: `lobby → revealingRoles → playing → gameOver → (Reset) lobby`.
Inside `playing`, `roundFinished=false` is describing, `true` is voting.

| Command | Rule |
|---|---|
| Join | rejected `inProgress` once started, `nameTaken` if the name exists |
| Start (host only) | ≥3 players, ≥1 category; coin-flip category then uniform word; shuffle order, uniform Undercover; double tap is a no-op |
| Acknowledge | only players in the game; when all acked → `playing`, index 0 (server-driven) |
| NextPlayer(expectedIndex) | CAS on index **and** caller must be the current player; last in order sets `roundFinished` |
| Vote(target) | only during voting, voter alive, target alive or `"skip"`, not self; re-vote allowed |
| Tally (server-driven once all alive voted) | count votes for alive targets; eliminate iff one leader with `max>0 && max>skips`; ties/skips eliminate nobody (`lastEliminated=""`); reshuffle order; Civilians win when no Undercover alive, Undercover wins at ≤2 alive |
| Leave | host → lobby deleted for everyone; else remove from every list/map, `currentPlayerIndex--` if leaver was before it, finish the round if they were last, re-check the winner |
| Reset (host only) | back to `lobby` with the same players |

`Advance()` runs after every mutation (including leaves) and loops the two
server-driven transitions until nothing changes.

`ViewFor(player)` strips secrets: `myRole` (Civilian/Undercover/Spectator),
`myWord` (nil for the Undercover until game over), `myIcon`; `roles` and
`selectedWord` only at `gameOver`; `connected[player]` for grey-out UI.

## Hub semantics (`server/internal/hub/hub.go`)

- **One global mutex.** Every mutation = apply → Advance → version++ →
  SQLite upsert → broadcast, all under the lock. Sends are non-blocking
  (32-slot buffer per connection); a client that can't keep up is closed
  and treated as disconnected.
- **Tokens.** Create/Join issue a 16-byte hex token stored in
  `sessions`; `resume(lobbyId, token)` rebinds a new socket. Newest
  connection wins; the old one is closed as "superseded".
- **Disconnect grace = 45 s** (`UNDERCOVER_GRACE`). A read-loop exit
  without `leave` starts a timer for the seat; expiry runs the Leave logic.
  Server pings every 25 s so dead mobile sockets are noticed within ~35 s.
- **Seat takeover.** Joining under a name that is seated but disconnected
  revokes the old tokens and hands the seat over (works mid-game and after
  a restart). Accepted trade-off: anyone with lobby ID + name can take a
  disconnected seat.
- **Restart.** Lobbies are lazily loaded from SQLite on first
  join/resume/create; every seat then starts a grace timer so abandoned
  games resolve themselves. Rooms leave memory when they have no
  connections and no timers; rows idle >24 h are purged hourly.
- **Host leaving/expiring** deletes the row and sends `lobbyClosed` to all.

## Wire protocol (JSON text frames on `/ws`)

Client → server (`Command`):
```
{"type":"create","reqId":1,"lobbyId":"t1","name":"Alice"}
{"type":"join","reqId":2,"lobbyId":"t1","name":"Bob"}
{"type":"resume","reqId":3,"lobbyId":"t1","token":"…"}
{"type":"start","useChampions":true,"useItems":true}
{"type":"ack"}  {"type":"nextPlayer","expectedIndex":2}  {"type":"vote","votedFor":"Bob"|"skip"}
{"type":"reset"}  {"type":"leave"}
```
Server → client (`hub.Event`):
```
{"type":"joined","reqId":1,"token":"…","lobbyId":"t1","playerName":"Alice","isHost":true}
{"type":"lobby","lobby":{…View…}}          after every change, one per connection
{"type":"error","reqId":1,"code":"…","message":"…"}   codes: notFound exists inProgress nameTaken notHost expired invalid
{"type":"lobbyClosed"}
```
`reqId` is echoed only on `joined`/`error` so create/join/resume can be
awaited; other rejections arrive as `error` without `reqId` and the client
shows them as a snackbar. Frames are capped at 4 KB. Origin is deliberately
not checked (no cookies, token is in-band, native apps send none).

## Flutter client

- `GameConnection.instance` is the only socket. `request()` awaits by
  `reqId` (10 s timeout); `send()` is fire-and-forget. On an unexpected
  close with a session it resumes with backoff 1,2,4,8,16,16,16 s; `expired`/
  `notFound` or giving up emits `null` on the lobby stream, which is the
  "lobby gone" signal the screens already navigate on. `takeCloseReason()`
  lets HomeScreen show why ("closed" / "expired" / "unreachable").
- URL: `--dart-define=UNDERCOVER_WS_URL` overrides; otherwise web derives
  `ws(s)://<origin>/ws`, native uses `wss://undercover.jarneclaesen.be/ws`.
- `StreamBuilder<Lobby?>` with `initialData: currentLobby`; check
  `snapshot.data` first, then `connectionState == waiting` for the spinner,
  else treat as closed.
- Screens never call the server for phase transitions anymore; the two
  host-driven transitions from the Firebase era are server-side.
- Android: `INTERNET` permission is declared explicitly; debug builds allow
  cleartext to `10.0.2.2`/`localhost` only. macOS has `network.client`.

## Local development

```bash
export PATH="$PATH:/c/Program Files/Go/bin"          # Go is not on the Bash PATH on this machine
cd server && go vet ./... && go test ./...           # -race needs cgo/gcc, unavailable locally; the Docker build runs the tests
UNDERCOVER_DB=./dev.db UNDERCOVER_WEB_DIR=../build/web UNDERCOVER_ADDR=127.0.0.1:8080 UNDERCOVER_GRACE=20s go run ./cmd/undercover
flutter run -d chrome --dart-define=UNDERCOVER_WS_URL=ws://localhost:8080/ws
go run ./cmd/wsprobe -url ws://localhost:8080/ws -create -lobby t1 -name Alice   # then type raw JSON commands
flutter analyze && flutter test
```

Env: `UNDERCOVER_ADDR` (`:8080`), `UNDERCOVER_DB` (`/data/undercover.db`),
`UNDERCOVER_GRACE` (`45s`), `UNDERCOVER_WEB_DIR` (`/web`; static serving is
skipped if the dir is missing). Static responses are `Cache-Control: no-cache`;
extension-less unknown paths fall back to `index.html`.

Word list: `server/internal/game/words.json` is the single source (go:embed).
`test/data_test.dart` verifies every icon path exists under `assets/`.

## Production

**Server:** Hetzner box, `ssh hetzner` (root@62.238.106.224, key
`~/.ssh/phonetracker_ed25519`; IPv6 `2a01:4f9:c014:5795::1`). Ubuntu 26.04,
2 vCPU, 3.7 GB. It also hosts the phonetracker stack (`/opt/phonetracker`),
whose Caddy container owns ports 80/443 and does Let's Encrypt.

**Our stack:** `/opt/undercover` (compose project `undercover`, one service,
distroless image ~115 MB — mostly the Flutter web build). No published
ports; it joins the external network `phonetracker_default` with alias
`undercover`, and Caddy proxies to `undercover:8080`. Named volume
`undercover_undercover_data` holds the SQLite file. Healthcheck runs
`/undercover -healthcheck` (distroless has no curl).

**Caddy block** (must exist in BOTH `/opt/phonetracker/Caddyfile` on the
server and `C:\Users\Jarne\Development\phonetracker\Caddyfile`, because
phonetracker deploys by tar-unpacking that folder over `/opt/phonetracker`):
```
undercover.jarneclaesen.be {
	encode zstd gzip
	reverse_proxy undercover:8080
}
```

**DNS** (Hostinger / dns-parking): `undercover` A → 62.238.106.224 and AAAA →
2a01:4f9:c014:5795::1. The AAAA must point here (or not exist): Let's
Encrypt validates over IPv6 first, and an AAAA at Hostinger broke issuance
until fixed. Cert issued 2026-09-20, auto-renewed by Caddy.

### Deploy

```bash
sh server/deploy/deploy.sh              # flutter build web + upload + docker compose up -d --build
SKIP_WEB=1 sh server/deploy/deploy.sh   # server-only change, reuse build/web
ssh hetzner "cd /opt/undercover/deploy && docker compose logs -f"
```
Games survive a redeploy: state is in the volume, clients resume within
seconds. First image build on the box takes a few minutes (modernc sqlite);
BuildKit cache mounts make later builds fast.

### Gotchas learned the hard way

- **Caddyfile bind mount is pinned to an inode.** `scp`/tar replacing the
  file leaves the container reading the old one; `caddy reload` logs
  "config is unchanged". Recreate instead:
  `docker compose -f docker-compose.prod.yml up -d --force-recreate --no-deps caddy`.
- **Verify DNS and do smoke tests from the server**, not from this Windows
  machine: the ISP transparently caches DNS, so local lookups (even against
  authoritative servers) lag for a long time and local curl/wsprobe may hit
  the wrong host.
- Compose healthcheck `test` must start with `"CMD"`.
- `server/**` is forced to LF via `.gitattributes`; `deploy.sh` would
  break on the box with CRLF.
- Browser-testing the Flutter web build with the in-app browser: clicks on
  the canvas land reliably only right after a screenshot, and background
  tabs don't advance frames. That is the automation, not the app.

## Conventions

- Keep `internal/game` free of I/O; put rules there with a table test.
  Anything touching connections, timers or persistence belongs in `hub`.
- Guards that used to be silent no-ops in the Firebase code (double taps,
  stale indexes) stay silent; new authorisation checks return `invalid`/`notHost`.
- JSON field names on the view are a contract with `lib/models/lobby.dart`;
  change both together and bump nothing else — clients tolerate missing fields.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
