-- WhatsApp-style read receipts for direct messages (single check = sent,
-- double blue check = read). Scoped to direct messages only — a
-- per-message "who in the family group has read this" receipt is a much
-- bigger feature (N-way, not two-way) and isn't part of this pass.

alter table public.direct_messages
  add column if not exists read_at timestamptz;

create or replace function public.mark_direct_messages_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'Not a participant in this conversation';
  end if;

  update public.direct_messages
  set read_at = now()
  where conversation_id = p_conversation_id
    and sender_id <> auth.uid()
    and read_at is null;
end;
$$;

grant execute on function public.mark_direct_messages_read(uuid) to authenticated;

-- list_direct_messages now also returns read_at so the sender's device can
-- render ticks. Matches the live signature (p_-prefixed params) — see
-- 20260820030000_e2ee_and_password_recovery.sql's comment on checking
-- pg_get_functiondef before assuming schema.sql/older migrations reflect
-- what's actually deployed.
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
  order by dm.sent_at asc
  limit greatest(1, least(p_message_limit, 500));
$$;

grant execute on function public.list_direct_messages(uuid, integer) to authenticated;

-- send_direct_message's return shape must match (adds read_at, always null
-- for a message that was just created).
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
  sent_at timestamptz,
  read_at timestamptz
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
    inserted.sent_at,
    inserted.read_at
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

grant execute on function public.send_direct_message(uuid, text) to authenticated;
