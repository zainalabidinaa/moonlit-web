#!/bin/bash
# Find Trakt list IDs for TV franchise universes.
# You need a Trakt client_id from https://trakt.tv/oauth/applications
# Usage: TRAKT_CLIENT_ID=your_id ./find_trakt_lists.sh

: ${TRAKT_CLIENT_ID:?Set TRAKT_CLIENT_ID env var}

search() {
  local query="$1"
  curl -s -H "trakt-api-version: 2" -H "trakt-api-key: $TRAKT_CLIENT_ID" \
    "https://api.trakt.tv/search/list?query=$query&type=all&limit=5" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data:
    lid = item['list']['ids']['trakt']
    name = item['list']['name']
    user = item['list']['user']['username']
    desc = item['list']['description'][:60] if item['list']['description'] else ''
    count = item['list']['item_count']
    print(f'{lid:>8} | {name} | by {user} | {count} items | {desc}')" 2>/dev/null || echo "  (no results or API error)"
}

echo "=== ACTION ==="
search "Jack%20Ryan%20Clancy%20series"

echo ""
echo "=== COMEDY ==="
search "The%20Office%20Parks%20Rec%20universe"

echo ""
echo "=== CRIME ==="
search "Breaking%20Bad%20Better%20Call%20Saul%20universe"
search "Law%20and%20Order%20universe%20series"
search "Narcos%20universe"

echo ""
echo "=== DRAMA ==="
search "Game%20of%20Thrones%20House%20of%20Dragon%20universe"
search "Yellowstone%201883%201923%20universe"
search "Grey%27s%20Anatomy%20Station%2019%20universe"

echo ""
echo "=== HORROR ==="
search "American%20Horror%20Story%20universe"
search "Walking%20Dead%20universe%20series"

echo ""
echo "=== MYSTERY ==="
search "Sherlock%20series"
search "True%20Detective%20series"

echo ""
echo "=== SCI-FI ==="
search "Star%20Trek%20universe%20series"
search "Doctor%20Who%20universe"
search "The%20Expanse%20Battlestar%20Galactica"
search "Black%20Mirror%20series"

echo ""
echo "=== THRILLER ==="
search "Mindhunter%20series"
search "Homeland%20series"

echo ""
echo "=== WAR ==="
search "Band%20of%20Brothers%20The%20Pacific"

echo ""
echo "=== FANTASY ==="
search "The%20Witcher%20Rings%20of%20Power%20fantasy%20series"

echo ""
echo "=== ROMANCE ==="
search "Bridgerton%20series"
search "Outlander%20series"

echo ""
echo "=== ANIMATION ==="
search "The%20Simpsons%20Futurama%20series"
search "Rick%20and%20Morty%20series"
search "South%20Park%20series"
