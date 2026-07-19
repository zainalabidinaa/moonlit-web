-- installed_addons: owner-only row level security.
--
-- Rationale (App Store Review Guidelines 1.2 / 2.3.1 / 5.2.3):
-- A user's addon list must be writable ONLY by that user. This makes the app's
-- sync behave like the iCloud-synced survivor apps (Vidi/Omni): addons sync
-- across a user's own devices, but the developer's backend cannot inject a
-- stream source into a user's list. Deliberately NO service_role / admin
-- "manage all" write policy is created here — that is the injection vector we
-- are closing. Reads/writes are scoped to profiles owned by auth.uid().
--
-- NOTE: this migration also drops likely pre-existing permissive policies by
-- name. After applying, verify in the Supabase dashboard that NO other
-- permissive (USING true / service_role FOR ALL) policy remains on
-- installed_addons, and that no admin tooling writes this table via the
-- service_role key.

ALTER TABLE installed_addons ENABLE ROW LEVEL SECURITY;

-- Remove any broad/permissive policies that may have been created via the dashboard.
DROP POLICY IF EXISTS "Enable all access" ON installed_addons;
DROP POLICY IF EXISTS "Enable read access for all users" ON installed_addons;
DROP POLICY IF EXISTS "Enable insert for all users" ON installed_addons;
DROP POLICY IF EXISTS "Service role can manage all installed addons" ON installed_addons;
DROP POLICY IF EXISTS "Allow anon" ON installed_addons;

DROP POLICY IF EXISTS "Users can read own installed addons" ON installed_addons;
CREATE POLICY "Users can read own installed addons"
  ON installed_addons
  FOR SELECT
  USING (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert own installed addons" ON installed_addons;
CREATE POLICY "Users can insert own installed addons"
  ON installed_addons
  FOR INSERT
  WITH CHECK (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update own installed addons" ON installed_addons;
CREATE POLICY "Users can update own installed addons"
  ON installed_addons
  FOR UPDATE
  USING (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can delete own installed addons" ON installed_addons;
CREATE POLICY "Users can delete own installed addons"
  ON installed_addons
  FOR DELETE
  USING (
    profile_id IN (
      SELECT id FROM profiles WHERE user_id = auth.uid()
    )
  );
