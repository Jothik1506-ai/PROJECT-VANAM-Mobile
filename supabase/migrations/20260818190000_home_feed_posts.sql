-- VANAM Home feed: family-only post metadata plus photo media paths.
-- Apply in Supabase before testing Home posting from the app.

insert into storage.buckets (id, name, public)
values ('family-post-media', 'family-post-media', true)
on conflict (id) do update set public = excluded.public;

create table if not exists public.home_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  caption text not null default '',
  like_count int not null default 0,
  comment_count int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.home_post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.home_posts (id) on delete cascade,
  storage_bucket text not null default 'family-post-media',
  storage_path text not null,
  media_type text not null default 'photo' check (media_type in ('photo')),
  position int not null default 0,
  created_at timestamptz not null default now(),
  unique (storage_bucket, storage_path)
);

create index if not exists home_posts_created_idx
  on public.home_posts (created_at desc);

create index if not exists home_post_media_post_position_idx
  on public.home_post_media (post_id, position);

alter table public.home_posts enable row level security;
alter table public.home_post_media enable row level security;

drop policy if exists home_posts_select on public.home_posts;
create policy home_posts_select on public.home_posts
  for select using (public.is_active_member());

drop policy if exists home_posts_insert on public.home_posts;
create policy home_posts_insert on public.home_posts
  for insert with check (
    public.is_active_member() and author_id = auth.uid()
  );

drop policy if exists home_post_media_select on public.home_post_media;
create policy home_post_media_select on public.home_post_media
  for select using (public.is_active_member());

drop policy if exists home_post_media_insert on public.home_post_media;
create policy home_post_media_insert on public.home_post_media
  for insert with check (
    public.is_active_member()
    and exists (
      select 1
      from public.home_posts p
      where p.id = post_id and p.author_id = auth.uid()
    )
  );

drop policy if exists family_post_media_select on storage.objects;
create policy family_post_media_select on storage.objects
  for select using (
    bucket_id = 'family-post-media' and public.is_active_member()
  );

drop policy if exists family_post_media_insert on storage.objects;
create policy family_post_media_insert on storage.objects
  for insert with check (
    bucket_id = 'family-post-media'
    and public.is_active_member()
    and owner = auth.uid()
  );

create or replace function public.set_home_post_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can post';
  end if;
  new.author_id := auth.uid();
  return new;
end;
$$;

drop trigger if exists set_home_post_author_trigger on public.home_posts;
create trigger set_home_post_author_trigger
before insert on public.home_posts
for each row execute function public.set_home_post_author();

create or replace function public.list_home_posts(p_limit integer default 50)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  caption text,
  like_count int,
  comment_count int,
  created_at timestamptz,
  media_paths text[]
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
    p.like_count,
    p.comment_count,
    p.created_at,
    coalesce(
      array_agg(m.storage_path order by m.position)
        filter (where m.storage_path is not null),
      '{}'::text[]
    ) as media_paths
  from public.home_posts p
  join public.profiles profile on profile.id = p.author_id
  left join public.home_post_media m on m.post_id = p.id
  where public.is_active_member()
  group by p.id, profile.display_name
  order by p.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

grant execute on function public.list_home_posts(integer) to authenticated;
