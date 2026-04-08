# AGENTS.md

This file orients AI agents (Claude Code, Copilot, etc.) for this project. For full user-facing documentation see [README.md](README.md).

## What This Project Does

`video-extractor` crawls paginated video playlist pages using `yt-dlp`, saves metadata and thumbnails locally, and generates a searchable HTML catalog. It does **not** download video files.

## Key Files

| File | Purpose |
|------|---------|
| `scripts/scrape.sh` | Main crawler. Paginates any yt-dlp-supported URL, deduplicates, fetches metadata + thumbnails. Flags: `--force`, `--parallel N`, `--limit N`. Reads `$COOKIES_FILE` env var. |
| `scripts/build_catalog.py` | Reads all `metadata/*.info.json` and writes `catalog/catalog.html`. Surfaces title, duration, views, likes, tags. |
| `scripts/convert_cookies.py` | Converts Cookie-Editor JSON exports to Netscape format. Input: `cookies/cookies.json`. Output: `cookies/cookies.txt`. |
| `scripts/scrape_subscriptions.sh` | Fetches a subscriptions page via cookie-authenticated HTTP, extracts channel profile URLs (domain-agnostic), runs `scrape.sh` on each channel's `/videos` endpoint. Photo posts excluded by URL. Flags: `--limit N`, `--parallel N`, `--force`, `--yes` (skip confirm). |
| `scripts/update.sh` | One-shot wrapper: runs `scrape.sh "$@"` then `build_catalog.py`. |
| `scripts/check_thumbnails.sh` | Finds metadata entries missing a local thumbnail and re-fetches them. |
| `scripts/clean.sh` | Fetches live IDs from the playlist and removes local metadata/thumbnails for any ID no longer present. |
| `config.sh` | Commented-out per-source variables (`COOKIES_FILE`, `PARALLEL`, `URL`). Source before running scripts. |
| `sources.conf` | **Gitignored.** Personal playlist/subscription URLs (`FAVORITES_URL`, `SUBSCRIPTIONS_URL`). Copy from `sources.conf.example`. |
| `sources.conf.example` | Committed template showing the `sources.conf` structure. |
| `cookies/cookies.txt` | Netscape-format cookies passed to yt-dlp via `--cookies`. Expires with the browser session. |
| `metadata/` | One `.info.json` per video. Source of truth for catalog generation. |
| `thumbnails/` | One `.jpg` per video. Referenced by relative path from `catalog/catalog.html`. |

## Workflow

```
export cookies → convert_cookies.py → scrape.sh → build_catalog.py → catalog.html
```

Or one-shot:
```
source config.sh && bash scripts/update.sh "$URL"
```

## Common Tasks

**Rebuild catalog:**
```bash
python3 scripts/build_catalog.py
```

**Crawl a playlist/tag/channel URL (skip existing):**
```bash
source sources.conf && bash scripts/scrape.sh "$FAVORITES_URL"
bash scripts/scrape.sh --limit 20 "https://example-platform.com/channel/NAME/videos"
```

**Force re-fetch all, 4 parallel workers:**
```bash
bash scripts/scrape.sh --force --parallel 4 "https://example-platform.com/user/playlist"
```

**Scrape all subscriptions (5 new per channel, confirm first):**
```bash
source sources.conf && bash scripts/scrape_subscriptions.sh "$SUBSCRIPTIONS_URL" --limit 5 --parallel 2
```

**Non-interactive subscription scrape:**
```bash
source sources.conf && bash scripts/scrape_subscriptions.sh "$SUBSCRIPTIONS_URL" --limit 10 --yes
```

**Fix missing thumbnails after a partial run:**
```bash
bash scripts/check_thumbnails.sh
```

**Remove entries deleted from the playlist:**
```bash
bash scripts/clean.sh "https://platform.com/user/playlist-url"
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
- Infinite scroll (batches of 50 cards via `IntersectionObserver`)
- Export current filtered view to JSON or CSV

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

- **No video downloads** — metadata and thumbnails only. Keeps storage minimal.
- **Netscape cookies over browser profile** — more reliable than live browser extraction.
- **`?page=N` pagination** — simpler than yt-dlp's built-in playlist handling, which only fetched the first page for certain playlist types.
- **Thumbnails in separate folder** — relative paths (`../thumbnails/id.jpg`) let the catalog open directly from the filesystem.
- **Associative array dedup** — `declare -A SEEN_IDS` gives O(1) lookup vs the previous O(n²) string scan.
- **`$COOKIES_FILE` env var** — all scripts honour it, enabling `config.sh`-based multi-source setups.
- **`--limit N`** — stops after N new fetches, useful for tag/search pages that could return thousands of results.
- **Subscription scraper uses `/videos` endpoint** — naturally excludes photo posts without needing content-type checks.
- **Tag bar filtered to 2+ occurrences** — single-use tags are excluded from the bar to reduce clutter; they still appear on individual cards.

## Environment

- OS: Ubuntu/Zorin (Debian-based)
- Shell: bash
- Python: 3.12+
- yt-dlp: 2026.3.17+
- VPN: ProtonVPN (system-level, required for geo-restricted content)
