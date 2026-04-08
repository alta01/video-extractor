# video-extractor

A local video catalog tool that fetches metadata and thumbnails from online video platforms using [yt-dlp](https://github.com/yt-dlp/yt-dlp), then generates a searchable HTML catalog you can browse offline.

## Features

- Crawls paginated playlist/favorites pages and deduplicates entries across pages
- Downloads video metadata (title, duration, views, likes, tags) and thumbnails — no video files downloaded
- Converts browser cookie exports (JSON) to Netscape format for yt-dlp
- Generates a dark-themed, searchable HTML catalog with thumbnail grid
  - Sort by title, duration, views, or likes
  - Filter by tags (click pills or card tags)
  - Star/favorite videos — persisted in localStorage, filterable
  - Infinite scroll — renders cards in batches of 50
  - Export current view to JSON or CSV
- Warns on expiring cookies before each scrape run
- Supports geo-restriction bypass via system VPN or proxy

## Project Structure

```
video-extractor/
├── metadata/       # yt-dlp .info.json files (one per video)
├── thumbnails/     # .jpg thumbnail images
├── catalog/        # Generated catalog.html (gitignored)
├── cookies/        # Browser cookie exports
│   ├── cookies.json   # Raw export from browser extension
│   └── cookies.txt    # Converted Netscape format (used by yt-dlp)
├── config.sh       # Per-source settings (COOKIES_FILE, PARALLEL, etc.)
└── scripts/
    ├── scrape.sh               # Main crawler — paginates, deduplicates, fetches
    ├── scrape_subscriptions.sh # Scrape videos for all subscriptions of a PH user
    ├── build_catalog.py        # Rebuilds catalog.html from metadata/
    ├── convert_cookies.py      # Converts Cookie-Editor JSON → Netscape cookies.txt
    ├── update.sh               # One-shot: scrape + rebuild catalog
    ├── check_thumbnails.sh     # Re-fetch any missing thumbnails
    └── clean.sh                # Remove metadata/thumbnails for deleted playlist entries
```

## Requirements

- `yt-dlp` (2025+ recommended)
- `python3`
- A browser cookie export for authenticated/geo-unlocked access
- A system-level VPN if your region restricts access to the target platform

## Setup

### 1. Install yt-dlp

```bash
pip3 install -U yt-dlp
```

### 2. Export browser cookies

Install the [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) extension (or Cookie-Editor for JSON export) in your browser.

Navigate to the target platform while logged in, then export:

- **Netscape format** → save directly as `cookies/cookies.txt`
- **JSON format** → save as `cookies/cookies.json`, then convert:

```bash
python3 scripts/convert_cookies.py cookies/cookies.json cookies/cookies.txt
```

### 3. Store your URLs

Copy `sources.conf.example` to `sources.conf` and fill in your playlist/subscription URLs. This file is gitignored and never committed:

```bash
cp sources.conf.example sources.conf
# edit sources.conf and set FAVORITES_URL and SUBSCRIPTIONS_URL
```

### 4. Run the crawler

```bash
source sources.conf && bash scripts/scrape.sh "$FAVORITES_URL"
```

Or pass any URL directly:

```bash
bash scripts/scrape.sh "https://example-platform.com/users/someuser/favorites"
```

Flags:
- `--force` — re-fetch entries that already have local metadata
- `--parallel N` — fetch N videos concurrently (default: 1)
- `--limit N` — stop after fetching N new entries (useful for tag/search URLs)

The script warns on expiring cookies, paginates automatically, and stops when a page returns only duplicate IDs.

Works with any URL yt-dlp can paginate — favorites, tag pages, channel/creator pages, search results, etc.

### 5. Build the catalog

```bash
python3 scripts/build_catalog.py
```

Or use the combined one-shot wrapper:

```bash
bash scripts/update.sh "https://example-platform.com/users/someuser/favorites"
```

Open `catalog/catalog.html` in any browser. Thumbnails load from relative paths so the folder is self-contained.

## Scraping Subscriptions

Scrape videos for every channel a user subscribes to. Photo/image posts are excluded automatically — the `/videos` endpoint is used for each channel.

Store your subscriptions page URL in `sources.conf` (gitignored):

```bash
# sources.conf
SUBSCRIPTIONS_URL="https://example-platform.com/users/myusername/subscriptions"
```

Then run:

```bash
source sources.conf && bash scripts/scrape_subscriptions.sh "$SUBSCRIPTIONS_URL" --limit 10 --parallel 2
```

Flags are forwarded to `scrape.sh` (`--limit`, `--parallel`, `--force`). The script lists all found channels and asks for confirmation before scraping unless `--yes` is passed.

```bash
# Non-interactive, 5 new videos per channel
source sources.conf && bash scripts/scrape_subscriptions.sh "$SUBSCRIPTIONS_URL" --limit 5 --yes
```

## Maintenance Scripts

**Re-fetch missing thumbnails** (after partial runs or failures):
```bash
bash scripts/check_thumbnails.sh
```

**Remove entries deleted from the playlist** (clean up orphaned local files):
```bash
bash scripts/clean.sh "https://example-platform.com/users/someuser/favorites"
```

## Multi-Source / Config

Copy `config.sh` and uncomment the variables you need. Source it before running:

```bash
source config.sh && bash scripts/scrape.sh "$URL"
```

`COOKIES_FILE` and `PARALLEL` environment variables are honoured by all scripts.

## Dealing with Geo-Restrictions

Some platforms restrict content by region. Symptoms:

- yt-dlp gets HTTP 302 redirect to the site homepage instead of the video page
- Error: `Unable to extract title`

**Solution:** Connect a system-level VPN before running the scraper. Browser-only VPNs (like Opera's built-in VPN) do not route yt-dlp traffic — you need a system-wide VPN such as [ProtonVPN](https://protonvpn.com/).

```bash
# Install ProtonVPN on Debian/Ubuntu
sudo apt install -y proton-vpn-gnome-desktop
# Launch via app menu or:
protonvpn-app
```

## Dealing with JavaScript Bot Challenges

Some platforms serve an obfuscated JavaScript challenge page to detect bots before showing content. Symptoms:

- Error: `PhantomJS not found`
- The raw page HTML contains a `leastFactor` or similar JS puzzle rather than video content

**Solution:** The platform's JS challenge sets a session cookie in your browser once solved. Re-export cookies **after** navigating to a video page (so the challenge is solved), convert, and re-run. The solved-challenge cookie allows yt-dlp to pass through without needing to execute JavaScript.

## Pagination Notes

Many platforms only show ~24 items per page. The scraper handles this by appending `?page=N` to the playlist URL and stopping when a page returns only previously seen IDs. If a platform uses a different pagination scheme, update the `PAGE_URL` construction in `scrape.sh`.

## Cookie Expiry

Cookies expire. `scrape.sh` warns if any cookies expire within 7 days before starting a run. If you see authentication errors or JS challenge errors after a working run, re-export cookies from your browser and reconvert. ProtonVPN should remain connected for the duration of the crawl.
