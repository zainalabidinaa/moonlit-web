#!/usr/bin/env python3
"""Back up the four collection tables from Supabase to local JSON before a reimport.
Reads credentials from import_nuvio_collections.py so no secret is passed on the CLI."""
import json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from import_nuvio_collections import SUPABASE_URL, SERVICE_KEY  # noqa: E402

H = {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"}

def get(tbl):
    rows, off = [], 0
    while True:
        url = f"{SUPABASE_URL}/rest/v1/{tbl}?select=*&limit=1000&offset={off}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=H)) as r:
            chunk = json.load(r)
        rows += chunk
        if len(chunk) < 1000:
            break
        off += 1000
    return rows

def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for t in ["collections", "folders", "folder_catalogs", "folder_sources"]:
        rows = get(t)
        json.dump(rows, open(os.path.join(out_dir, f"supabase-{t}.json"), "w"), ensure_ascii=False)
        cols = sorted(rows[0].keys()) if rows else []
        print(f"{t}: {len(rows)} rows | columns: {cols}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/supabase-backup")
