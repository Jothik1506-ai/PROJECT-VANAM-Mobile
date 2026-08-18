-- Home feed interactions: likes and comments, scoped to active family members.

create table if not exists public.home_post_likes (
  post_id uuid not null references public.home_posts (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, member_id)
);

create table if not exists public.home_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.home_posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists home_post_comments_post_created_idx
  on public.home_post_comments (post_id, created_at);

alter table public.home_post_likes enable row level security;
alter table public.home_post_comments enable row level security;

drop policy if exists home_post_likes_select on public.home_post_likes;
create policy home_post_likes_select on public.home_post_likes
  for select using (public.is_active_member());

drop policy if exists home_post_likes_insert on public.home_post_likes;
create policy home_post_likes_insert on public.home_post_likes
  for insert with check (
    public.is_active_member() and member_id = auth.uid()
  );

drop policy if exists home_post_likes_delete on public.home_post_likes;
create policy home_post_likes_delete on public.home_post_likes
  for delete using (
    public.is_active_member() and member_id = auth.uid()
  );

drop policy if exists home_post_comments_select on public.home_post_comments;
create policy home_post_comments_select on public.home_post_comments
  for select using (public.is_active_member());

drop policy if exists home_post_comments_insert on public.home_post_comments;
create policy home_post_comments_insert on public.home_post_comments
  for insert with check (
    public.is_active_member() and author_id = auth.uid()
  );

create or replace function public.toggle_home_post_like(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can like posts';
  end if;

  if exists (
    select 1 from public.home_post_likes
    where post_id = p_post_id and member_id = auth.uid()
  ) then
    delete from public.home_post_likes
    where post_id = p_post_id and member_id = auth.uid();
  else
    insert into public.home_post_likes (post_id, member_id)
    values (p_post_id, auth.uid());
  end if;
end;
$$;

create or replace function public.add_home_post_comment(
  p_post_id uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can comment';
  end if;

  if length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'Comment cannot be empty';
  end if;

  insert into public.home_post_comments (post_id, author_id, body)
  values (p_post_id, auth.uid(), trim(p_body));
end;
$$;

create or replace function public.list_home_post_comments(p_post_id uuid)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  body text,
  created_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    c.id,
    c.author_id,
    coalesce(p.display_name, 'Family Member') as author_name,
    c.body,
    c.created_at
  from public.home_post_comments c
  join public.profiles p on p.id = c.author_id
  where public.is_active_member() and c.post_id = p_post_id
  order by c.created_at asc;
$$;

create or replace function public.list_home_posts(p_limit integer default 50)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  caption text,
  like_count int,
  comment_count int,
  created_at timestamptz,
  media_paths text[],
  liked_by_me boolean
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
      where mine.post_id = p.id and mine.member_id = auth.uid()
    ) as liked_by_me
  from public.home_posts p
  join public.profiles profile on profile.id = p.author_id
  left join public.home_post_media m on m.post_id = p.id
  where public.is_active_member()
  group by p.id, profile.display_name
  order by p.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

grant execute on function public.toggle_home_post_like(uuid) to authenticated;
grant execute on function public.add_home_post_comment(uuid, text) to authenticated;
grant execute on function public.list_home_post_comments(uuid) to authenticated;
grant execute on function public.list_home_posts(integer) to authenticated;
