#!/usr/bin/env bash
# scrape_youtube.sh — scrape a YouTube channel or search results
# Usage: ./scripts/scrape_youtube.sh [--parallel N] [--force] [channel-url-or-search-term]
#
# Prompts interactively for scope (all / last N / date range) or search limit.
# No cookies required for public channels.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS/.." && pwd)"
METADATA_DIR="$PROJECT_DIR/metadata"
THUMBNAILS_DIR="$PROJECT_DIR/thumbnails"

FORCE=0
PARALLEL="${PARALLEL:-1}"

while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --force)    FORCE=1; shift ;;
    --parallel) PARALLEL="${2:?--parallel requires a number}"; shift 2 ;;
    *) echo "[!] Unknown flag: $1"; exit 1 ;;
  esac
done

INPUT="${1:-}"

# ── Prompt for source if not provided ──────────────────────────────────────
if [[ -z "$INPUT" ]]; then
  echo ""
  echo "What do you want to scrape?"
  echo "  1) YouTube channel"
  echo "  2) YouTube search / tag"
  read -r -p "Choice [1/2]: " src_choice

  if [[ "${src_choice:-1}" == "2" ]]; then
    read -r -p "Search term or tag: " INPUT
    INPUT="search:${INPUT}"
  else
    read -r -p "Channel URL (e.g. https://www.youtube.com/@mkbhd): " INPUT
  fi
fi

# ── Build yt-dlp URL + extra flags based on source type ───────────────────
EXTRA_FLAGS=()
SCOPE_DESC=""

if [[ "$INPUT" == search:* ]]; then
  TERM="${INPUT#search:}"
  read -r -p "Max results [50]: " count
  count="${count:-50}"
  YT_URL="ytsearch${count}:${TERM}"
  SCOPE_DESC="Search: \"${TERM}\" (up to ${count} results)"

else
  # Normalise channel URL — strip trailing slash, ensure /videos suffix
  CHANNEL_URL="${INPUT%/}"
  [[ "$CHANNEL_URL" == */videos ]] || CHANNEL_URL="${CHANNEL_URL}/videos"

  echo ""
  echo "Scrape scope:"
  echo "  1) All videos"
  echo "  2) Last N videos"
  echo "  3) Date range"
  read -r -p "Choice [1/2/3]: " scope

  case "${scope:-1}" in
    2)
      read -r -p "How many videos? [100]: " n
      n="${n:-100}"
      EXTRA_FLAGS+=("--playlist-end" "$n")
      SCOPE_DESC="Last ${n} videos"
      ;;
    3)
      read -r -p "From date (YYYYMMDD): " from_date
      read -r -p "To date   (YYYYMMDD, blank = today): " to_date
      [[ -z "$from_date" ]] && { echo "[!] From date required."; exit 1; }
      EXTRA_FLAGS+=("--dateafter" "$from_date")
      [[ -n "${to_date:-}" ]] && EXTRA_FLAGS+=("--datebefore" "$to_date")
      SCOPE_DESC="Date range: ${from_date} → ${to_date:-today}"
      ;;
    *)
      SCOPE_DESC="All videos"
      ;;
  esac

  YT_URL="$CHANNEL_URL"
fi

echo ""
echo "[*] ${SCOPE_DESC}"
echo "[*] Fetching video list from YouTube..."

# yt-dlp handles YouTube pagination natively — fetch all IDs+URLs in one call
ENTRIES=$(yt-dlp \
  --flat-playlist \
  --print "%(id)s %(url)s" \
  "${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}" \
  "$YT_URL" 2>/dev/null) || true

if [[ -z "$ENTRIES" ]]; then
  echo "[!] No videos found. Check the URL or search term and try again."
  exit 1
fi

total=$(echo "$ENTRIES" | wc -l)
echo "[*] ${total} video(s) found — fetching metadata and thumbnails..."

# ── Per-video fetch (no cookies needed for public YT content) ──────────────
fetch_entry() {
  local id="$1" VIDEO_URL="$2"
  if [[ "$FORCE" -eq 0 && -f "${METADATA_DIR}/${id}.info.json" ]]; then
    echo "    Skipping (exists): $id"
    return 0
  fi
  echo "    Fetching: $id"
  yt-dlp \
    --write-info-json \
    --write-thumbnail \
    --skip-download \
    --convert-thumbnails jpg \
    --retries 3 \
    --sleep-interval 1 \
    --max-sleep-interval 3 \
    -o "${METADATA_DIR}/%(id)s" \
    "$VIDEO_URL" 2>/dev/null || echo "    [!] Failed: $id"
  [[ -f "${METADATA_DIR}/${id}.jpg" ]] && mv "${METADATA_DIR}/${id}.jpg" "${THUMBNAILS_DIR}/${id}.jpg"
  echo "__FETCHED__"
}
export -f fetch_entry
export FORCE METADATA_DIR THUMBNAILS_DIR

new_fetches=0
if [[ "$PARALLEL" -gt 1 ]]; then
  new_fetches=$(echo "$ENTRIES" \
    | xargs -P "$PARALLEL" -I {} bash -c \
        'id="${1%% *}"; url="${1#* }"; fetch_entry "$id" "$url"' _ {} \
    | grep -c "__FETCHED__") || true
else
  while IFS= read -r entry; do
    out=$(fetch_entry "${entry%% *}" "${entry#* }")
    echo "$out" | grep -v "__FETCHED__" || true
    [[ "$out" == *"__FETCHED__"* ]] && ((new_fetches++)) || true
  done <<< "$ENTRIES"
fi

json_files=("$METADATA_DIR"/*.info.json); [[ -e "${json_files[0]}" ]] || json_files=()
jpg_files=("$THUMBNAILS_DIR"/*.jpg);      [[ -e "${jpg_files[0]}" ]]  || jpg_files=()
echo ""
echo "[✓] Done. Fetched: ${new_fetches} new  |  Metadata: ${#json_files[@]}  |  Thumbnails: ${#jpg_files[@]}"
echo ""
echo "[*] Run scripts/build_catalog.py to regenerate catalog.html"
