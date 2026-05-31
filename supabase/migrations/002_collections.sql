-- supabase/migrations/002_collections.sql

-- System-level Stremio addon config (single row, always upsert)
CREATE TABLE IF NOT EXISTS system_addon (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  manifest_url TEXT NOT NULL,
  name         TEXT,
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- Collection rows (each becomes a horizontal row on the homepage)
CREATE TABLE IF NOT EXISTS collections (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT NOT NULL,
  sort_order  INTEGER DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Folder tiles within a collection row
CREATE TABLE IF NOT EXISTS folders (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  collection_id UUID REFERENCES collections(id) ON DELETE CASCADE NOT NULL,
  name          TEXT NOT NULL,
  cover_image   TEXT,
  focus_gif     TEXT,
  sort_order    INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- Stremio catalog sources attached to a folder
CREATE TABLE IF NOT EXISTS folder_catalogs (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  folder_id  UUID REFERENCES folders(id) ON DELETE CASCADE NOT NULL,
  catalog_id TEXT NOT NULL,
  media_type TEXT NOT NULL
);

-- RLS
ALTER TABLE system_addon     ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections      ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE folder_catalogs  ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read
CREATE POLICY "Authenticated users can read system_addon"
  ON system_addon FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can read collections"
  ON collections FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can read folders"
  ON folders FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can read folder_catalogs"
  ON folder_catalogs FOR SELECT USING (auth.uid() IS NOT NULL);

-- Only admin can write
CREATE POLICY "Admins can manage system_addon"
  ON system_addon FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage collections"
  ON collections FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage folders"
  ON folders FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins can manage folder_catalogs"
  ON folder_catalogs FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'));
