-- 007_dedup_kaptain_collections.sql
-- Removes duplicates caused by re-running 006_kaptain_collections.sql
-- Keeps the earliest (lowest created_at) row per unique key

-- 1. Delete duplicate folder_catalogs
DELETE FROM folder_catalogs
WHERE id NOT IN (
  SELECT DISTINCT ON (folder_id, catalog_id) id
  FROM folder_catalogs
  ORDER BY folder_id, catalog_id, id ASC
);

-- 2. Delete duplicate folders
DELETE FROM folders
WHERE id NOT IN (
  SELECT DISTINCT ON (collection_id, name) id
  FROM folders
  ORDER BY collection_id, name, id ASC
);

-- 3. Delete duplicate collections
DELETE FROM collections
WHERE id NOT IN (
  SELECT DISTINCT ON (name) id
  FROM collections
  ORDER BY name, id ASC
);
