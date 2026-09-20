# Undercover League — notes for Claude

Flutter app + Go server; see `README.md` for layout, local dev and deploy.
Checks: `flutter analyze && flutter test` and `cd server && go vet ./... && go test ./...`.
Deploy: `sh server/deploy/deploy.sh` (add `SKIP_WEB=1` to reuse the last `flutter build web`).
The web build is `--wasm` (dart2wasm + skwasm, dart2js fallback picked by `flutter.js`).
No COOP/COEP headers on purpose: skwasm runs single-threaded without cross-origin
isolation, and `require-corp` would block the Data Dragon icons.

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
  `hextechTheme()`); shared components in `lib/widgets/` (`Hextech*` incl.
  `HextechChip`, `HextechExpander`, `PlayerTile`, `RevealCard`, `WordCard`,
  `PhaseHeader`, `PhaseSwitcher`, `StatusNotice`, `ReadyMeter`, `TurnOrderStrip`,
  `VoteTile`, `TurnTimer`, `ClueLog`, `ReactionBar`/`ReactionOverlay`,
  `RevealSequence`, `AchievementBadge`, `ScoreRow`, `LobbyRules`, `LobbyFilters`,
  `LobbyPoolToggles`, `DailyThemeCard`, `HomeThemeBanner`, `showLobbyQrDialog`,
  `MotionSize`). Use them; no hard-coded colours or font sizes in screens, and
  every animation checks `Motion.reduced(context)`.
- Never use `AnimatedSize` directly: it asserts on `Duration.zero`, which
  `Motion.of` yields under reduced motion. `MotionSize` (`lib/widgets/motion_size.dart`)
  wraps it and swaps the child outright when motion is reduced.
- Fonts are bundled variable TTFs under `assets/fonts/` (Cinzel, Source Sans 3, OFL);
  weights are chosen with `FontVariation('wght', …)` in `app_text.dart`. Emoji come
  from the web engine's fallback font, fetched on first use: `ReactionOverlay` lays
  out the whole `reactionEmoji` set offstage at mount so the first reaction is not
  a tofu box.
- `GameScreen` is the shell: it owns the lobby stream and switches phase bodies via
  `PhaseSwitcher`; the compact peek card is its footer during rounds, voting and
  while waiting for a last guess; `ReactionOverlay` sits over every phase. Host-ness
  is derived from the live view (`lobby.host == playerName`), never from a
  constructor argument, because "play again" can rotate the seat; the device's
  remembered host settings are only pushed by the player who created the lobby.
- Word-kind labels ("your champion / item / ability…") come from
  `WordPack.noun(lobby.selectedPack, 1)`; `isChampion` only decides the art
  layout (portrait art vs. sprite on a glow).
- Privacy: the server broadcasts the live `votes` map to everyone during voting.
  Screens may only use `containsKey` and the viewer's own entry until the tally;
  `lastVotes` (sent after the tally) is the one that may be shown in full.
  Spectators (lobby `spectators`, role `Spectator`) see the word but never the
  roles until game over. Reactions are ephemeral: they arrive on
  `GameConnection.reactions`, are never in the view and are never replayed.

## Server contract notes

- All game rules run in `server/internal/game`; the client only renders `View`.
- The word pool is a `game.Catalog` built by `server/internal/catalog` from
  Data Dragon (see README "Word pool"); `internal/game` never does I/O, the
  hub holds the catalog in an `atomic.Pointer` and `catalog.Service.Run`
  swaps it. Icons are https URLs; only `assets/default_icon.jpg` is bundled.
- Packs: `champions items spells runes abilities skinlines monsters`
  (`game.AllPacks`). `Filter{packs, champSeasons, itemSeasons, itemTiers,
  champClasses, champRegions, champRanges, champResources, champDamage,
  champDifficulty}`; legacy `useChampions/useItems` JSON is mapped onto
  `packs` by `Filter.UnmarshalJSON`. Zero season bounds mean "all";
  `itemTiers` null = all, `[]` = none; every champion list empty = all.
  The four bucket lists take the fixed enums `game.AllRanges` (`melee
  ranged`), `AllResources` (`mana energy none other`), `AllDamages`
  (`physical magic mixed`) and `AllDifficulties` (`easy medium hard`),
  matched case-insensitively and echoed back canonical. Each `Champion`
  carries `range resource damage difficulty`, set by
  `catalog.classifyChampion` from `championFull.json` (`damage` and
  `difficulty` are `""` for the few champions without Riot ratings, which
  then match no damage/difficulty filter).
- `game.Settings` embeds `Filter` (JSON flattened) plus `undercovers` (>= 1),
  `mrWhites` (needs `decoyWord`), `decoyWord`, `randomOrder` (default false;
  `Settings.UnmarshalJSON` exists because the embedded Filter's would
  otherwise be promoted), `turnSeconds` (0 or 10..300), `clueLog`,
  `rotateHost`. `{"type":"settings","settings":{…Settings…}}` is host-only in
  the lobby; `Start` also requires `2*(undercovers+mrWhites) < active players`.
  `lib/models/game_settings.dart` mirrors this.
- The view carries `settings` (normalized) and, in the lobby phase only,
  `poolSize` (`{pack: count}`), `seasonRange`, `classes`, `regions`,
  `resources` (the resource buckets present, in `AllResources` order; the
  other three enums are fixed so the client hard-codes them) and
  `dailyTheme` (`{id,title,description,filter}`, also at `GET /daily`).
- Roles: `Civilian | Undercover | MrWhite | Spectator`. Undercovers get the
  decoy (`myWord` + `myDecoy: true`) when `decoyWord`, else nothing; Mr. White
  never gets a word; lobby spectators (`spectate{spectating}`, `spectators`
  in the view) see the word, are not in `alivePlayers`/`roundOrder` and are
  not counted for `MinPlayers`. At game over everyone gets `roles`,
  `selectedWord` and `decoyWord`. `selectedPack` names the drawn pack.
- Phases: `lobby → revealingRoles → playing → (lastGuess) → gameOver`.
  Eliminating a wordless player enters `lastGuess` with `guesser`; only they
  may `guess{word}` (case/punctuation-insensitive; abilities match "Charm" or
  "Charm (Ahri)"); `lastGuess {player,word,correct}` records it. Right ends
  the game (`winner` `MrWhite` or `Undercover`, `winReason` `guess`); wrong or
  the guesser leaving/timing out resumes. `winReason` is otherwise
  `eliminated` (no impostor alive) or `outnumbered` (impostors >= civilians).
- Turns: `nextPlayer{expectedIndex}` ends a turn, or `clue{text,expectedIndex}`
  (<= 40 runes) when `clueLog` is on (`nextPlayer` is then rejected); `clues
  [{round,player,text}]` is public. `round` is 1-based. By default the Start
  order is kept and the first speaker rotates after each tally; `randomOrder`
  reshuffles instead.
- Timer: `deadline` (unix ms, 0 = none) is set per describing turn
  (`turnSeconds`), voting and last guess (2x). The hub arms one
  `time.AfterFunc` per room in `commit`, re-validated under the lock by
  deadline+version, and calls `Lobby.Expire` (turn ends with an empty clue,
  missing votes become skips, the guess is forfeited).
- `lastVotes` is the tallied ballot of the previous vote; `ballots` is every
  tally of this game; `lastEliminated` is `null` before the first vote, `""`
  for no elimination, else a name.
- `playAgain` (host, game over only) is `reset` plus, with `rotateHost`, the
  host seat moving to the next non-spectator in `players` order. `scores`,
  `gamesPlayed`, `stats {civilianSurvivals,impostorGames,games}` and
  `achievements {name: [sorted ids]}` are awarded once per game in
  `Lobby.finish` (`scoring.go`) and live as long as the lobby does.
- `react{emoji}` (allowlist `game.Reactions`, not from alive players, 700 ms
  per player) is relayed as `{"type":"reaction","playerName","emoji"}` to
  the room without persisting or bumping `version`.
- Item names are the identity across seasons (case-insensitive); Data
  Dragon champion ids key `champion_seasons.json`, `champion_regions.json`
  and `champions.seasons`/`champions.regions` in the overrides, display
  names key the excludes and `skinLines.exclude`.
- `create` with an empty `lobbyId` returns a generated 5-letter code in the
  `joined` event; the client reads it from `GameConnection.session.lobbyId`.
  `isHost` must be derived from `lobby.host` in the live view (it rotates).
