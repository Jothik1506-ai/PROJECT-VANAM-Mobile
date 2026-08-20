-- Fix: admin_create_member's raw insert into auth.users left several
-- GoTrue token columns (confirmation_token, recovery_token,
-- email_change_token_new, email_change, email_change_token_current,
-- reauthentication_token, phone_change, phone_change_token) as NULL
-- instead of '' — GoTrue's Go code cannot scan NULL into those string
-- fields, so any login attempt for an account created this way failed
-- with a generic "Database error querying schema" (not a credentials
-- error — the row was simply unreadable by the auth service). Live-
-- reproduced on the first real admin_create_member account
-- ("vanam_jothik"): backfilled that row directly, this migration fixes
-- the function so it never happens again.

drop function if exists public.admin_create_member(text);
create or replace function public.admin_create_member(p_display_name text)
returns table (username text, temp_password text, recovery_code text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_username text;
  new_id uuid := gen_random_uuid();
  synthetic_email text;
  default_password constant text := 'vanam_2026';
  new_recovery_code text;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can create members';
  end if;
  if coalesce(trim(p_display_name), '') = '' then
    raise exception 'Enter a name for the new member';
  end if;

  new_username := public.generate_member_username(p_display_name);
  synthetic_email := new_username || '@vanam.local';
  new_recovery_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, reauthentication_token,
    phone_change, phone_change_token
  ) values (
    '00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
    synthetic_email, crypt(default_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, false, false,
    '', '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), new_id, new_id::text,
    jsonb_build_object('sub', new_id::text, 'email', synthetic_email),
    'email', now(), now(), now()
  );

  insert into public.profiles (id, display_name, username, password_changed, recovery_code_hash)
  values (new_id, trim(p_display_name), new_username, false, crypt(new_recovery_code, gen_salt('bf')));

  return query select new_username, default_password, new_recovery_code;
end;
$$;

comment on function public.admin_create_member is
  'Admin-only. Creates a real password-auth account for a brand-new member and returns the one-time credentials + recovery code to show/QR-encode.';

grant execute on function public.admin_create_member(text) to authenticated;

-- Backfill: any existing account with a NULL token column (only
-- admin_create_member could have produced this — admin_issue_credentials
-- only ever UPDATEs an existing, already-valid auth.users row).
update auth.users
set confirmation_token = coalesce(confirmation_token, ''),
    recovery_token = coalesce(recovery_token, ''),
    email_change_token_new = coalesce(email_change_token_new, ''),
    email_change = coalesce(email_change, ''),
    email_change_token_current = coalesce(email_change_token_current, ''),
    reauthentication_token = coalesce(reauthentication_token, ''),
    phone_change = coalesce(phone_change, ''),
    phone_change_token = coalesce(phone_change_token, '')
where confirmation_token is null
   or recovery_token is null
   or email_change_token_new is null
   or email_change is null
   or email_change_token_current is null
   or reauthentication_token is null
   or phone_change is null
   or phone_change_token is null;
