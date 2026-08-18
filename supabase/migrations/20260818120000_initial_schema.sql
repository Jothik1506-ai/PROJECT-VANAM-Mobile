-- Applied copy of ../schema.sql for `supabase db push`. Keep these two files
-- in sync by hand for now — one initial migration, not yet an incremental
-- migration history.

-- VANAM Mobile — Supabase schema for invite-only family chat.
--
-- See ARCHITECTURE.md Section 5 for the reasoning and the auth-flow
-- explanation (anonymous sign-in + invite redemption, since there is no
-- open signup and no email/phone in the locked login model).

create extension if not exists pgcrypto;

-- ============================================================================
-- profiles
-- One row per redeemed invite. id = auth.uid() of the anonymous Supabase
-- session that redeemed it — this IS the link between "a real family member"
-- and "an authenticated session," since there is no email/phone identity.
-- ============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  language text not null default 'English',
  -- Client-generated E2EE public key (base64), uploaded after redeeming the
  -- invite. Never a private key — that never leaves the device
  -- (ARCHITECTURE.md Section 6). Nullable because it's set slightly after
  -- profile creation, not atomically with it.
  public_key text,
  role text not null default 'member' check (role in ('member', 'admin')),
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per family member who has redeemed a real invite. A bare anonymous Supabase session with no profiles row can do nothing.';

-- ============================================================================
-- invite_codes
-- Admin-issued, one-time use. PIN is hashed, never stored or logged in
-- plaintext — the same discipline as a password, even though it's short.
-- ============================================================================
create table if not exists public.invite_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  pin_hash text not null,
  invitee_name text not null,
  created_by uuid not null references public.profiles (id),
  expires_at timestamptz not null,
  redeemed_by uuid references public.profiles (id),
  redeemed_at timestamptz,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.invite_codes is
  'Admin-issued invite codes. redeemed_by set once, permanently — invites are single-use.';

create index if not exists invite_codes_code_idx on public.invite_codes (code);

-- ============================================================================
-- messages
-- Ciphertext only. group_id is a fixed constant for V1's single family
-- group (see ARCHITECTURE.md — no per-contact DMs, no multi-group). Kept as
-- a column rather than hardcoded so Phase 2+ multi-group doesn't need a
-- breaking migration.
-- ============================================================================
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  group_id text not null default 'family-group',
  sender_id uuid not null references public.profiles (id),
  -- Ciphertext produced client-side. Supabase stores and relays bytes it
  -- cannot read — see ARCHITECTURE.md Section 6.
  body bytea not null,
  sent_at timestamptz not null default now()
);

comment on table public.messages is
  'Ciphertext only — see ARCHITECTURE.md Section 6. Supabase never receives plaintext.';

create index if not exists messages_group_sent_idx
  on public.messages (group_id, sent_at);

-- ============================================================================
-- Row Level Security
-- Every policy below is gated on "does an active, non-revoked profiles row
-- exist for auth.uid()" — that check is what makes "admin-approved access
-- only" actually enforced at the database, not just in app UI.
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.invite_codes enable row level security;
alter table public.messages enable row level security;

create or replace function public.is_active_member()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'active' and role = 'admin'
  );
$$;

-- profiles: members can see each other (it's a family group — knowing who
-- else is in it is expected), but can only edit their own row, and never
-- their own role/status (that would let a member self-promote to admin or
-- un-revoke themselves).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (public.is_active_member());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles where id = auth.uid())
    and status = (select status from public.profiles where id = auth.uid())
  );

-- Admins can change any member's role/status — this is the revocation path
-- (ARCHITECTURE.md Section 7: "admin can revoke a member"). Separate policy
-- from profiles_update_self rather than loosening it, so a self-update can
-- never accidentally grant a role/status change to a non-admin.
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles
  for update using (public.is_admin()) with check (public.is_admin());

-- invite_codes: admins only, in both directions. Regular members never see
-- outstanding invite codes or PIN hashes.
drop policy if exists invite_codes_admin_all on public.invite_codes;
create policy invite_codes_admin_all on public.invite_codes
  for all using (public.is_admin()) with check (public.is_admin());

-- messages: any active member can read the group and post to it. No update
-- or delete policy exists at all — messages are append-only, matching "no
-- message deletion in V1" from the chat requirements.
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select using (public.is_active_member());

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert with check (
    public.is_active_member() and sender_id = auth.uid()
  );

-- ============================================================================
-- redeem_invite(code, pin)
-- The only way an anonymous session becomes a real family member. Runs as
-- SECURITY DEFINER specifically so it can read invite_codes (which the
-- caller's own RLS would otherwise block, correctly, from a non-admin).
-- ============================================================================
create or replace function public.redeem_invite(
  invite_code text,
  invite_pin text
)
returns public.profiles
language plpgsql
security definer
as $$
declare
  invite public.invite_codes;
  new_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in (even anonymously) to redeem an invite';
  end if;

  select * into invite
  from public.invite_codes
  where code = invite_code
  for update; -- lock the row: two simultaneous redemptions of the same code must not both succeed

  if invite.id is null then
    raise exception 'Invalid invite code';
  end if;
  if invite.revoked then
    raise exception 'This invite has been revoked';
  end if;
  if invite.redeemed_by is not null then
    raise exception 'This invite has already been used';
  end if;
  if invite.expires_at < now() then
    raise exception 'This invite has expired';
  end if;
  if invite.pin_hash <> crypt(invite_pin, invite.pin_hash) then
    raise exception 'Incorrect PIN';
  end if;

  insert into public.profiles (id, display_name)
  values (auth.uid(), invite.invitee_name)
  returning * into new_profile;

  update public.invite_codes
  set redeemed_by = auth.uid(), redeemed_at = now()
  where id = invite.id;

  return new_profile;
end;
$$;

comment on function public.redeem_invite is
  'The only path from an anonymous session to a real profiles row. See ARCHITECTURE.md Section 5, auth model.';

-- ============================================================================
-- create_invite(invitee_name, pin, ttl_days)
-- Admin-only (enforced inside, not just by RLS, since it also needs to
-- generate/hash before any row exists to check RLS against on insert).
-- ============================================================================
create or replace function public.create_invite(
  invitee_name text,
  invite_pin text,
  ttl_days int default 7
)
returns public.invite_codes
language plpgsql
security definer
as $$
declare
  new_invite public.invite_codes;
  generated_code text;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can create invites';
  end if;
  if invite_pin !~ '^[0-9]{4,6}$' then
    raise exception 'PIN must be 4-6 digits';
  end if;

  -- Human-shareable over WhatsApp: e.g. VANAM-7F2K9Q. Collision retried by
  -- the unique constraint on invite_codes.code if it ever happens (astronomically unlikely at family scale).
  generated_code := 'VANAM-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));

  insert into public.invite_codes (code, pin_hash, invitee_name, created_by, expires_at)
  values (
    generated_code,
    crypt(invite_pin, gen_salt('bf')),
    invitee_name,
    auth.uid(),
    now() + (ttl_days || ' days')::interval
  )
  returning * into new_invite;

  return new_invite;
end;
$$;

comment on function public.create_invite is
  'Admin-only. Generates the code, hashes the PIN — the plaintext PIN is never stored.';
