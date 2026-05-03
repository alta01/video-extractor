#!/usr/bin/env bash
# serve.sh — start the catalog server
# Usage: ./scripts/serve.sh [port]   (default: 8765)
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/serve.py "${1:-8765}"
