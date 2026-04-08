# config.sh — per-source settings for scrape.sh
# Source this file or pass it to scrape.sh via: source config.sh && ./scripts/scrape.sh "$URL"
#
# Copy this file and customise per platform. scrape.sh reads these variables if set.

# Default cookies file (overrides the built-in default)
# COOKIES_FILE="$HOME/video-extractor/cookies/mysite-cookies.txt"

# Parallel workers (default: 1)
# PARALLEL=4

# Pagination style: "query" (?page=N) or "path" (/page/N) — scrape.sh uses "query" by default
# PAGE_STYLE="query"

# Example profiles — uncomment and adjust as needed:
#
# --- Site A ---
# URL="https://example.com/users/someone/favorites"
# COOKIES_FILE="$HOME/video-extractor/cookies/sitea.txt"
# PARALLEL=2
#
# --- Site B ---
# URL="https://other-site.com/playlist/12345"
# COOKIES_FILE="$HOME/video-extractor/cookies/siteb.txt"
# PARALLEL=1
