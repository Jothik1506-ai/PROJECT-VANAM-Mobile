-- Authoritative Home post deletion RPC.
-- Deletes the database post in one server-side operation and returns storage
-- paths so the client can remove uploaded files best-effort afterward.

create or replace function public.delete_home_post(p_post_id uuid)
returns table (storage_path text)
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

  return query
  select m.storage_path
  from public.home_post_media m
  where m.post_id = p_post_id
  order by m.position;

  delete from public.home_posts
  where id = p_post_id;
end;
$$;

grant execute on function public.delete_home_post(uuid) to authenticated;
