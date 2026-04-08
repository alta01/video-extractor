#!/usr/bin/env bash
# clean.sh — remove metadata and thumbnails for IDs not returned by a playlist URL
# Usage: ./scripts/clean.sh <playlist-url>
#
# Fetches all current IDs from the playlist (all pages), then deletes local
# metadata/*.info.json and thumbnails/*.jpg for any ID not in that set.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
METADATA_DIR="$PROJECT_DIR/metadata"
THUMBNAILS_DIR="$PROJECT_DIR/thumbnails"
COOKIES_FILE="${COOKIES_FILE:-$PROJECT_DIR/cookies/cookies.txt}"

if [[ -z "${1:-}" ]]; then
  echo "[!] Usage: $0 <playlist-url>"
  exit 1
fi
URL="$1"

if [[ ! -f "$COOKIES_FILE" ]]; then
  echo "[!] No cookies file found at $COOKIES_FILE"
  exit 1
fi

echo "[*] Fetching live ID list from playlist..."
declare -A LIVE_IDS
PAGE=1
while true; do
  PAGE_URL="${URL}?page=${PAGE}"
  IDS=$(yt-dlp --cookies "$COOKIES_FILE" --flat-playlist --print "%(id)s" "$PAGE_URL" 2>/dev/null)
  [[ -z "$IDS" ]] && break
  while IFS= read -r id; do LIVE_IDS["$id"]=1; done <<< "$IDS"
  ((PAGE++))
done

echo "[*] ${#LIVE_IDS[@]} live IDs found"

removed=0
for f in "$METADATA_DIR"/*.info.json; do
  id="$(basename "$f" .info.json)"
  [[ "$id" == *favorites* ]] && continue
  if [[ -z "${LIVE_IDS[$id]+_}" ]]; then
    echo "    Removing: $id"
    rm -f "$f" "${THUMBNAILS_DIR}/${id}.jpg"
    ((removed++))
  fi
done

echo "[✓] Removed $removed orphaned entries"
