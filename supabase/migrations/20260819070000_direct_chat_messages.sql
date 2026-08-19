-- Direct/personal chat messages + RPCs.
--
-- Deliberately a separate table from `messages`, not a shared table keyed
-- by group_id: messages_select's RLS is "any active member can read"
-- (correct for the one family group), which would leak every DM to the
-- whole family if reused here. A direct chat's access rule is instead
-- "only the two participants", enforced via is_conversation_participant()
-- against conversation_participants (see 20260819040000/50000/60000).

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id),
  body bytea not null,
  sent_at timestamptz not null default now()
);

comment on table public.direct_messages is
  'Ciphertext only, same discipline as messages (see 20260818120000). One row per DM. Access is per-conversation-participant, not "any active member".';

create index if not exists direct_messages_conversation_sent_idx
  on public.direct_messages (conversation_id, sent_at);

alter table public.direct_messages enable row level security;

drop policy if exists direct_messages_select on public.direct_messages;
create policy direct_messages_select on public.direct_messages
  for select using (public.is_conversation_participant(conversation_id));

drop policy if exists direct_messages_insert on public.direct_messages;
create policy direct_messages_insert on public.direct_messages
  for insert with check (
    public.is_conversation_participant(conversation_id)
    and sender_id = auth.uid()
  );

-- Realtime must be turned on explicitly per table (learned the hard way on
-- `messages` in 20260818170000 — RLS alone does not enable postgres_changes
-- broadcast). The guard keeps this safe if pasted twice in Supabase SQL Editor.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_messages'
  ) then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
end $$;

-- ============================================================================
-- list_direct_conversations(): every DM conversation.uid() participates in,
-- with the other participant's real name and a preview of the last message.
-- SECURITY DEFINER, so it must filter to auth.uid()'s own rows itself
-- (RLS on conversation_participants would otherwise be bypassed).
-- ============================================================================
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
    lm.message_text,
    lm.sent_at as last_message_at
  from public.conversation_participants me
  join public.conversations c on c.id = me.conversation_id
  join public.conversation_participants other
    on other.conversation_id = c.id and other.user_id <> auth.uid()
  join public.profiles other_p on other_p.id = other.user_id
  left join lateral (
    select convert_from(dm.body, 'UTF8') as message_text, dm.sent_at
    from public.direct_messages dm
    where dm.conversation_id = c.id
    order by dm.sent_at desc
    limit 1
  ) lm on true
  where me.user_id = auth.uid() and public.is_active_member()
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

-- ============================================================================
-- list_direct_messages(conversation_id, limit)
-- ============================================================================
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
set search_path = public
as $$
  select
    dm.id,
    dm.conversation_id,
    dm.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(dm.body, 'UTF8') as message_text,
    dm.sent_at
  from public.direct_messages dm
  join public.profiles p on p.id = dm.sender_id
  where
    public.is_conversation_participant(p_conversation_id)
    and dm.conversation_id = p_conversation_id
  order by dm.sent_at asc
  limit greatest(1, least(p_message_limit, 500));
$$;

-- ============================================================================
-- send_direct_message(conversation_id, text)
-- ============================================================================
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
set search_path = public
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
    convert_to(trim(p_message_text), 'UTF8')
  )
  returning * into inserted;

  return query
  select
    inserted.id,
    inserted.conversation_id,
    inserted.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(inserted.body, 'UTF8') as message_text,
    inserted.sent_at
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

grant execute on function public.list_direct_conversations() to authenticated;
grant execute on function public.list_direct_messages(uuid, integer) to authenticated;
grant execute on function public.send_direct_message(uuid, text) to authenticated;

-- ============================================================================
-- Backfill: create direct conversations for pairs of currently-active
-- members that predate the join-flow auto-creation logic (which only runs
-- for the *new* member's own first-name-save — two members who both
-- already had name_confirmed = true before that feature shipped would
-- otherwise never get a DM conversation). Idempotent — safe to re-run.
-- ============================================================================
do $$
declare
  a public.profiles;
  b public.profiles;
  pair_key text;
  conv_id uuid;
begin
  for a in select * from public.profiles where status = 'active' loop
    for b in select * from public.profiles where status = 'active' and id > a.id loop
      pair_key := least(a.id::text, b.id::text) || ':' || greatest(a.id::text, b.id::text);

      select id into conv_id from public.conversations where direct_pair_key = pair_key limit 1;

      if conv_id is null then
        insert into public.conversations (type, direct_pair_key)
        values ('direct', pair_key)
        returning id into conv_id;
      end if;

      insert into public.conversation_participants (conversation_id, user_id)
      values (conv_id, a.id), (conv_id, b.id)
      on conflict do nothing;
    end loop;
  end loop;
end $$;
