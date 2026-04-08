#!/usr/bin/env bash
# scrape_subscriptions.sh — scrape videos for each channel in a subscriptions page
# Usage: ./scripts/scrape_subscriptions.sh <subscriptions-url> [--limit N] [--parallel N] [--yes]
#
# Reads the subscriptions page (using your cookies for auth), extracts each
# subscribed channel's profile URL, then runs scrape.sh on each channel's
# /videos endpoint. Photo/image posts are excluded because the /videos path
# is used for every channel.
#
# Tip: store your subscriptions URL in sources.conf and run:
#   source sources.conf && bash scripts/scrape_subscriptions.sh "$SUBSCRIPTIONS_URL"

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS/.." && pwd)"
COOKIES_FILE="${COOKIES_FILE:-$PROJECT_DIR/cookies/cookies.txt}"

if [[ -z "${1:-}" ]]; then
  echo "[!] Usage: $0 <subscriptions-url> [--limit N] [--parallel N] [--yes]"
  echo "    Tip: source sources.conf && $0 \"\$SUBSCRIPTIONS_URL\""
  exit 1
fi
SUBS_URL="$1"; shift

SCRAPE_ARGS=()
AUTO_YES=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --yes)                      AUTO_YES=1; shift ;;
    --limit|--parallel|--force) SCRAPE_ARGS+=("$1" "$2"); shift 2 ;;
    *) echo "[!] Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ ! -f "$COOKIES_FILE" ]]; then
  echo "[!] No cookies file found at $COOKIES_FILE"
  exit 1
fi

echo "[*] Fetching subscriptions from: $SUBS_URL"

# Fetch the subscriptions page with cookie auth and extract channel profile URLs.
# The base domain is derived from the provided URL so this works across platforms.
CHANNELS=$(python3 - "$SUBS_URL" "$COOKIES_FILE" <<'PYEOF'
import sys, re, urllib.request, http.cookiejar
from urllib.parse import urlparse

url, cookie_file = sys.argv[1], sys.argv[2]
base = "{0.scheme}://{0.netloc}".format(urlparse(url))

cj = http.cookiejar.MozillaCookieJar(cookie_file)
try:
    cj.load(ignore_discard=True, ignore_expires=True)
except Exception:
    pass

opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.addheaders = [
    ('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'),
    ('Accept-Language', 'en-US,en;q=0.9'),
]

try:
    html = opener.open(url, timeout=15).read().decode('utf-8', errors='replace')
except Exception as e:
    print(f"# Error fetching page: {e}", file=sys.stderr)
    sys.exit(1)

# Extract profile links: /model/NAME, /pornstar/NAME, /users/NAME, /channels/NAME
# Matches both absolute and root-relative hrefs on the same domain.
skip_names = {'subscriptions', 'videos', 'playlists', 'photos', 'activity',
              'favorites', 'login', 'register', 'search', 'categories'}
found = set()
pattern = re.compile(
    r'href="((?:' + re.escape(base) + r')?/(model|pornstar|users|channels)/([^"/?#\s]+))'
)
for m in pattern.finditer(html):
    path, kind, name = m.group(1), m.group(2), m.group(3)
    if name.lower() in skip_names or name.startswith('?'):
        continue
    full = path if path.startswith('http') else base + path
    found.add((kind, name, full.rstrip('/')))

if not found:
    print("# No channel links found on page", file=sys.stderr)
    sys.exit(1)

for kind, name, full_url in sorted(found):
    print(f"{kind}\t{name}\t{full_url}")
PYEOF
) || true

if [[ -z "$CHANNELS" ]]; then
  echo "[!] No subscriptions found — ensure cookies are current and the URL is correct."
  exit 1
fi

echo ""
echo "[*] Found channels:"
echo "$CHANNELS" | while IFS=$'\t' read -r kind name _url; do
  printf "    [%-10s] %s\n" "$kind" "$name"
done
echo ""

if [[ "$AUTO_YES" -eq 0 ]]; then
  read -r -p "[?] Scrape all of the above? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

total=$(echo "$CHANNELS" | wc -l)
current=0
echo "$CHANNELS" | while IFS=$'\t' read -r kind name profile_url; do
  ((current++)) || true
  echo ""
  echo "[→] ($current/$total) $name"
  bash "$SCRIPTS/scrape.sh" "${SCRAPE_ARGS[@]+"${SCRAPE_ARGS[@]}"}" "${profile_url}/videos" \
    || echo "    [!] Failed for $name — skipping"
done

echo ""
echo "[✓] All channels processed. Run scripts/build_catalog.py to rebuild the catalog."
