#!/usr/bin/env bash
# update.sh — scrape a playlist then rebuild the catalog
# Usage: ./scripts/update.sh <playlist-url> [scrape.sh flags]

set -euo pipefail
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPTS/scrape.sh" "$@"
python3 "$SCRIPTS/build_catalog.py"
