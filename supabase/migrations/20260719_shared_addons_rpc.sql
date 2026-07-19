-- Shared addon inheritance (replaces the removed system_addon broadcast on iOS).
--
-- Authenticated users inherit the admin's curated addons. Implemented as a
-- SECURITY DEFINER function so a caller can read the admin's addon URLs WITHOUT
-- weakening the owner-only RLS on installed_addons (see
-- 20260719_installed_addons_owner_only_rls.sql). The function only ever returns
-- addon URLs from admin-role profiles — nothing else private.
--
-- COMPLIANCE: the iOS client applies a stream-resource guard to everything this
-- returns, so a stream addon in the admin's list is NEVER activated for other
-- users. Only catalog/metadata/subtitle addons propagate. The backend must not
-- deliver a stream source to users (App Store Review Guidelines 5.2.3 / 2.3.1);
-- users obtain their own stream addon via a user-initiated install.

create or replace function public.get_shared_addons()
returns table(addon_url text, sort_order int)
language sql
security definer
set search_path = public
as $$
  select ia.addon_url, min(ia.sort_order)::int as sort_order
  from installed_addons ia
  join profiles p on p.id = ia.profile_id
  where p.role = 'admin'
    and coalesce(ia.enabled, true) = true
  group by ia.addon_url
  order by sort_order asc
$$;

-- Only signed-in users may read the shared list; anon/guests get bundled defaults only.
revoke all on function public.get_shared_addons() from public;
grant execute on function public.get_shared_addons() to authenticated;
