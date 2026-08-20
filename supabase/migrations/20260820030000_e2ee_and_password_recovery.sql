-- Two independent features in one migration (both touch auth/profiles):
--
-- 1. End-to-end encryption for messages (family group + direct chats).
--    Design: each device generates an X25519 keypair on first login and
--    uploads only the public half to profiles.public_key (already existed,
--    unused, pre-staged for exactly this). A random 32-byte symmetric key
--    is generated once per chat scope (the family group, or each direct
--    conversation) by whichever device first needs it, then "sealed"
--    (anonymous-sender public-key encryption, libsodium crypto_box_seal
--    style: ephemeral X25519 keypair + HKDF + AES-GCM, zero nonce is safe
--    here because the derived key is unique per seal) individually to
--    every current participant's public key and stored in key_wraps. The
--    server only ever stores/relays ciphertext and sealed keys — it has no
--    way to read a message, by construction, matching the "Supabase never
--    receives plaintext" comment already on the messages table.
--    New members (or members opening the feature for the first time) get
--    their key wrap opportunistically: any device that already holds the
--    scope's symmetric key checks list_missing_key_wraps() on chat open
--    and seals+uploads for anyone missing one whose public_key is now set.
--
-- 2. Self-service password recovery. There's no real email/phone in this
--    app's login model (see 20260820020000), so "forgot password" can't be
--    a magic-link flow. Instead a one-time recovery code is generated
--    alongside every admin-issued credential set, hashed (never stored
--    plaintext, same discipline as the old invite PIN), and can be
--    exchanged exactly once for a new password without involving the
--    admin. Using it consumes it — a new one is only minted by the admin
--    issuing/resetting credentials again.

-- ============================================================================
-- 1. End-to-end encryption
-- ============================================================================

create table if not exists public.key_wraps (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('group', 'direct')),
  -- 'family-group' for the group scope, or the conversation id (as text)
  -- for a direct chat. Not a foreign key on purpose — one column has to
  -- serve two different id spaces.
  scope_id text not null,
  member_id uuid not null references public.profiles (id) on delete cascade,
  -- ephemeral_pubkey(32 bytes) || AES-GCM ciphertext+tag, sealing the
  -- scope's 32-byte symmetric key to member_id's public key. Only that
  -- member's private key (never uploaded, device-local) can open it.
  sealed_key bytea not null,
  created_at timestamptz not null default now(),
  unique (scope, scope_id, member_id)
);

comment on table public.key_wraps is
  'Each row is one chat-scope symmetric key, encrypted so only one specific member can read it. The server stores only sealed (unreadable) key material — see ARCHITECTURE.md Section 6.';

alter table public.key_wraps enable row level security;

-- A member can always read their own key wraps (how their device recovers
-- the scope's symmetric key). Writing a wrap for someone else is allowed
-- only for a scope the writer can also see the plaintext key for — i.e.
-- an active member for the group, or a participant for a direct scope —
-- which is exactly what lets an already-keyed device seal for a
-- newly-joined member.
drop policy if exists key_wraps_select on public.key_wraps;
create policy key_wraps_select on public.key_wraps
  for select using (member_id = auth.uid());

drop policy if exists key_wraps_insert on public.key_wraps;
create policy key_wraps_insert on public.key_wraps
  for insert with check (
    case scope
      when 'group' then public.is_active_member()
      when 'direct' then public.is_conversation_participant(scope_id::uuid)
      else false
    end
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'key_wraps'
  ) then
    alter publication supabase_realtime add table public.key_wraps;
  end if;
end $$;

-- Whether the group scope has been bootstrapped yet at all — distinguishes
-- "no one has created the group key yet, I should be the one to" from "the
-- key exists, I'm just still waiting for my wrap".
create or replace function public.group_key_exists()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.key_wraps where scope = 'group'
  );
$$;

-- Which active participants of a scope don't have a key_wraps row yet —
-- callable by any device that already holds the plaintext key, to know
-- who it should seal+upload for next.
create or replace function public.list_missing_key_wraps(
  p_scope text,
  p_scope_id text
)
returns table (member_id uuid, public_key text)
language sql
security definer
stable
set search_path = public
as $$
  select p.id, p.public_key
  from public.profiles p
  where p.public_key is not null
    and (
      (p_scope = 'group' and p.status = 'active')
      or (
        p_scope = 'direct'
        and exists (
          select 1 from public.conversation_participants cp
          where cp.conversation_id = p_scope_id::uuid and cp.user_id = p.id
        )
      )
    )
    and not exists (
      select 1 from public.key_wraps kw
      where kw.scope = p_scope and kw.scope_id = p_scope_id and kw.member_id = p.id
    );
$$;

create or replace function public.upload_key_wrap(
  p_scope text,
  p_scope_id text,
  p_member_id uuid,
  p_sealed_key text -- base64
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.key_wraps (scope, scope_id, member_id, sealed_key)
  values (p_scope, p_scope_id, p_member_id, decode(p_sealed_key, 'base64'))
  on conflict (scope, scope_id, member_id) do nothing;
$$;

create or replace function public.fetch_my_key_wrap(
  p_scope text,
  p_scope_id text
)
returns text -- base64, or null if not sealed for me yet
language sql
security definer
stable
set search_path = public
as $$
  select encode(sealed_key, 'base64')
  from public.key_wraps
  where scope = p_scope and scope_id = p_scope_id and member_id = auth.uid();
$$;

grant execute on function public.group_key_exists() to authenticated;
grant execute on function public.list_missing_key_wraps(text, text) to authenticated;
grant execute on function public.upload_key_wrap(text, text, uuid, text) to authenticated;
grant execute on function public.fetch_my_key_wrap(text, text) to authenticated;

-- Re-grant: dropping+recreating a function drops its prior grants too.
grant execute on function public.send_message(text, text) to authenticated;
grant execute on function public.list_messages(text, integer) to authenticated;
grant execute on function public.list_direct_conversations() to authenticated;
grant execute on function public.list_direct_messages(uuid, integer) to authenticated;
grant execute on function public.send_direct_message(uuid, text) to authenticated;

-- message_text params below now carry base64-encoded ciphertext, not
-- plaintext — decode/encode replaces convert_to/convert_from. The Flutter
-- side encrypts before calling send_*, and decrypts what list_*/realtime
-- returns; the RPC surface (param/column names) is unchanged so this is a
-- transparent swap, matching the seam the original schema.sql comment
-- anticipated.
-- Matches the function's ACTUAL live signature (p_-prefixed params, a
-- `kind` OUT column for system events) which had already drifted from
-- schema.sql on disk — confirmed via pg_get_functiondef before writing
-- this, rather than trusting the checked-in file.
drop function if exists public.send_message(text, text);
create or replace function public.send_message(
  p_message_text text,
  p_group_id text default 'family-group'
)
returns table (
  id uuid,
  group_id text,
  sender_id uuid,
  sender_name text,
  message_text text,
  sent_at timestamptz,
  kind text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  inserted public.messages;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can send messages';
  end if;

  if length(trim(coalesce(p_message_text, ''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  insert into public.messages (group_id, sender_id, body)
  values (p_group_id, auth.uid(), decode(p_message_text, 'base64'))
  returning * into inserted;

  return query
  select
    inserted.id,
    inserted.group_id,
    inserted.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    encode(inserted.body, 'base64') as message_text,
    inserted.sent_at,
    inserted.kind
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

drop function if exists public.list_messages(text, integer);
create or replace function public.list_messages(
  p_group_id text default 'family-group',
  p_message_limit integer default 100
)
returns table (
  id uuid,
  group_id text,
  sender_id uuid,
  sender_name text,
  message_text text,
  sent_at timestamptz,
  kind text
)
language sql
security definer
stable
set search_path = public, extensions
as $$
  select
    m.id,
    m.group_id,
    m.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    encode(m.body, 'base64') as message_text,
    m.sent_at,
    m.kind
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where
    public.is_active_member()
    and m.group_id = p_group_id
  order by m.sent_at asc
  limit greatest(1, least(p_message_limit, 500));
$$;

drop function if exists public.list_direct_messages(uuid, integer);
create or replace function public.list_direct_messages(
  p_conversation_id uuid,
  p_message_limit integer default 100
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  message_text text,
  sent_at timestamptz
)
language sql
security definer
stable
set search_path = public, extensions
as $$
  select
    dm.id,
    dm.conversation_id,
    dm.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    encode(dm.body, 'base64') as message_text,
    dm.sent_at
  from public.direct_messages dm
  join public.profiles p on p.id = dm.sender_id
  where
    public.is_conversation_participant(p_conversation_id)
    and dm.conversation_id = p_conversation_id
  order by dm.sent_at asc
  limit greatest(1, least(p_message_limit, 500));
$$;

drop function if exists public.send_direct_message(uuid, text);
create or replace function public.send_direct_message(
  p_conversation_id uuid,
  p_message_text text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  message_text text,
  sent_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  inserted public.direct_messages;
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'Not a participant in this conversation';
  end if;

  if length(trim(coalesce(p_message_text, ''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  insert into public.direct_messages (conversation_id, sender_id, body)
  values (
    p_conversation_id,
    auth.uid(),
    decode(p_message_text, 'base64')
  )
  returning * into inserted;

  return query
  select
    inserted.id,
    inserted.conversation_id,
    inserted.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    encode(inserted.body, 'base64') as message_text,
    inserted.sent_at
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

-- list_direct_conversations' last-message preview used to decode the body
-- as UTF8 text for a plaintext snippet; that's no longer possible (it's
-- ciphertext now), so the preview becomes a generic placeholder. The
-- Flutter UI can still show its own decrypted preview if it wants better
-- than this later — this just stops it crashing/showing garbled bytes.
drop function if exists public.list_direct_conversations();
create or replace function public.list_direct_conversations()
returns table (
  conversation_id uuid,
  other_user_id uuid,
  other_display_name text,
  last_message_text text,
  last_message_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    c.id as conversation_id,
    other_p.id as other_user_id,
    other_p.display_name as other_display_name,
    case when lm.sent_at is not null then 'New message' else null end as last_message_text,
    lm.sent_at as last_message_at
  from public.conversation_participants me
  join public.conversations c on c.id = me.conversation_id
  join public.conversation_participants other
    on other.conversation_id = c.id and other.user_id <> auth.uid()
  join public.profiles other_p on other_p.id = other.user_id
  left join lateral (
    select dm.sent_at
    from public.direct_messages dm
    where dm.conversation_id = c.id
    order by dm.sent_at desc
    limit 1
  ) lm on true
  where me.user_id = auth.uid() and public.is_active_member()
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

-- ============================================================================
-- 2. Password recovery codes
-- ============================================================================

alter table public.profiles
  add column if not exists recovery_code_hash text;

comment on column public.profiles.recovery_code_hash is
  'bcrypt hash of a one-time recovery code, minted alongside admin_create_member/admin_issue_credentials/admin_reset_member_password. Null once used (reset_password_with_recovery_code) or never issued.';

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

  insert into public.profiles (id, display_name, username, password_changed, recovery_code_hash)
  values (new_id, trim(p_display_name), new_username, false, crypt(new_recovery_code, gen_salt('bf')));

  return query select new_username, default_password, new_recovery_code;
end;
$$;

comment on function public.admin_create_member is
  'Admin-only. Creates a real password-auth account for a brand-new member and returns the one-time credentials + recovery code to show/QR-encode.';

drop function if exists public.admin_issue_credentials(uuid);
create or replace function public.admin_issue_credentials(p_member_id uuid)
returns table (username text, temp_password text, recovery_code text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  new_username text;
  target_display_name text;
  synthetic_email text;
  default_password constant text := 'vanam_2026';
  new_recovery_code text;
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
  new_recovery_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));

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
  set username = new_username, password_changed = false,
      recovery_code_hash = crypt(new_recovery_code, gen_salt('bf'))
  where id = p_member_id;

  return query select new_username, default_password, new_recovery_code;
end;
$$;

comment on function public.admin_issue_credentials is
  'Admin-only. Attaches username/password login to an existing member''s current account (same id, so message history is preserved) and mints a recovery code.';

drop function if exists public.admin_reset_member_password(uuid);
create or replace function public.admin_reset_member_password(p_member_id uuid)
returns table (temp_password text, recovery_code text)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  default_password constant text := 'vanam_2026';
  new_recovery_code text;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can reset a password';
  end if;

  new_recovery_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));

  update auth.users
  set encrypted_password = crypt(default_password, gen_salt('bf')),
      updated_at = now()
  where id = p_member_id;

  if not found then
    raise exception 'No such member';
  end if;

  update public.profiles
  set password_changed = false,
      recovery_code_hash = crypt(new_recovery_code, gen_salt('bf'))
  where id = p_member_id;

  return query select default_password, new_recovery_code;
end;
$$;

comment on function public.admin_reset_member_password is
  'Admin-only. Resets a member back to the default password, forces the set-password screen again, and mints a fresh recovery code.';

-- ============================================================================
-- reset_password_with_recovery_code(username, recovery_code, new_password)
-- The self-service path: no admin, no session required (callable by the
-- Login screen's "Forgot password?" flow before signing in). One-time use
-- — succeeding clears recovery_code_hash, so the same code can't be reused
-- and a fresh one only comes from the admin issuing/resetting again.
-- ============================================================================
create or replace function public.reset_password_with_recovery_code(
  p_username text,
  p_recovery_code text,
  p_new_password text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  target public.profiles;
begin
  if length(coalesce(p_new_password, '')) < 6 then
    raise exception 'New password must be at least 6 characters';
  end if;

  select * into target
  from public.profiles
  where username = lower(trim(p_username));

  if target.id is null or target.recovery_code_hash is null then
    raise exception 'Invalid username or recovery code';
  end if;

  if target.recovery_code_hash <> crypt(trim(p_recovery_code), target.recovery_code_hash) then
    raise exception 'Invalid username or recovery code';
  end if;

  update auth.users
  set encrypted_password = crypt(p_new_password, gen_salt('bf')),
      updated_at = now()
  where id = target.id;

  update public.profiles
  set password_changed = true, recovery_code_hash = null
  where id = target.id;
end;
$$;

comment on function public.reset_password_with_recovery_code is
  'Self-service password reset — no session needed. One-time use: succeeding consumes the recovery code.';

grant execute on function public.reset_password_with_recovery_code(text, text, text) to anon, authenticated;
