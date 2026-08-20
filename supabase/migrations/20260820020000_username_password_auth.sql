-- Replaces invite-code+PIN login with real username/password accounts.
--
-- Why: anonymous Supabase auth ties a family member's identity to one
-- device's locally-persisted session. Clearing app data, or moving to a
-- new phone, meant the member had no way back into their own account and
-- message history — there was no credential, only a device-local session.
--
-- New model:
--   - Admin creates a member with `admin_create_member(display_name)`,
--     which mints `vanam_<slug>` as a username and 'vanam_2026' as a
--     default password, and creates a real auth.users row for it directly
--     (email/password auth, using a synthetic `<username>@vanam.local`
--     email so Supabase's email/password grant works with no real inbox).
--   - The member logs in with that username+password from any device,
--     any time — the credential, not the device, carries the identity.
--   - `password_changed` forces a one-time "set your own password" screen
--     after first login (or after an admin-issued reset).
--   - The QR code shown to a new member now encodes username+password so
--     scanning it logs them straight in, then walks into that same
--     set-password screen.
--
-- Existing members (created under the old anonymous+invite flow) keep
-- their profiles row and all their message history untouched — an admin
-- upgrades each one to password auth with `admin_issue_credentials`,
-- which attaches email/password to their *existing* auth.users id rather
-- than creating a new one, so nothing they've sent is orphaned.

alter table public.profiles
  add column if not exists username text unique,
  add column if not exists password_changed boolean not null default true;

comment on column public.profiles.password_changed is
  'False right after admin_create_member/admin_issue_credentials/admin_reset_member_password — forces the one-time set-your-own-password screen. Existing rows default true so nobody already active gets stopped by a screen that doesn''t apply to them.';

-- Turns "Jothik Reddy" into a stable, unique `vanam_jothikreddy` (retrying
-- with a numeric suffix on collision) — never touches auth.users directly;
-- callers insert/update using the returned value.
create or replace function public.generate_member_username(p_display_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  base text;
  candidate text;
  suffix int := 0;
begin
  base := lower(regexp_replace(coalesce(p_display_name, 'member'), '[^a-zA-Z0-9]', '', 'g'));
  if base = '' then
    base := 'member';
  end if;

  candidate := 'vanam_' || base;
  while exists (select 1 from public.profiles where username = candidate) loop
    suffix := suffix + 1;
    candidate := 'vanam_' || base || suffix::text;
  end loop;

  return candidate;
end;
$$;

-- ============================================================================
-- admin_create_member(display_name)
-- Brand-new member: creates both the auth.users row (email/password,
-- pre-confirmed) and the profiles row in one call. Writing directly into
-- auth.users/auth.identities from SQL is the standard workaround for
-- "admin creates a password account" when there's no server/edge-function
-- holding a service-role key — GoTrue's password grant only checks
-- auth.users.email + encrypted_password, so this is sufficient for
-- signInWithPassword to work immediately after.
-- ============================================================================
create or replace function public.admin_create_member(p_display_name text)
returns table (username text, temp_password text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_username text;
  new_id uuid := gen_random_uuid();
  synthetic_email text;
  default_password constant text := 'vanam_2026';
begin
  if not public.is_admin() then
    raise exception 'Only an admin can create members';
  end if;
  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'Enter a name for the new member';
  end if;

  new_username := public.generate_member_username(p_display_name);
  synthetic_email := new_username || '@vanam.local';

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
    synthetic_email, crypt(default_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false, false
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), new_id, new_id::text,
    jsonb_build_object('sub', new_id::text, 'email', synthetic_email),
    'email', now(), now(), now()
  );

  insert into public.profiles (id, display_name, username, password_changed)
  values (new_id, trim(p_display_name), new_username, false);

  return query select new_username, default_password;
end;
$$;

comment on function public.admin_create_member is
  'Admin-only. Creates a real password-auth account for a brand-new member and returns the one-time credentials to show/QR-encode.';

-- ============================================================================
-- admin_issue_credentials(member_id)
-- Upgrades an EXISTING member (created under the old anonymous+invite
-- flow, or any account that still has no username) to password auth —
-- same auth.users.id, so their message history stays attached.
-- ============================================================================
create or replace function public.admin_issue_credentials(p_member_id uuid)
returns table (username text, temp_password text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_username text;
  target_display_name text;
  synthetic_email text;
  default_password constant text := 'vanam_2026';
begin
  if not public.is_admin() then
    raise exception 'Only an admin can issue credentials';
  end if;

  select display_name into target_display_name
  from public.profiles where id = p_member_id;

  if target_display_name is null then
    raise exception 'No such member';
  end if;

  new_username := public.generate_member_username(target_display_name);
  synthetic_email := new_username || '@vanam.local';

  -- is_anonymous must be cleared explicitly: GoTrue refuses
  -- auth.updateUser(password:) for any account still flagged anonymous,
  -- even after it has a real email + password set here.
  update auth.users
  set email = synthetic_email,
      encrypted_password = crypt(default_password, gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      is_anonymous = false,
      updated_at = now()
  where id = p_member_id;

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), p_member_id, p_member_id::text,
    jsonb_build_object('sub', p_member_id::text, 'email', synthetic_email),
    'email', now(), now(), now()
  )
  on conflict (provider, provider_id) do update
    set identity_data = excluded.identity_data, updated_at = now();

  update public.profiles
  set username = new_username, password_changed = false
  where id = p_member_id;

  return query select new_username, default_password;
end;
$$;

comment on function public.admin_issue_credentials is
  'Admin-only. Attaches username/password login to an existing member''s current account (same id, so message history is preserved).';

-- ============================================================================
-- admin_reset_member_password(member_id)
-- For a member who forgot their password and doesn't have the QR anymore.
-- ============================================================================
create or replace function public.admin_reset_member_password(p_member_id uuid)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  default_password constant text := 'vanam_2026';
begin
  if not public.is_admin() then
    raise exception 'Only an admin can reset a password';
  end if;

  update auth.users
  set encrypted_password = crypt(default_password, gen_salt('bf')),
      updated_at = now()
  where id = p_member_id;

  if not found then
    raise exception 'No such member';
  end if;

  update public.profiles
  set password_changed = false
  where id = p_member_id;

  return default_password;
end;
$$;

comment on function public.admin_reset_member_password is
  'Admin-only. Resets a member back to the default password and forces the set-password screen again.';

-- ============================================================================
-- mark_own_password_changed()
-- Called right after the member successfully sets their own password via
-- supabase auth.updateUser — clears the "must change password" flag.
-- ============================================================================
create or replace function public.mark_own_password_changed()
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles set password_changed = true where id = auth.uid();
$$;

grant execute on function public.generate_member_username(text) to authenticated;
grant execute on function public.admin_create_member(text) to authenticated;
grant execute on function public.admin_issue_credentials(uuid) to authenticated;
grant execute on function public.admin_reset_member_password(uuid) to authenticated;
grant execute on function public.mark_own_password_changed() to authenticated;
