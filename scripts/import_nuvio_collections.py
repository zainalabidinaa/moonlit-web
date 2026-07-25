#!/usr/bin/env python3
"""
Import Nuvio collections JSON into Supabase.
Wipes all existing collections (CASCADE deletes folders, folder_catalogs, folder_sources)
then re-inserts from the provided JSON file.
"""

import json
import sys
import uuid
import urllib.request
import urllib.error

SUPABASE_URL = "https://hvfsntdyowapjxobtyli.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2ZnNudGR5b3dhcGp4b2J0eWxpIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDE3ODQ5NSwiZXhwIjoyMDk1NzU0NDk1fQ.sB0HwWmcM8c5JQoqNnjvWoM0_Yd7IkXeNcweaGq-CuU"

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal",
}


def req(method, path, body=None):
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on {method} {path}: {e.read().decode()}")
        sys.exit(1)


def batch_insert(table, rows, chunk=100):
    for i in range(0, len(rows), chunk):
        req("POST", table, rows[i:i+chunk])


# --- Source resolution mirroring MoonlitCore/CollectionOrganizerParser.appendSource ---
# Discover sources (tmdbId 0, no catalogId) synthesize a catalog id from their title;
# tmdb COLLECTION → "tmdb.collection.<id>"; trakt → "trakt.list.<id>". These all land in
# folder_catalogs so the app (and the genre hub) read them the same way it reads the
# bundled JSON. Without this, such sources were dumped into folder_sources with no
# catalog_id and never resolved — the "tmdb issue".

DISCOVER_CATALOG_IDS = {
    ("movie", "new movies"): "tmdb.discover.movie.new-movies.069d5312",
    ("movie", "popular movies"): "tmdb.discover.movie.popular-movies.29727d26",
    ("movie", "top all time movies"): "tmdb.discover.movie.top-all-time-movies.39f5a0c4",
    ("movie", "top of the year movies"): "tmdb.discover.movie.top-of-the-year-movies.870b3ada",
    ("movie", "anime movies"): "tmdb.discover.movie.anime-movies.8caaddea",
    ("movie", "top anime movies"): "tmdb.discover.movie.top-anime-movies.ef410dcc",
    ("movie", "upcoming anime movies"): "tmdb.discover.movie.upcoming-anime-movies.e57db259",
    ("series", "new series"): "tmdb.discover.series.new-series.76fc7ade",
    ("series", "popular series"): "tmdb.discover.series.popular-series.20af3ad9",
    ("series", "top all time series"): "tmdb.discover.series.top-all-time-series.53046f30",
    ("series", "top of the year series"): "tmdb.discover.series.top-of-the-year-series.f0fd20b7",
    ("series", "anime series"): "tmdb.discover.series.anime-series.193e8308",
    ("series", "top anime series"): "tmdb.discover.series.top-anime-series.63ff4f07",
    ("series", "upcoming anime series"): "tmdb.discover.series.upcoming-anime-series.e71e22cf",
}

MOVIE_GENRES = {
    "28": "Action", "12": "Adventure", "16": "Animation", "35": "Comedy", "80": "Crime",
    "99": "Documentary", "18": "Drama", "10751": "Family", "14": "Fantasy", "36": "History",
    "27": "Horror", "10402": "Music", "9648": "Mystery", "10749": "Romance",
    "878": "Science Fiction", "10770": "TV Movie", "53": "Thriller", "10752": "War", "37": "Western",
}
SERIES_GENRES = {
    "10759": "Action & Adventure", "16": "Animation", "35": "Comedy", "80": "Crime",
    "99": "Documentary", "18": "Drama", "10751": "Family", "10762": "Kids", "9648": "Mystery",
    "10763": "News", "10764": "Reality", "10765": "Sci-Fi & Fantasy", "10766": "Soap",
    "10767": "Talk", "10768": "War & Politics", "37": "Western",
}

def normalize_media_type(value):
    u = (value or "").upper()
    if u in ("TV", "SERIES"):
        return "series"
    if u == "MOVIE":
        return "movie"
    return (value or "movie").lower()

def normalize_genre(value):
    if not value or str(value).lower() == "none":
        return None
    return value

def genre_name(with_genres, media_type):
    if not with_genres:
        return None
    first = str(with_genres).split(",")[0].strip()
    table = SERIES_GENRES if media_type == "series" else MOVIE_GENRES
    return table.get(first)

def resolve_raw(provider, catalog_id, media_type):
    if catalog_id.startswith("tmdb.discover."):
        return ("tmdb", catalog_id.split(".")[-1], "discover")
    if catalog_id.startswith("tmdb."):
        return ("tmdb", catalog_id[len("tmdb."):], None)
    if catalog_id.startswith("trakt.list."):
        return ("trakt", catalog_id[len("trakt.list."):], None)
    if catalog_id.startswith("mdblist."):
        return ("mdblist", catalog_id[len("mdblist."):], None)
    return (provider, catalog_id, None)

def process_source(s, idx, folder_id, seen, all_catalogs, all_sources):
    media_type = normalize_media_type(s.get("type") or s.get("mediaType"))
    is_discover = (s.get("tmdbSourceType") or "").upper() == "DISCOVER"
    raw_tmdb = s.get("tmdbId") or 0
    try:
        tmdb_int = int(raw_tmdb)
    except (TypeError, ValueError):
        tmdb_int = 0
    has_concrete = tmdb_int > 0
    filters = s.get("filters") or {}

    if s.get("catalogId"):
        eff = s["catalogId"]
    elif s.get("traktListId"):
        eff = f"trakt.list.{s['traktListId']}"
    elif has_concrete and (s.get("tmdbSourceType") or "").upper() == "COLLECTION":
        eff = f"tmdb.collection.{tmdb_int}"
    elif is_discover and not has_concrete and DISCOVER_CATALOG_IDS.get((media_type, (s.get("title") or "").lower())):
        eff = DISCOVER_CATALOG_IDS[(media_type, (s.get("title") or "").lower())]
    elif is_discover and filters.get("releaseDateGte"):
        try:
            year = int(str(filters["releaseDateGte"])[:4])
        except ValueError:
            return
        eff = f"tmdb.discover.{media_type}.decades.{(year // 10) * 10}s"
    else:
        return

    key = f"{folder_id}:{eff}"
    if key in seen:
        return
    seen.add(key)

    provider = (s.get("provider") or "").lower()
    is_addon = (provider in ("", "addon") or s.get("traktListId") or s.get("tmdbId")
                or (is_discover and not has_concrete))
    if is_addon:
        genre = normalize_genre(s.get("genre")) or genre_name(filters.get("withGenres"), media_type)
        all_catalogs.append({
            "folder_id": folder_id,
            "catalog_id": eff,
            "media_type": media_type,
            "genre": genre,
        })
        return

    rp, rid, rtype = resolve_raw(provider, eff, s.get("type"))
    all_sources.append({
        "folder_id": folder_id,
        "provider": rp,
        "title": None,
        "tmdb_id": rid,
        "media_type": media_type,
        "tmdb_source_type": rtype,
        "sort_by": s.get("sortBy"),
        "filters_json": None,
        "raw_json": json.dumps(s),
        "sort_order": idx,
    })


def main(json_path):
    with open(json_path) as f:
        data = json.load(f)

    print(f"Loaded {len(data)} collections from {json_path}")

    # 1. Wipe existing collections (CASCADE handles the rest)
    print("Deleting existing collections…")
    req("DELETE", "collections?id=neq.00000000-0000-0000-0000-000000000000")
    print("  Done.")

    all_folders = []
    all_catalogs = []
    all_sources = []

    for col_idx, col in enumerate(data):
        col_id = str(uuid.uuid4())

        col_row = {
            "id": col_id,
            "name": col["title"],
            "sort_order": col_idx,
            "enabled": True,
            "pin_to_top": col.get("pinToTop", False),
            "view_mode": col.get("viewMode", "FOLLOW_LAYOUT"),
            "show_all_tab": col.get("showAllTab", False),
            "focus_glow_enabled": col.get("focusGlowEnabled", False),
            "backdrop_image": col.get("backdropImageUrl"),
        }
        req("POST", "collections", col_row)
        print(f"[{col_idx+1}/{len(data)}] Collection: {col['title']}")

        for folder_idx, folder in enumerate(col.get("folders", [])):
            folder_id = str(uuid.uuid4())

            folder_row = {
                "id": folder_id,
                "collection_id": col_id,
                "name": folder["title"],
                "sort_order": folder_idx,
                "tile_shape": folder.get("tileShape", "LANDSCAPE"),
                "hide_title": folder.get("hideTitle", False),
                "focus_gif_enabled": folder.get("focusGifEnabled", False),
                "cover_image": folder.get("coverImageUrl") or folder.get("heroBackdropUrl"),
                "hero_backdrop": folder.get("heroBackdropUrl"),
                "focus_gif": folder.get("focusGifUrl"),
                "hero_video_url": folder.get("heroVideoUrl"),
                "title_logo": folder.get("titleLogoUrl"),
            }
            all_folders.append(folder_row)

            # Resolve every source the same way the app's parser does, so franchise
            # (tmdb.collection.*), browse (tmdb.discover.*) and explicit-catalogId rows all
            # land in folder_catalogs with a usable catalog_id + genre.
            seen_catalog_keys = set()
            combined = list(folder.get("catalogSources", [])) + list(folder.get("sources", []))
            for s_idx, s in enumerate(combined):
                process_source(s, s_idx, folder_id, seen_catalog_keys, all_catalogs, all_sources)

    # Batch insert folders first, then child rows
    print(f"Inserting {len(all_folders)} folders…")
    batch_insert("folders", all_folders, chunk=50)

    print(f"Inserting {len(all_catalogs)} folder_catalogs…")
    batch_insert("folder_catalogs", all_catalogs, chunk=100)

    print(f"Inserting {len(all_sources)} folder_sources…")
    batch_insert("folder_sources", all_sources, chunk=100)

    print(f"\nDone! {len(data)} collections, {len(all_folders)} folders, "
          f"{len(all_catalogs)} catalog sources, {len(all_sources)} TMDB sources.")


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else (
        "/Users/zain/Downloads/aiometadata and nuevio collections/"
        "nuvio-collections-profile-2-2026-06-14.json"
    )
    main(path)
