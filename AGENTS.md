# AGENTS.md

This file orients AI agents (Claude Code, Copilot, etc.) for this project. For full user-facing documentation see [README.md](README.md).

## What This Project Does

`video-extractor` crawls paginated video playlist pages using `yt-dlp`, saves metadata and thumbnails locally, and generates a searchable HTML catalog. Videos are not downloaded by default, but can be downloaded on-demand via the local catalog server.

Primary scripting layer is **PowerShell Core 7+** (`.ps1` files) — cross-platform on Linux, macOS, and Windows. Equivalent bash scripts (`.sh`) remain for reference but are superseded by the PS equivalents.

## Key Files

| File | Purpose |
|------|---------|
| `scripts/scrape.ps1` | **Primary** crawler (PS Core). Paginates any yt-dlp-supported URL, deduplicates via `@{}` hashtable, fetches metadata + thumbnails. Params: `-Force`, `-Parallel N`, `-Limit N`. Reads `$COOKIES_FILE` env var. |
| `scripts/scrape.sh` | Bash equivalent of `scrape.ps1`. Flags: `--force`, `--parallel N`, `--limit N`. |
| `scripts/build_catalog.py` | Reads all `metadata/*.info.json` and writes `catalog/catalog.html`. Surfaces title, duration, views, likes, tags. |
| `scripts/convert_cookies.py` | Converts Cookie-Editor JSON exports to Netscape format. Input: `cookies/cookies.json`. Output: `cookies/cookies.txt`. |
| `scripts/scrape_subscriptions.ps1` | **Primary** subscriptions scraper (PS Core). Fetches subscriptions page via cookie-authenticated Python HTTP, extracts channel profile URLs (domain-agnostic), runs `scrape.ps1` on each channel's `/videos` endpoint. Params: `-Limit N`, `-Parallel N`, `-Force`, `-Yes`. |
| `scripts/scrape_subscriptions.sh` | Bash equivalent of `scrape_subscriptions.ps1`. |
| `scripts/scrape_youtube.ps1` | **Primary** YouTube scraper (PS Core). Interactive: channel vs search, scope (all / last N / date range) or result count. No cookies for public content. Params: `-Parallel N`, `-Force`. |
| `scripts/scrape_youtube.sh` | Bash equivalent of `scrape_youtube.ps1`. |
| `scripts/serve.py` | `http.server` subclass serving the project root + two API endpoints: `GET /api/status?id=ID` and `GET /api/download?id=ID&url=URL`. Spawns yt-dlp in a background thread. Downloads land in `videos/`. |
| `scripts/serve.ps1` | Thin PS wrapper: sets project root as working dir then runs `python3 scripts/serve.py [port]`. Default port 8765. |
| `scripts/serve.sh` | Bash equivalent of `serve.ps1`. |
| `scripts/update.ps1` | One-shot PS wrapper: runs `scrape.ps1 @args` then `build_catalog.py`. |
| `scripts/update.sh` | Bash equivalent of `update.ps1`. |
| `scripts/check_thumbnails.ps1` | Finds metadata entries missing a local thumbnail and re-fetches them. |
| `scripts/check_thumbnails.sh` | Bash equivalent of `check_thumbnails.ps1`. |
| `scripts/clean.ps1` | Fetches live IDs from the playlist and removes local metadata/thumbnails for any ID no longer present. |
| `scripts/clean.sh` | Bash equivalent of `clean.ps1`. |
| `config.sh` | Commented-out per-source variables (`COOKIES_FILE`, `PARALLEL`, `URL`). Source before running bash scripts. |
| `sources.conf.ps1` | **Gitignored.** Personal playlist/subscription URLs for PowerShell (`$FAVORITES_URL`, `$SUBSCRIPTIONS_URL`). Copy from `sources.conf.ps1.example`. |
| `sources.conf.ps1.example` | Committed template for `sources.conf.ps1` with placeholder URLs. |
| `sources.conf` | **Gitignored.** Personal URLs for bash scripts. Copy from `sources.conf.example`. |
| `sources.conf.example` | Committed template for `sources.conf`. |
| `cookies/cookies.txt` | Netscape-format cookies passed to yt-dlp via `--cookies`. Expires with the browser session. |
| `metadata/` | One `.info.json` per video. Source of truth for catalog generation. |
| `thumbnails/` | One `.jpg` per video. Referenced by relative path from `catalog/catalog.html`. |
| `videos/` | **Gitignored.** Downloaded video files (MP4). Detected by `build_catalog.py` at build time; baked into `local_video` field in catalog JSON so Play button appears without the server. |

## Workflow

**PowerShell (primary):**
```powershell
export cookies → convert_cookies.py → scrape.ps1 → build_catalog.py → catalog.html
```

One-shot:
```powershell
. ./sources.conf.ps1
pwsh scripts/update.ps1 $FAVORITES_URL
```

To enable video downloads:
```powershell
pwsh scripts/serve.ps1   # serves at http://localhost:8765/catalog/catalog.html
```

**Bash (alternative):**
```bash
source sources.conf && bash scripts/update.sh "$FAVORITES_URL"
```

## Common Tasks

**Rebuild catalog:**
```bash
python3 scripts/build_catalog.py
```

**Crawl a playlist/tag/channel URL (skip existing):**
```powershell
. ./sources.conf.ps1
pwsh scripts/scrape.ps1 $FAVORITES_URL
pwsh scripts/scrape.ps1 -Limit 20 "https://example-platform.com/channel/NAME/videos"
```

**Force re-fetch all, 4 parallel workers:**
```powershell
pwsh scripts/scrape.ps1 -Force -Parallel 4 "https://example-platform.com/user/playlist"
```

**Scrape all subscriptions (5 new per channel, confirm first):**
```powershell
. ./sources.conf.ps1
pwsh scripts/scrape_subscriptions.ps1 $SUBSCRIPTIONS_URL -Limit 5 -Parallel 2
```

**Non-interactive subscription scrape:**
```powershell
. ./sources.conf.ps1
pwsh scripts/scrape_subscriptions.ps1 $SUBSCRIPTIONS_URL -Limit 10 -Yes
```

**Scrape a YouTube channel or search (interactive):**
```powershell
pwsh scripts/scrape_youtube.ps1
pwsh scripts/scrape_youtube.ps1 -Parallel 4 "https://www.youtube.com/@mkbhd"
```

**Start the local catalog server (enables video downloads):**
```powershell
pwsh scripts/serve.ps1
# http://localhost:8765/catalog/catalog.html
```

**Fix missing thumbnails after a partial run:**
```powershell
pwsh scripts/check_thumbnails.ps1
```

**Remove entries deleted from the playlist:**
```powershell
pwsh scripts/clean.ps1 "https://platform.com/user/playlist-url"
```

**Refresh cookies (do this when auth errors appear):**
1. Open browser, navigate to platform while logged in / VPN active
2. Export cookies as JSON via Cookie-Editor extension
3. `python3 scripts/convert_cookies.py cookies/cookies.json cookies/cookies.txt`

## Catalog Features (generated HTML)

- Search by title, sort by title/duration/views/likes
- Tag bar — collapsed by default, toggle with "Tags ▾" button; only shows tags that appear in 2+ videos
- Card-level tag chips — click any tag on a card to filter by it
- Star/favorite toggle — persisted in `localStorage`
- **Saved views** — "Views ▾" toolbar button opens a panel; name and save any search/sort/tag/favorite state; click to restore; overwrite by saving with the same name; delete individually. `localStorage` keys: `vcat_views` (named list), `vcat_last_state` (auto-saved on every filter change, restored on load)
- **Auto-restore last state** — `restoreLastState()` runs before the initial `applyFilters()` call so the catalog reopens in the same state
- Infinite scroll (batches of 50 cards via `IntersectionObserver`)
- Export current filtered view to JSON or CSV
- **Download button** on each card — triggers `serve.py` API to run yt-dlp in background; polls for completion; transitions to Play on success
- **In-page video player modal** — plays local file; original URL always preserved and linked from modal
- `build_catalog.py` bakes `local_video` path into catalog JSON if a file exists in `videos/` at build time — Play works without server after rebuild

## Known Issues & Solutions

### `Unable to extract title`
Geo-blocking. Connect a **system-level** VPN (not browser-only) and retry.

### `PhantomJS not found`
JS bot-challenge page. Navigate to a video in-browser (solves challenge + sets cookie), re-export cookies, retry.

### `HTTP 412: Precondition Failed` on m3u8
Stream is access-controlled. Metadata may be saved but thumbnail may be missing. Logged as `[!] Failed: <id>`, safe to skip.

### Cookie decryption warnings from `--cookies-from-browser`
Prefer explicit `cookies.txt` exports over live browser profile extraction.

### Pagination returns inflated ID counts
Platforms mix recommended videos into playlist pages. The associative-array deduplication in `scrape.sh` handles this.

## Architecture Decisions

- **PowerShell Core as primary scripting layer** — `pwsh` 7+ runs cross-platform (Linux, macOS, Windows). All `.sh` scripts have `.ps1` equivalents; the bash scripts are kept for reference but `.ps1` is the maintained version. Parallel execution uses `ForEach-Object -Parallel` with `-ThrottleLimit`; cross-thread variable capture uses `$using:` scope.
- **On-demand video downloads via local server** — `serve.py` acts as a minimal API gateway so the static HTML can trigger authenticated yt-dlp downloads without any external service. Videos default to not being downloaded; storage is only used when explicitly requested.
- **`local_video` baked into catalog JSON** — `build_catalog.py` checks `videos/` at build time; if a file exists the path is embedded so the Play button works when opening the HTML directly from the filesystem (no server needed for already-downloaded files).
- **Netscape cookies over browser profile** — more reliable than live browser extraction.
- **`?page=N` pagination** — simpler than yt-dlp's built-in playlist handling, which only fetched the first page for certain playlist types.
- **Thumbnails in separate folder** — relative paths (`../thumbnails/id.jpg`) let the catalog open directly from the filesystem.
- **`@{}` hashtable dedup** — PS uses `@{}` hashtable (O(1) lookup); bash uses `declare -A SEEN_IDS` for the same reason.
- **`$COOKIES_FILE` env var** — all scripts honour it, enabling `config.sh`-based multi-source setups.
- **`-Limit N`** — stops after N new fetches, useful for tag/search pages that could return thousands of results.
- **Subscription scraper uses `/videos` endpoint** — naturally excludes photo posts without needing content-type checks.
- **Tag bar filtered to 2+ occurrences** — single-use tags are excluded from the bar to reduce clutter; they still appear on individual cards.
- **YouTube scraper skips cookies** — public YouTube content doesn't need auth; both `scrape_youtube.ps1` and `.sh` omit `--cookies` intentionally.
- **YouTube pagination is native** — yt-dlp handles YouTube's internal pagination in one call; no `?page=N` looping. `-Playlist-end N` and `--dateafter`/`--datebefore` are passed directly to yt-dlp.
- **Saved views use two localStorage keys** — `vcat_views` for named saves, `vcat_last_state` for the auto-saved last state; kept separate so clearing named views doesn't lose the last-used state.

## Environment

- OS: Ubuntu/Zorin (Debian-based)
- Shell: bash + pwsh (PowerShell Core 7+)
- Python: 3.12+
- yt-dlp: 2026.3.17+
- VPN: ProtonVPN (system-level, required for geo-restricted content)
