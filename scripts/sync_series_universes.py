#!/usr/bin/env python3
"""Insert Series Universes collection data into Supabase.
Reads the JSON file and upserts all franchise entries."""
import json, uuid, sys, os
import urllib.request, urllib.error

SUPABASE_URL = "https://hvfsntdyowapjxobtyli.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzg0OTUsImV4cCI6MjA5NTc1NDQ5NX0.YraHrXjD-l_CmzEbs7jRW34i83HIlKcOh76xbfOn6sQ"

COLLECTION_ID = "collection-series-universes"

def supabase_request(method, table, body=None):
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

# Load JSON data
json_path = os.path.join(os.path.dirname(__file__), "..", "Apps", "MoonlitMac", "Resources", "home-organizer.json")
with open(json_path) as f:
    data = json.load(f)

# Find Series Universes
su = next((c for c in data if c.get("title") == "Series Universes"), None)
if not su:
    print("ERROR: Series Universes not found in JSON")
    sys.exit(1)

# 1. Delete existing Series Universes data (clean slate)
print("Cleaning up existing entries...")
for table in ["folder_sources", "folder_catalogs", "folders", "collections"]:
    code, _ = supabase_request("DELETE", f"{table}?id=eq.{COLLECTION_ID}")
    if table == "collections":
        supabase_request("DELETE", f"{table}?id=eq.{COLLECTION_ID}")

# Get current max sort_order
code, body = supabase_request("GET", "collections?select=sort_order&order=sort_order.desc&limit=1")
max_sort = 0
if code == 200:
    rows = json.loads(body)
    max_sort = rows[0]["sort_order"] if rows else 0

# 2. Insert collection
print("Inserting Series Universes collection...")
collection = {
    "id": COLLECTION_ID,
    "name": "Series Universes",
    "sort_order": max_sort + 1,
    "view_mode": "FOLLOW_LAYOUT",
    "show_all_tab": True,
    "pin_to_top": True,
}
code, _ = supabase_request("POST", "collections", collection)
if code not in (200, 201, 204):
    print(f"  FAILED: {code}")
else:
    print("  OK")

# 3. Insert folders and sources
source_order = 0
for folder in su["folders"]:
    folder_id = folder["id"]
    folder_name = folder["title"]
    print(f"Inserting: {folder_name}...")

    f = {
        "id": folder_id,
        "collection_id": COLLECTION_ID,
        "name": folder_name,
        "sort_order": folder.get("sortOrder", 0),
        "hide_title": folder.get("hideTitle", True),
        "tile_shape": folder.get("tileShape", "POSTER"),
    }
    code, _ = supabase_request("POST", "folders", f)
    if code not in (200, 201, 204):
        print(f"  Folder FAILED: {code}")
        continue

    for src in folder.get("sources", []):
        src_id = src.get("id", f"src-{folder_id}-{source_order}")
        source = {
            "id": src_id,
            "folder_id": folder_id,
            "title": src.get("title"),
            "provider": src.get("provider"),
            "tmdb_id": str(src.get("traktListId", 0)) if src.get("traktListId") else src.get("tmdbId"),
            "media_type": src.get("type", "series"),
            "tmdb_source_type": src.get("tmdbSourceType"),
            "sort_by": src.get("sortBy"),
            "sort_order": source_order,
        }
        code, _ = supabase_request("POST", "folder_sources", source)
        source_order += 1
        if code not in (200, 201, 204):
            print(f"  Source FAILED ({src.get('title')}): {code}")

print(f"\nDone. Inserted collection + {len(su['folders'])} folders with {source_order} sources.")
