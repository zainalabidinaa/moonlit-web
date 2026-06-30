ALTER TABLE profile_recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile recommendations"
  ON profile_recommendations
  FOR SELECT
  USING (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Service role can manage all recommendations"
  ON profile_recommendations
  FOR ALL
  USING (true)
  WITH CHECK (true);
