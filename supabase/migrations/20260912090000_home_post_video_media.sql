-- Migration: 20260912090000_home_post_video_media.sql
-- Enables video sharing on Home posts:
-- 1. Creates a private storage bucket 'family-video-media' (public = false from creation).
-- 2. Sets RLS policies on storage.objects for 'family-video-media'.
-- 3. Extends home_post_media's media_type check constraint to allow 'video'.
-- 4. Adds duration_seconds and thumbnail_path columns.
-- 5. Updates list_home_posts() to return media_items jsonb with bucket, media_type, duration.
-- 6. Updates get_home_post_delete_paths() to return storage_bucket and storage_path.

-- 1. Create the private bucket for video media
insert into storage.buckets (id, name, public)
values ('family-video-media', 'family-video-media', false)
on conflict (id) do update set public = excluded.public;

-- 2. Storage policies for family-video-media
drop policy if exists family_video_media_select on storage.objects;
create policy family_video_media_select on storage.objects
  for select using (
    bucket_id = 'family-video-media' and public.is_active_member()
  );

drop policy if exists family_video_media_insert on storage.objects;
create policy family_video_media_insert on storage.objects
  for insert with check (
    bucket_id = 'family-video-media'
    and public.is_active_member()
    and owner = auth.uid()
  );

drop policy if exists family_video_media_delete on storage.objects;
create policy family_video_media_delete on storage.objects
  for delete using (
    bucket_id = 'family-video-media' and owner = auth.uid()
  );

-- 3. Extend check constraint on public.home_post_media
alter table public.home_post_media
  drop constraint if exists home_post_media_media_type_check;

alter table public.home_post_media
  add constraint home_post_media_media_type_check
  check (media_type in ('photo', 'video'));

-- 4. Add duration_seconds and thumbnail_path columns
alter table public.home_post_media
  add column if not exists duration_seconds integer,
  add column if not exists thumbnail_path text;

-- 5. Update list_home_posts to return media_items jsonb
drop function if exists public.list_home_posts(integer);

create function public.list_home_posts(p_limit integer default 50)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  caption text,
  like_count int,
  comment_count int,
  created_at timestamptz,
  media_paths text[],
  liked_by_me boolean,
  media_items jsonb
)
language sql
security definer
stable
set search_path = public
as $$
  select
    p.id,
    p.author_id,
    coalesce(profile.display_name, 'Family Member') as author_name,
    p.caption,
    (
      select count(*)::int
      from public.home_post_likes l
      where l.post_id = p.id
    ) as like_count,
    (
      select count(*)::int
      from public.home_post_comments c
      where c.post_id = p.id
    ) as comment_count,
    p.created_at,
    coalesce(
      array_agg(m.storage_path order by m.position)
        filter (where m.storage_path is not null),
      '{}'::text[]
    ) as media_paths,
    exists (
      select 1 from public.home_post_likes mine
      where mine.post_id = p.id and mine.member_id = (select auth.uid())
    ) as liked_by_me,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'storage_bucket', m.storage_bucket,
          'storage_path', m.storage_path,
          'media_type', m.media_type,
          'duration_seconds', m.duration_seconds,
          'thumbnail_path', m.thumbnail_path,
          'position', m.position
        ) order by m.position
      ) filter (where m.storage_path is not null),
      '[]'::jsonb
    ) as media_items
  from public.home_posts p
  join public.profiles profile on profile.id = p.author_id
  left join public.home_post_media m on m.post_id = p.id
  where public.is_active_member()
  group by p.id, profile.display_name
  order by p.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

revoke all on function public.list_home_posts(integer) from public;
revoke all on function public.list_home_posts(integer) from anon;
grant execute on function public.list_home_posts(integer) to authenticated;

-- 6. Update get_home_post_delete_paths to return storage_bucket and storage_path
drop function if exists public.get_home_post_delete_paths(uuid);

create function public.get_home_post_delete_paths(p_post_id uuid)
returns table (storage_bucket text, storage_path text)
language sql
security definer
stable
set search_path = public
as $$
  select m.storage_bucket, m.storage_path
  from public.home_posts p
  join public.home_post_media m on m.post_id = p.id
  where
    p.id = p_post_id
    and (public.is_admin() or p.author_id = auth.uid())
  order by m.position;
$$;

grant execute on function public.get_home_post_delete_paths(uuid) to authenticated;

