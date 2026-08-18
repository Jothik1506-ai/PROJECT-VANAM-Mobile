-- Strict Home post deletion flow:
-- 1. Client asks for authorized storage paths.
-- 2. Client deletes those Storage objects.
-- 3. Client calls delete_home_post() to delete database rows.
--
-- This avoids reporting success while photo files remain in Storage.

create or replace function public.get_home_post_delete_paths(p_post_id uuid)
returns table (storage_path text)
language sql
security definer
stable
set search_path = public
as $$
  select m.storage_path
  from public.home_posts p
  join public.home_post_media m on m.post_id = p.id
  where
    p.id = p_post_id
    and (public.is_admin() or p.author_id = auth.uid())
  order by m.position;
$$;

grant execute on function public.get_home_post_delete_paths(uuid) to authenticated;

create or replace function public.delete_home_post(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post public.home_posts;
begin
  select * into target_post
  from public.home_posts
  where id = p_post_id;

  if target_post.id is null then
    return;
  end if;

  if not (public.is_admin() or target_post.author_id = auth.uid()) then
    raise exception 'Only the post owner or an admin can delete this post';
  end if;

  delete from public.home_posts
  where id = p_post_id;
end;
$$;

grant execute on function public.delete_home_post(uuid) to authenticated;
