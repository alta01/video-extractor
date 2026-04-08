#!/usr/bin/env bash
# scrape.sh — fetch metadata + thumbnails from a paginated video playlist
# Usage: ./scrape.sh [--force] [--parallel N] [--limit N] <playlist-or-tag-url>
#
# Requires: yt-dlp
# Output:   metadata/ and thumbnails/ under project root

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
METADATA_DIR="$PROJECT_DIR/metadata"
THUMBNAILS_DIR="$PROJECT_DIR/thumbnails"
COOKIES_FILE="${COOKIES_FILE:-$PROJECT_DIR/cookies/cookies.txt}"

FORCE=0
PARALLEL="${PARALLEL:-1}"
LIMIT=0   # 0 = unlimited

while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --force)    FORCE=1; shift ;;
    --parallel) PARALLEL="${2:?--parallel requires a number}"; shift 2 ;;
    --limit)    LIMIT="${2:?--limit requires a number}"; shift 2 ;;
    *) echo "[!] Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -z "${1:-}" ]]; then
  echo "[!] Usage: $0 [--force] [--parallel N] [--limit N] <playlist-url>"
  exit 1
fi
URL="$1"

if [[ ! -f "$COOKIES_FILE" ]]; then
  echo "[!] No cookies file found at $COOKIES_FILE"
  exit 1
fi

now=$(date +%s)
stale=$(awk -v now="$now" '
  /^#/ { next }
  { expiry=$5; if (expiry > 0 && expiry < now + 604800) count++ }
  END { print count+0 }
' "$COOKIES_FILE")
[[ "$stale" -gt 0 ]] && echo "[!] Warning: $stale cookie(s) expired or expiring within 7 days — consider re-exporting"

fetch_entry() {
  local id="$1" VIDEO_URL="$2"
  if [[ "$FORCE" -eq 0 && -f "${METADATA_DIR}/${id}.info.json" ]]; then
    echo "    Skipping (exists): $id"
    return 0
  fi
  echo "    Fetching: $id"
  yt-dlp \
    --cookies "$COOKIES_FILE" \
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
  # Signal that a new entry was fetched (not skipped) for limit tracking
  echo "__FETCHED__"
}
export -f fetch_entry
export FORCE COOKIES_FILE METADATA_DIR THUMBNAILS_DIR

declare -A SEEN_IDS
PAGE=1
FETCHED=0

while true; do
  [[ "$LIMIT" -gt 0 && "$FETCHED" -ge "$LIMIT" ]] && { echo "[*] Limit of $LIMIT reached — stopping"; break; }

  PAGE_URL="${URL}?page=${PAGE}"
  echo "[*] Scraping page $PAGE: $PAGE_URL"

  ENTRIES=$(yt-dlp \
    --cookies "$COOKIES_FILE" \
    --flat-playlist \
    --print "%(id)s %(url)s" \
    "$PAGE_URL" 2>/dev/null) || true

  if [[ -z "$ENTRIES" ]]; then
    echo "[*] No results on page $PAGE — done paginating"
    break
  fi

  NEW_ENTRIES=()
  while IFS= read -r line; do
    id="${line%% *}"
    if [[ -z "${SEEN_IDS[$id]+_}" ]]; then
      NEW_ENTRIES+=("$line")
      SEEN_IDS[$id]=1
    fi
  done <<< "$ENTRIES"

  if [[ ${#NEW_ENTRIES[@]} -eq 0 ]]; then
    echo "[*] Page $PAGE returned only duplicates — done paginating"
    break
  fi

  # Trim to limit if needed
  if [[ "$LIMIT" -gt 0 ]]; then
    remaining=$(( LIMIT - FETCHED ))
    if [[ ${#NEW_ENTRIES[@]} -gt "$remaining" ]]; then
      NEW_ENTRIES=("${NEW_ENTRIES[@]:0:$remaining}")
    fi
  fi

  echo "[*] Page $PAGE: ${#NEW_ENTRIES[@]} entries to process"

  if [[ "$PARALLEL" -gt 1 ]]; then
    new_fetches=$(printf '%s\n' "${NEW_ENTRIES[@]}" \
      | xargs -P "$PARALLEL" -I {} bash -c \
          'id="${1%% *}"; url="${1#* }"; fetch_entry "$id" "$url"' _ {} \
      | grep -c "__FETCHED__") || true
  else
    new_fetches=0
    for entry in "${NEW_ENTRIES[@]}"; do
      out=$(fetch_entry "${entry%% *}" "${entry#* }")
      echo "$out" | grep -v "__FETCHED__" || true
      [[ "$out" == *"__FETCHED__"* ]] && ((new_fetches++)) || true
    done
  fi

  FETCHED=$(( FETCHED + new_fetches ))
  ((PAGE++))
done

json_files=("$METADATA_DIR"/*.info.json); [[ -e "${json_files[0]}" ]] || json_files=()
jpg_files=("$THUMBNAILS_DIR"/*.jpg);      [[ -e "${jpg_files[0]}" ]]  || jpg_files=()
echo ""
echo "[✓] Done. Fetched: $FETCHED new  |  Metadata: ${#json_files[@]} files  |  Thumbnails: ${#jpg_files[@]} files"
echo ""
echo "[*] Run scripts/build_catalog.py to regenerate catalog.html"
