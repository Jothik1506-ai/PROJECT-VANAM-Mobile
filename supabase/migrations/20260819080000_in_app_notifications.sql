-- In-app notifications for active family members.
-- First use: notify existing members when a new member joins Vanam.

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete cascade,
  type text not null default 'general',
  title text not null,
  body text not null,
  related_group_id text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists app_notifications_recipient_created_idx
  on public.app_notifications (recipient_id, created_at desc);

create index if not exists app_notifications_unread_idx
  on public.app_notifications (recipient_id)
  where read_at is null;

alter table public.app_notifications enable row level security;

drop policy if exists app_notifications_select_self on public.app_notifications;
create policy app_notifications_select_self on public.app_notifications
  for select using (
    public.is_active_member() and recipient_id = auth.uid()
  );

drop policy if exists app_notifications_update_self on public.app_notifications;
create policy app_notifications_update_self on public.app_notifications
  for update using (
    public.is_active_member() and recipient_id = auth.uid()
  )
  with check (
    public.is_active_member() and recipient_id = auth.uid()
  );

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

      select id into conversation_id
      from public.conversations
      where direct_pair_key = pair_key
      limit 1;

      if conversation_id is null then
        insert into public.conversations (type, direct_pair_key)
        values ('direct', pair_key)
        returning id into conversation_id;
      end if;

      insert into public.conversation_participants (conversation_id, user_id)
      values
        (conversation_id, auth.uid()),
        (conversation_id, other_member.id)
      on conflict do nothing;

      insert into public.app_notifications (
        recipient_id,
        actor_id,
        type,
        title,
        body,
        related_group_id
      )
      values (
        other_member.id,
        auth.uid(),
        'member_joined',
        'New family member',
        clean_name || ' joined Vanam',
        'family-group'
      );
    end loop;
  end if;
end;
$$;

grant execute on function public.set_own_display_name(text) to authenticated;
