-- VANAM Stories: WhatsApp-style 24-hour photo status updates.
-- Bucket is private from the start (family-post-media learned that
-- lesson the hard way — see 20260827000000_private_family_post_media.sql)
-- so signed URLs, not public ones, are the only way media is ever served.

insert into storage.buckets (id, name, public)
values ('family-story-media', 'family-story-media', false)
on conflict (id) do update set public = excluded.public;

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  storage_bucket text not null default 'family-story-media',
  storage_path text not null,
  media_type text not null default 'photo' check (media_type in ('photo')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);

create table if not exists public.story_views (
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create index if not exists stories_author_created_idx
  on public.stories (author_id, created_at desc);

create index if not exists stories_expires_idx
  on public.stories (expires_at);

alter table public.stories enable row level security;
alter table public.story_views enable row level security;

drop policy if exists stories_select on public.stories;
create policy stories_select on public.stories
  for select using (public.is_active_member() and expires_at > now());

drop policy if exists stories_insert on public.stories;
create policy stories_insert on public.stories
  for insert with check (
    public.is_active_member() and author_id = auth.uid()
  );

drop policy if exists stories_delete on public.stories;
create policy stories_delete on public.stories
  for delete using (author_id = auth.uid());

drop policy if exists story_views_select on public.story_views;
create policy story_views_select on public.story_views
  for select using (public.is_active_member());

drop policy if exists story_views_insert on public.story_views;
create policy story_views_insert on public.story_views
  for insert with check (
    public.is_active_member() and viewer_id = auth.uid()
  );

drop policy if exists family_story_media_select on storage.objects;
create policy family_story_media_select on storage.objects
  for select using (
    bucket_id = 'family-story-media' and public.is_active_member()
  );

drop policy if exists family_story_media_insert on storage.objects;
create policy family_story_media_insert on storage.objects
  for insert with check (
    bucket_id = 'family-story-media'
    and public.is_active_member()
    and owner = auth.uid()
  );

drop policy if exists family_story_media_delete on storage.objects;
create policy family_story_media_delete on storage.objects
  for delete using (
    bucket_id = 'family-story-media' and owner = auth.uid()
  );

create or replace function public.create_story(p_storage_path text)
returns table (id uuid, created_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.stories;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can post a story';
  end if;

  insert into public.stories (author_id, storage_path)
  values (auth.uid(), p_storage_path)
  returning * into v_row;

  return query select v_row.id, v_row.created_at, v_row.expires_at;
end;
$$;

grant execute on function public.create_story(text) to authenticated;

-- One row per still-active story, newest first within each author, plus
-- whether the caller has already viewed it. The app groups these by
-- author_id into one "story ring" per person, same as WhatsApp Status.
create or replace function public.list_active_stories()
returns table (
  story_id uuid,
  author_id uuid,
  author_name text,
  storage_path text,
  created_at timestamptz,
  expires_at timestamptz,
  viewed_by_me boolean
)
language sql
security definer
stable
set search_path = public
as $$
  select
    s.id,
    s.author_id,
    coalesce(profile.display_name, 'Family Member'),
    s.storage_path,
    s.created_at,
    s.expires_at,
    exists (
      select 1 from public.story_views v
      where v.story_id = s.id and v.viewer_id = auth.uid()
    )
  from public.stories s
  join public.profiles profile on profile.id = s.author_id
  where public.is_active_member() and s.expires_at > now()
  order by s.author_id, s.created_at asc;
$$;

grant execute on function public.list_active_stories() to authenticated;

create or replace function public.mark_story_viewed(p_story_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_member() then return; end if;

  insert into public.story_views (story_id, viewer_id)
  values (p_story_id, auth.uid())
  on conflict (story_id, viewer_id) do nothing;
end;
$$;

grant execute on function public.mark_story_viewed(uuid) to authenticated;

create or replace function public.delete_own_story(p_story_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.stories
  where id = p_story_id and author_id = auth.uid();
end;
$$;

grant execute on function public.delete_own_story(uuid) to authenticated;

-- The storage_path a story pointed at, so the caller can remove the file
-- from Storage after (or before) deleting the row — same pattern as
-- get_home_post_delete_paths.
create or replace function public.get_own_story_storage_path(p_story_id uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select storage_path from public.stories
  where id = p_story_id and author_id = auth.uid();
$$;

grant execute on function public.get_own_story_storage_path(uuid) to authenticated;
