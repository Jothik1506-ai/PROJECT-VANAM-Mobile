-- Chat history paging + richer chat list. ADDITIVE ONLY: safe to apply at
-- any time, before or after the app release that uses it.
--
-- BUG FIX: list_messages / list_direct_messages order `sent_at asc` with a
-- limit, so once a chat passes 100 messages they return the OLDEST 100 and
-- newer messages never appear. Installed apps (1.0.1+29 and earlier) call
-- those functions and expect ascending order, so they are left exactly as
-- they are. New apps call list_messages_page / list_direct_messages_page,
-- which return the NEWEST page (newest first) and accept p_before (+ p_before_id
-- as a tiebreaker for equal sent_at) to fetch older pages ("load earlier messages"). The app sorts each page itself.
--
-- list_direct_conversations keeps every existing column with its existing
-- meaning (last_message_text is still the plain 'New message' placeholder)
-- and gains three columns: last_message_body (the encrypted last message,
-- base64, so the phone can decrypt a real preview), last_message_sender_id
-- and unread_count. Nothing new is readable by the server: the body is the
-- same ciphertext the chat shows.

create or replace function public.list_messages_page(
  p_group_id text default 'family-group',
  p_message_limit integer default 100,
  p_before timestamptz default null,
  p_before_id uuid default null
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
    and (
      p_before is null
      or (p_before_id is null and m.sent_at < p_before)
      or (p_before_id is not null and (m.sent_at, m.id) < (p_before, p_before_id))
    )
  order by m.sent_at desc, m.id desc
  limit greatest(1, least(p_message_limit, 500));
$$;

create or replace function public.list_direct_messages_page(
  p_conversation_id uuid,
  p_message_limit integer default 100,
  p_before timestamptz default null,
  p_before_id uuid default null
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
    and (
      p_before is null
      or (p_before_id is null and dm.sent_at < p_before)
      or (p_before_id is not null and (dm.sent_at, dm.id) < (p_before, p_before_id))
    )
  order by dm.sent_at desc, dm.id desc
  limit greatest(1, least(p_message_limit, 500));
$$;

-- The return type gains columns, so the function must be dropped and
-- recreated; the existing columns keep their names, order and meanings.
drop function if exists public.list_direct_conversations();
create or replace function public.list_direct_conversations()
returns table (
  conversation_id uuid,
  other_user_id uuid,
  other_display_name text,
  last_message_text text,
  last_message_at timestamptz,
  last_message_body text,
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
    case when lm.sent_at is not null then 'New message' else null end as last_message_text,
    lm.sent_at as last_message_at,
    encode(lm.body, 'base64') as last_message_body,
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

revoke all on function public.list_messages_page(text, integer, timestamptz, uuid) from public, anon;
revoke all on function public.list_direct_messages_page(uuid, integer, timestamptz, uuid) from public, anon;
revoke all on function public.list_direct_conversations() from public, anon;
grant execute on function public.list_messages_page(text, integer, timestamptz, uuid) to authenticated;
grant execute on function public.list_direct_messages_page(uuid, integer, timestamptz, uuid) to authenticated;
grant execute on function public.list_direct_conversations() to authenticated;
