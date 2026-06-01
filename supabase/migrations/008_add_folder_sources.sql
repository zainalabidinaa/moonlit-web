-- 008_add_folder_sources.sql
-- Raw community-pack source definitions alongside normalized folder_catalogs

CREATE TABLE IF NOT EXISTS folder_sources (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  folder_id       UUID REFERENCES folders(id) ON DELETE CASCADE NOT NULL,
  provider        TEXT    NOT NULL,
  title           TEXT,
  tmdb_id         TEXT,
  media_type      TEXT,
  tmdb_source_type TEXT,
  sort_by         TEXT,
  filters_json    TEXT,
  raw_json        TEXT,
  sort_order      INTEGER DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE folder_sources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read folder_sources"
  ON folder_sources FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Admins can manage folder_sources"
  ON folder_sources FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND role = 'admin'));
