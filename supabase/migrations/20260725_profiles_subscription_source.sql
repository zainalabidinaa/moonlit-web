-- Tracks whether a profile's premium role came from a StoreKit purchase (via
-- RevenueCat) or was granted manually (admin / friends & family). The
-- RevenueCat webhook must only ever revert `role` to 'free' on expiration when
-- subscription_source = 'storekit' — otherwise an expiring/cancelled StoreKit
-- event could clobber a manually-granted role for the same user.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS subscription_source text
    CHECK (subscription_source IN ('storekit', 'manual') OR subscription_source IS NULL);
