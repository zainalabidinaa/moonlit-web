#!/usr/bin/env python3
"""
Rehost home-organizer.json artwork onto your own Supabase Storage bucket.

WHY: the shipped home layout pulls hero/cover/logo art from third-party hosts
(nuvio-assets on github.io + raw.githubusercontent, i.postimg.cc, files.catbox.moe,
giphy, etc.). That host trail ties the app to Nuvio and to throwaway image hosts —
a bad optic for App Store review and a breadcrumb for rights-holder complaints.
This script downloads each non-TMDB asset and re-uploads it to a bucket you own,
then rewrites the JSON to point at your CDN. TMDB art (image.tmdb.org) is left
alone: it is license-covered under the TMDB API terms.

NOTE ON COPYRIGHT: rehosting changes *where* the art is served from, not its
license status. These are franchise/promotional images. Rehosting removes the
Nuvio/piracy-host association (the review + complaint risk this addresses); it does
not grant you a license the way TMDB does. Prefer TMDB-sourced art where possible.

USAGE
  # 1. Preview what would change (no network writes):
  python3 scripts/rehost_home_assets.py --dry-run

  # 2. Do it (needs a Supabase Storage bucket + SERVICE ROLE key):
  export SUPABASE_URL="https://<project>.supabase.co"
  export SUPABASE_SERVICE_KEY="<service_role_key>"   # NOT the anon key
  export HOME_ASSETS_BUCKET="home-assets"            # create this public bucket first
  python3 scripts/rehost_home_assets.py

Re-runnable: a local map (scripts/.rehost_map.json) records source->new URL, so a
second run skips already-uploaded assets and only rewrites any remaining old URLs.
"""

from __future__ import annotations
import argparse
import hashlib
import json
import os
import sys
import urllib.request
import urllib.error
from urllib.parse import urlparse
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Every copy of the layout that ships in a client, kept in sync.
TARGET_FILES = [
    REPO / "Apps/MoonlitApp/Resources/home-organizer.json",
    REPO / "Apps/MoonlitMac/Resources/home-organizer.json",
    REPO / "moonlit-web/public/home-organizer.json",
    REPO / "Apps/MoonlitWindows/public/home-organizer.json",
]

# JSON keys whose string values are media URLs.
URL_KEYS = {
    "heroBackdropUrl",
    "backdropImageUrl",
    "titleLogoUrl",
    "coverImageUrl",
    "focusGifUrl",
    "heroVideoUrl",
}

# Hosts left untouched: TMDB (license-covered) + anything already on your CDN.
# Add your own bucket/CDN host(s) here so re-runs stay idempotent.
KEEP_HOSTS = {
    "image.tmdb.org",
}

MAP_PATH = Path(__file__).resolve().parent / ".rehost_map.json"


def host_of(url: str) -> str:
    return (urlparse(url).netloc or "").lower()


def load_map() -> dict:
    if MAP_PATH.exists():
        return json.loads(MAP_PATH.read_text())
    return {}


def save_map(m: dict) -> None:
    MAP_PATH.write_text(json.dumps(m, indent=2, sort_keys=True))


def collect_urls(files: list[Path]) -> set[str]:
    found: set[str] = set()

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in URL_KEYS and isinstance(v, str) and v.startswith("http"):
                    found.add(v)
                else:
                    walk(v)
        elif isinstance(node, list):
            for x in node:
                walk(x)

    for f in files:
        if f.exists():
            walk(json.loads(f.read_text()))
    return found


def needs_rehost(url: str, owned_hosts: set[str]) -> bool:
    h = host_of(url)
    return bool(h) and h not in owned_hosts


def object_path(url: str) -> str:
    from urllib.parse import urlparse
    ext = os.path.splitext(urlparse(url).path)[1].lower() or ".img"
    if len(ext) > 6:
        ext = ".img"
    digest = hashlib.sha1(url.encode()).hexdigest()
    return f"home-assets/{digest}{ext}"


def download(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Moonlit-rehost/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def upload(supabase_url: str, service_key: str, bucket: str, path: str, data: bytes, content_type: str) -> str:
    endpoint = f"{supabase_url}/storage/v1/object/{bucket}/{path}"
    req = urllib.request.Request(endpoint, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {service_key}")
    req.add_header("apikey", service_key)
    req.add_header("x-upsert", "true")
    req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=60) as r:
        r.read()
    return f"{supabase_url}/storage/v1/object/public/{bucket}/{path}"


def guess_content_type(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return {
        ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".webp": "image/webp", ".gif": "image/gif", ".svg": "image/svg+xml",
        ".mp4": "video/mp4", ".webm": "video/webm",
    }.get(ext, "application/octet-stream")


def rewrite_files(files: list[Path], mapping: dict) -> int:
    changed = 0
    for f in files:
        if not f.exists():
            continue
        text = f.read_text()
        new = text
        for old, repl in mapping.items():
            if old in new:
                new = new.replace(old, repl)
        if new != text:
            f.write_text(new)
            changed += 1
    return changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="Report only; no downloads/uploads/writes.")
    ap.add_argument("--files", nargs="*", help="Override target JSON files.")
    args = ap.parse_args()

    files = [Path(p) for p in args.files] if args.files else TARGET_FILES
    owned = set(KEEP_HOSTS)
    bucket = os.environ.get("HOME_ASSETS_BUCKET", "home-assets")
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    service_key = os.environ.get("SUPABASE_SERVICE_KEY", "")

    # Treat your own CDN host as already-owned so it is never re-uploaded.
    if supabase_url:
        owned.add(host_of(supabase_url))

    all_urls = collect_urls(files)
    todo = sorted(u for u in all_urls if needs_rehost(u, owned))
    keep = sorted(u for u in all_urls if not needs_rehost(u, owned))

    from collections import Counter
    hosts = Counter(host_of(u) for u in todo)
    print(f"Total media URLs: {len(all_urls)}")
    print(f"  keep (owned/TMDB): {len(keep)}")
    print(f"  to rehost:         {len(todo)}")
    print("  hosts to rehost:")
    for h, n in hosts.most_common():
        print(f"    {h:40s} {n}")

    if args.dry_run:
        print("\n[dry-run] no changes made.")
        return 0

    if not supabase_url or not service_key:
        print("\nERROR: set SUPABASE_URL and SUPABASE_SERVICE_KEY to upload.", file=sys.stderr)
        print("Re-run with --dry-run to preview without credentials.", file=sys.stderr)
        return 2

    mapping = load_map()
    ok, fail = 0, 0
    for i, url in enumerate(todo, 1):
        if url in mapping:
            continue
        path = object_path(url)
        try:
            data = download(url)
            new_url = upload(supabase_url, service_key, bucket, path, data, guess_content_type(path))
            mapping[url] = new_url
            ok += 1
            print(f"[{i}/{len(todo)}] OK  {url[:70]} -> {new_url.split('/')[-1]}")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            fail += 1
            print(f"[{i}/{len(todo)}] ERR {url[:70]} ({e})", file=sys.stderr)
        if i % 25 == 0:
            save_map(mapping)
    save_map(mapping)

    changed = rewrite_files(files, mapping)
    print(f"\nUploaded {ok}, failed {fail}. Rewrote {changed} JSON file(s).")
    if fail:
        print("Some assets failed (dead links). Fix or drop those tiles, then re-run.", file=sys.stderr)
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
