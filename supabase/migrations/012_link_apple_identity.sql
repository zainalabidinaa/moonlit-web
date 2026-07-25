create or replace function public.link_apple_identity(
  p_user_id uuid,
  p_apple_sub text,
  p_apple_email text
) returns void
language plpgsql
security definer
set search_path = auth, public
as $$
begin
  if exists (
    select 1 from auth.identities
    where provider = 'apple' and provider_id = p_apple_sub
  ) then
    raise exception 'Apple ID is already linked to an account';
  end if;

  insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(),
    p_user_id,
    p_apple_sub,
    'apple',
    jsonb_build_object('sub', p_apple_sub, 'email', p_apple_email, 'email_verified', true),
    now(), now(), now()
  );
end;
$$;
