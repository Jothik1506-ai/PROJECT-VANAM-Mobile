-- Repair migration for direct/personal chat foundation.
-- Safe to run after a partial/older join migration. It ensures the
-- conversations table, direct_pair_key column, participant table, policies,
-- and first-name-save join flow all match the current app expectation.

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'direct' check (type in ('direct')),
  created_at timestamptz not null default now()
);

alter table public.conversations
  add column if not exists direct_pair_key text;

create unique index if not exists conversations_direct_pair_key_idx
  on public.conversations (direct_pair_key)
  where direct_pair_key is not null;

create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  primary key (conversation_id, user_id)
);

create index if not exists conversation_participants_user_idx
  on public.conversation_participants (user_id);

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;

create or replace function public.is_conversation_participant(
  p_conversation_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = auth.uid()
  );
$$;

drop policy if exists conversations_select on public.conversations;
create policy conversations_select on public.conversations
  for select using (public.is_conversation_participant(id));

drop policy if exists conversation_participants_select
  on public.conversation_participants;
create policy conversation_participants_select
  on public.conversation_participants
  for select using (public.is_conversation_participant(conversation_id));

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
