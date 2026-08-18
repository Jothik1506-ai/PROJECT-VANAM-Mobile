-- App-facing chat RPCs.
--
-- The messages table keeps body as bytea because V1 will move to real E2EE.
-- Until that encryption layer exists, the app sends temporary UTF-8 text
-- through these functions. Replacing convert_to/convert_from with ciphertext
-- handling later should not require changing the Flutter chat UI.

create or replace function public.send_message(
  message_text text,
  message_group_id text default 'family-group'
)
returns table (
  id uuid,
  group_id text,
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
  inserted public.messages;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can send messages';
  end if;

  if length(trim(coalesce(message_text, ''))) = 0 then
    raise exception 'Message cannot be empty';
  end if;

  insert into public.messages (group_id, sender_id, body)
  values (message_group_id, auth.uid(), convert_to(trim(message_text), 'UTF8'))
  returning * into inserted;

  return query
  select
    inserted.id,
    inserted.group_id,
    inserted.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(inserted.body, 'UTF8') as message_text,
    inserted.sent_at
  from public.profiles p
  where p.id = inserted.sender_id;
end;
$$;

create or replace function public.list_messages(
  message_group_id text default 'family-group',
  message_limit integer default 100
)
returns table (
  id uuid,
  group_id text,
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
    m.id,
    m.group_id,
    m.sender_id,
    coalesce(p.display_name, 'Family Member') as sender_name,
    convert_from(m.body, 'UTF8') as message_text,
    m.sent_at
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where
    public.is_active_member()
    and m.group_id = message_group_id
  order by m.sent_at asc
  limit greatest(1, least(message_limit, 500));
$$;

grant execute on function public.send_message(text, text) to authenticated;
grant execute on function public.list_messages(text, integer) to authenticated;
