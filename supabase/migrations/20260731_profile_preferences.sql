create table if not exists public.profile_preferences (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  namespace text not null check (namespace in ('home', 'artwork', 'player', 'subtitles')),
  schema_version integer not null check (schema_version > 0),
  value jsonb not null default '{}'::jsonb check (jsonb_typeof(value) = 'object'),
  updated_at timestamptz not null default now(),
  primary key (profile_id, namespace)
);

alter table public.profile_preferences enable row level security;

drop policy if exists "profile owners manage preferences" on public.profile_preferences;
create policy "profile owners manage preferences"
  on public.profile_preferences
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.profiles
      where profiles.id = profile_preferences.profile_id
        and profiles.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.profiles
      where profiles.id = profile_preferences.profile_id
        and profiles.user_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.profile_preferences to authenticated;
