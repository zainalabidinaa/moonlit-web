
-- Run in Supabase SQL Editor: https://hvfsntdyowapjxobtyli.supabase.co
-- Adds 11 TV franchise collections with real Trakt list IDs.

BEGIN;

DELETE FROM folder_sources WHERE folder_id IN (
  SELECT id FROM folders WHERE collection_id IN (
    SELECT id FROM collections WHERE name = 'Series Universes'
  )
);
DELETE FROM folders WHERE collection_id IN (
  SELECT id FROM collections WHERE name = 'Series Universes'
);
DELETE FROM collections WHERE name = 'Series Universes';

DO $$
DECLARE
  col_id   uuid;
  max_sort int;

  f0 uuid;
  f1 uuid;
  f2 uuid;
  f3 uuid;
  f4 uuid;
  f5 uuid;
  f6 uuid;
  f7 uuid;
  f8 uuid;
  f9 uuid;
  f10 uuid;

BEGIN
  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO max_sort FROM collections;
  col_id := gen_random_uuid();

  INSERT INTO collections (id, name, sort_order, enabled, pin_to_top, view_mode, show_all_tab, focus_glow_enabled)
  VALUES (col_id, 'Series Universes', max_sort, true, true, 'FOLLOW_LAYOUT', true, false);


  -- Action Jack Ryan
  f0 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f0, col_id, 'Action Jack Ryan', 0, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f0, 'Jack Ryan / Clancyverse', 'trakt', '162', 'series', 'LIST', 'popularity', 0);

  -- Crime Breaking Bad
  f1 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f1, col_id, 'Crime Breaking Bad', 1, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f1, 'Breaking Bad', 'trakt', '23602779', 'series', 'LIST', 'popularity', 1);

  -- Crime Law & Order
  f2 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f2, col_id, 'Crime Law & Order', 2, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f2, 'Law & Order', 'trakt', '27910003', 'series', 'LIST', 'popularity', 2);

  -- Drama Yellowstone
  f3 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f3, col_id, 'Drama Yellowstone', 3, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f3, 'Yellowstone', 'trakt', '24695928', 'series', 'LIST', 'popularity', 3);

  -- Drama Grey's Anatomy
  f4 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f4, col_id, 'Drama Grey''s Anatomy', 4, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f4, 'Grey''s Anatomy', 'trakt', '11397151', 'series', 'LIST', 'popularity', 4);

  -- Horror The Walking Dead
  f5 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f5, col_id, 'Horror The Walking Dead', 5, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f5, 'The Walking Dead', 'trakt', '23844316', 'series', 'LIST', 'popularity', 5);

  -- Sci-Fi Star Trek
  f6 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f6, col_id, 'Sci-Fi Star Trek', 6, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f6, 'Star Trek', 'trakt', '22989542', 'series', 'LIST', 'popularity', 6);

  -- Sci-Fi Doctor Who
  f7 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f7, col_id, 'Sci-Fi Doctor Who', 7, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f7, 'Doctor Who', 'trakt', '6605884', 'series', 'LIST', 'popularity', 7);

  -- Sci-Fi Black Mirror
  f8 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f8, col_id, 'Sci-Fi Black Mirror', 8, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f8, 'Black Mirror', 'trakt', '3151200', 'series', 'LIST', 'popularity', 8);

  -- Animation The Simpsons
  f9 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f9, col_id, 'Animation The Simpsons', 9, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f9, 'The Simpsons / Futurama', 'trakt', '23360152', 'series', 'LIST', 'popularity', 9);

  -- Animation South Park
  f10 := gen_random_uuid();
  INSERT INTO folders (id, collection_id, name, sort_order, hide_title, tile_shape)
  VALUES (f10, col_id, 'Animation South Park', 10, true, 'POSTER');
  INSERT INTO folder_sources (id, folder_id, title, provider, tmdb_id, media_type, tmdb_source_type, sort_by, sort_order)
  VALUES (gen_random_uuid(), f10, 'South Park', 'trakt', '30360889', 'series', 'LIST', 'popularity', 10);

END $$;

COMMIT;
