#!/usr/bin/env bash
# check_thumbnails.sh — find metadata entries missing a local thumbnail and re-fetch them
# Usage: ./scripts/check_thumbnails.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
METADATA_DIR="$PROJECT_DIR/metadata"
THUMBNAILS_DIR="$PROJECT_DIR/thumbnails"
COOKIES_FILE="${COOKIES_FILE:-$PROJECT_DIR/cookies/cookies.txt}"

missing=()
for f in "$METADATA_DIR"/*.info.json; do
  id="$(basename "$f" .info.json)"
  [[ "$id" == *favorites* ]] && continue
  [[ -f "${THUMBNAILS_DIR}/${id}.jpg" ]] || missing+=("$id")
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "[✓] All thumbnails present"
  exit 0
fi

echo "[*] ${#missing[@]} missing thumbnail(s) — re-fetching..."

for id in "${missing[@]}"; do
  url="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('webpage_url',''))" "${METADATA_DIR}/${id}.info.json")"
  if [[ -z "$url" ]]; then
    echo "    [!] No URL for $id — skipping"
    continue
  fi
  echo "    Fetching thumbnail: $id"
  yt-dlp \
    --cookies "$COOKIES_FILE" \
    --write-thumbnail \
    --skip-download \
    --convert-thumbnails jpg \
    --retries 3 \
    -o "${METADATA_DIR}/%(id)s" \
    "$url" 2>/dev/null || echo "    [!] Failed: $id"
  [[ -f "${METADATA_DIR}/${id}.jpg" ]] && mv "${METADATA_DIR}/${id}.jpg" "${THUMBNAILS_DIR}/${id}.jpg"
done

echo "[✓] Done"
