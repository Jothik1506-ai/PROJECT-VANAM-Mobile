-- Chat history paging + richer chat list.
--
-- BUG FIX: list_messages / list_direct_messages ordered `sent_at asc` with a
-- limit, so once a chat passed 100 messages they returned the OLDEST 100
-- and newer messages never appeared. Both now select the NEWEST page and
-- accept p_before to fetch older pages ("load earlier messages").
--
-- Each page is still RETURNED oldest-first, exactly like before, so app
-- builds that predate this migration keep rendering in the right order (and
-- get the cap fix for free).
--
-- list_direct_conversations now returns the encrypted last message body
-- (so the phone can decrypt a real preview — "Photo", "sure, 6pm" — instead
-- of "New message") and an unread count for the badge. Nothing new is
-- readable by the server: the body is the same ciphertext the chat shows.

drop function if exists public.list_messages(text, integer);
create or replace function public.list_messages(
  p_group_id text default 'family-group',
  p_message_limit integer default 100,
  p_before timestamptz default null
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
  select t.id, t.group_id, t.sender_id, t.sender_name, t.message_text,
         t.sent_at, t.kind
  from (
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
      and (p_before is null or m.sent_at < p_before)
    order by m.sent_at desc
    limit greatest(1, least(p_message_limit, 500))
  ) t
  order by t.sent_at asc;
$$;

drop function if exists public.list_direct_messages(uuid, integer);
create or replace function public.list_direct_messages(
  p_conversation_id uuid,
  p_message_limit integer default 100,
  p_before timestamptz default null
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  message_text text,
  sent_at timestamptz,
  read_at timestamptz
)
language sql
security definer
stable
set search_path = public, extensions
as $$
  select t.id, t.conversation_id, t.sender_id, t.sender_name, t.message_text,
         t.sent_at, t.read_at
  from (
    select
      dm.id,
      dm.conversation_id,
      dm.sender_id,
      coalesce(p.display_name, 'Family Member') as sender_name,
      encode(dm.body, 'base64') as message_text,
      dm.sent_at,
      dm.read_at
    from public.direct_messages dm
    join public.profiles p on p.id = dm.sender_id
    where
      public.is_conversation_participant(p_conversation_id)
      and dm.conversation_id = p_conversation_id
      and (p_before is null or dm.sent_at < p_before)
    order by dm.sent_at desc
    limit greatest(1, least(p_message_limit, 500))
  ) t
  order by t.sent_at asc;
$$;

drop function if exists public.list_direct_conversations();
create or replace function public.list_direct_conversations()
returns table (
  conversation_id uuid,
  other_user_id uuid,
  other_display_name text,
  last_message_text text,
  last_message_at timestamptz,
  last_message_sender_id uuid,
  unread_count integer
)
language sql
security definer
stable
set search_path = public, extensions
as $$
  select
    c.id as conversation_id,
    other_p.id as other_user_id,
    other_p.display_name as other_display_name,
    encode(lm.body, 'base64') as last_message_text,
    lm.sent_at as last_message_at,
    lm.sender_id as last_message_sender_id,
    coalesce(unread.n, 0)::integer as unread_count
  from public.conversation_participants me
  join public.conversations c on c.id = me.conversation_id
  join public.conversation_participants other
    on other.conversation_id = c.id and other.user_id <> auth.uid()
  join public.profiles other_p on other_p.id = other.user_id
  left join lateral (
    select dm.body, dm.sent_at, dm.sender_id
    from public.direct_messages dm
    where dm.conversation_id = c.id
    order by dm.sent_at desc
    limit 1
  ) lm on true
  left join lateral (
    select count(*) as n
    from public.direct_messages dm
    where dm.conversation_id = c.id
      and dm.sender_id <> auth.uid()
      and dm.read_at is null
  ) unread on true
  where me.user_id = auth.uid() and public.is_active_member()
  order by coalesce(lm.sent_at, c.created_at) desc;
$$;

revoke all on function public.list_messages(text, integer, timestamptz) from public;
revoke all on function public.list_direct_messages(uuid, integer, timestamptz) from public;
revoke all on function public.list_direct_conversations() from public;
grant execute on function public.list_messages(text, integer, timestamptz) to authenticated;
grant execute on function public.list_direct_messages(uuid, integer, timestamptz) to authenticated;
grant execute on function public.list_direct_conversations() to authenticated;
