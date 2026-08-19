-- Join-flow completion: when a member sets their own real name for the
-- first time (see 20260818160000_member_own_display_name.sql), post a
-- system event into the family group so existing members see "<Name>
-- joined Vanam" — the join itself becomes visible, not silent.
--
-- Also lays foundation tables for future direct/personal chats between
-- members. Not wired to any RPC or UI yet — additive only, so it cannot
-- affect the existing family-group chat path.

-- ============================================================================
-- messages.kind — distinguishes a normal chat message from a system event
-- (e.g. a join notice). Additive, defaults to 'user' so every existing row
-- and every existing send_message/list_messages caller is unaffected.
-- ============================================================================
alter table public.messages
  add column if not exists kind text not null default 'user'
  check (kind in ('user', 'system'));

-- ============================================================================
-- set_own_display_name: post a join event the first time a name is set.
-- Re-declared (not just altered) because the join-event insert must run in
-- the same transaction as the name update — if either fails, neither
-- happens. Uses "was name_confirmed false before this call" as the signal
-- for "this is the member's first time setting their name", so renaming
-- later (Profile > Edit) never re-fires the join event.
-- ============================================================================
create or replace function public.set_own_display_name(p_display_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  was_first_time boolean;
  clean_name text;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can set their name';
  end if;

  clean_name := trim(coalesce(p_display_name, ''));

  if length(clean_name) = 0 then
    raise exception 'Name cannot be empty';
  end if;

  if length(clean_name) > 60 then
    raise exception 'Name is too long';
  end if;

  select not name_confirmed into was_first_time
  from public.profiles
  where id = auth.uid();

  update public.profiles
  set display_name = clean_name, name_confirmed = true
  where id = auth.uid();

  if was_first_time then
    insert into public.messages (group_id, sender_id, body, kind)
    values (
      'family-group',
      auth.uid(),
      convert_to(clean_name || ' joined Vanam', 'UTF8'),
      'system'
    );
  end if;
end;
$$;

grant execute on function public.set_own_display_name(text) to authenticated;

-- ============================================================================
-- send_message / list_messages: now also return kind, so the client can
-- render a system event differently (centered notice, not a chat bubble)
-- instead of showing it as a message "from" the new member.
--
-- Dropped first: Postgres refuses `create or replace` when the OUT
-- parameters (the RETURNS TABLE row shape) change, even by just adding a
-- column.
-- ============================================================================
drop function if exists public.send_message(text, text);
drop function if exists public.list_messages(text, integer);

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
set search_path = public
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
  values (p_group_id, auth.uid(), convert_to(trim(p_message_text), 'UTF8'))
  returning * into inserted;

  return query
  select
    inserted.id,
    inserted.group_id,
    inserted.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(inserted.body, 'UTF8') as message_text,
    inserted.sent_at,
    inserted.kind
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

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
set search_path = public
as $$
  select
    m.id,
    m.group_id,
    m.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(m.body, 'UTF8') as message_text,
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

grant execute on function public.send_message(text, text) to authenticated;
grant execute on function public.list_messages(text, integer) to authenticated;

-- ============================================================================
-- Direct/personal chat foundation (schema only — no RPCs, no UI wiring yet).
--
-- A DM is a conversation with exactly two participants. This is
-- deliberately a separate model from the family group's `group_id` string
-- column, because a DM's access control can't be "any active member" (that
-- would let anyone read anyone else's private chat) — it must be "one of
-- the two people in it". conversation_participants is what a future DM RPC
-- set will check against.
-- ============================================================================
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'direct' check (type in ('direct')),
  direct_pair_key text unique,
  created_at timestamptz not null default now()
);

comment on table public.conversations is
  'Foundation for Phase-2 direct/personal chats. Not yet wired to any RPC or UI — the family group continues to use messages.group_id.';

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  primary key (conversation_id, user_id)
);

create index if not exists conversation_participants_user_idx
  on public.conversation_participants (user_id);

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;

create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id and user_id = auth.uid()
  );
$$;

drop policy if exists conversations_select on public.conversations;
create policy conversations_select on public.conversations
  for select using (public.is_conversation_participant(id));

drop policy if exists conversation_participants_select on public.conversation_participants;
create policy conversation_participants_select on public.conversation_participants
  for select using (public.is_conversation_participant(conversation_id));

-- ============================================================================
-- Final set_own_display_name definition for this migration.
-- Now that the direct-chat tables exist, the first real-name save also creates
-- one direct conversation between the new member and every existing active
-- member. Existing rows are protected by direct_pair_key, so retrying the RPC
-- cannot create duplicates.
-- ============================================================================
create or replace function public.set_own_display_name(p_display_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  was_first_time boolean;
  clean_name text;
  other_member public.profiles;
  pair_key text;
  conversation_id uuid;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can set their name';
  end if;

  clean_name := trim(coalesce(p_display_name, ''));

  if length(clean_name) = 0 then
    raise exception 'Name cannot be empty';
  end if;

  if length(clean_name) > 60 then
    raise exception 'Name is too long';
  end if;

  select not name_confirmed into was_first_time
  from public.profiles
  where id = auth.uid();

  update public.profiles
  set display_name = clean_name, name_confirmed = true
  where id = auth.uid();

  if was_first_time then
    insert into public.messages (group_id, sender_id, body, kind)
    values (
      'family-group',
      auth.uid(),
      convert_to(clean_name || ' joined Vanam', 'UTF8'),
      'system'
    );

    for other_member in
      select *
      from public.profiles
      where id <> auth.uid() and status = 'active'
    loop
      pair_key := least(auth.uid()::text, other_member.id::text)
        || ':'
        || greatest(auth.uid()::text, other_member.id::text);

      insert into public.conversations (type, direct_pair_key)
      values ('direct', pair_key)
      on conflict (direct_pair_key) do update
        set direct_pair_key = excluded.direct_pair_key
      returning id into conversation_id;

      insert into public.conversation_participants (conversation_id, user_id)
      values
        (conversation_id, auth.uid()),
        (conversation_id, other_member.id)
      on conflict do nothing;
    end loop;
  end if;
end;
$$;

grant execute on function public.set_own_display_name(text) to authenticated;
