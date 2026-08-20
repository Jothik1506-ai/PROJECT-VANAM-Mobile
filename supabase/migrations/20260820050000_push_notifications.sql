-- Android push notification plumbing.
--
-- Important E2EE boundary: this migration does not alter send_message,
-- list_messages, send_direct_message, list_direct_messages, key_wraps, or
-- auth/profile credential columns. Push events carry routing metadata only.

create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles (id) on delete cascade,
  fcm_token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web', 'other')),
  app_version text,
  last_registered_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists push_tokens_member_idx
  on public.push_tokens (member_id);

alter table public.push_tokens enable row level security;

drop policy if exists push_tokens_select_self on public.push_tokens;
create policy push_tokens_select_self on public.push_tokens
  for select using (member_id = auth.uid());

drop policy if exists push_tokens_insert_self on public.push_tokens;
create policy push_tokens_insert_self on public.push_tokens
  for insert with check (
    public.is_active_member()
    and member_id = auth.uid()
  );

drop policy if exists push_tokens_update_self on public.push_tokens;
create policy push_tokens_update_self on public.push_tokens
  for update using (member_id = auth.uid())
  with check (
    public.is_active_member()
    and member_id = auth.uid()
  );

drop policy if exists push_tokens_delete_self on public.push_tokens;
create policy push_tokens_delete_self on public.push_tokens
  for delete using (member_id = auth.uid());

create or replace function public.register_push_token(
  p_fcm_token text,
  p_platform text,
  p_app_version text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_token text := trim(coalesce(p_fcm_token, ''));
  clean_platform text := lower(trim(coalesce(p_platform, 'other')));
begin
  if not public.is_active_member() then
    raise exception 'Only active members can register push tokens';
  end if;

  if clean_token = '' then
    raise exception 'Push token cannot be empty';
  end if;

  if clean_platform not in ('android', 'ios', 'web', 'other') then
    clean_platform := 'other';
  end if;

  insert into public.push_tokens (
    member_id,
    fcm_token,
    platform,
    app_version,
    last_registered_at
  )
  values (
    auth.uid(),
    clean_token,
    clean_platform,
    nullif(trim(coalesce(p_app_version, '')), ''),
    now()
  )
  on conflict (fcm_token) do update
  set member_id = auth.uid(),
      platform = excluded.platform,
      app_version = excluded.app_version,
      last_registered_at = now();
end;
$$;

grant execute on function public.register_push_token(text, text, text)
  to authenticated;

-- Queue rows are for the Supabase Edge Function only. They deliberately do
-- not contain message body/ciphertext.
create table if not exists public.push_notification_events (
  id uuid primary key default gen_random_uuid(),
  source_table text not null check (source_table in ('messages', 'direct_messages')),
  source_id uuid not null,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  chat_type text not null check (chat_type in ('family', 'direct')),
  group_id text,
  conversation_id uuid,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists push_notification_events_unprocessed_idx
  on public.push_notification_events (created_at)
  where processed_at is null;

alter table public.push_notification_events enable row level security;

-- No client policies: only service-role/server code should read or mark these.

create or replace function public.enqueue_family_message_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.kind = 'system' then
    return new;
  end if;

  insert into public.push_notification_events (
    source_table,
    source_id,
    sender_id,
    chat_type,
    group_id
  )
  values (
    'messages',
    new.id,
    new.sender_id,
    'family',
    new.group_id
  );

  return new;
end;
$$;

drop trigger if exists messages_enqueue_push on public.messages;
create trigger messages_enqueue_push
  after insert on public.messages
  for each row execute function public.enqueue_family_message_push();

create or replace function public.enqueue_direct_message_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.push_notification_events (
    source_table,
    source_id,
    sender_id,
    chat_type,
    conversation_id
  )
  values (
    'direct_messages',
    new.id,
    new.sender_id,
    'direct',
    new.conversation_id
  );

  return new;
end;
$$;

drop trigger if exists direct_messages_enqueue_push on public.direct_messages;
create trigger direct_messages_enqueue_push
  after insert on public.direct_messages
  for each row execute function public.enqueue_direct_message_push();
