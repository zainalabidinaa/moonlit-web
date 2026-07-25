ALTER TABLE profile_recommendations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own profile recommendations" ON profile_recommendations;
CREATE POLICY "Users can read own profile recommendations"
  ON profile_recommendations
  FOR SELECT
  USING (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Service role can manage all recommendations" ON profile_recommendations;
CREATE POLICY "Service role can manage all recommendations"
  ON profile_recommendations
  FOR ALL
  USING (true)
  WITH CHECK (true);
