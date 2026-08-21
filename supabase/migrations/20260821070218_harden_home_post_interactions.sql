-- Home feed interaction RPCs are callable by signed-in family members only.
-- Postgres grants EXECUTE to PUBLIC by default for new functions, so lock
-- these down explicitly after creation/replacement.

revoke all on function public.toggle_home_post_like(uuid) from public;
revoke all on function public.add_home_post_comment(uuid, text) from public;
revoke all on function public.list_home_post_comments(uuid) from public;
revoke all on function public.list_home_posts(integer) from public;
revoke all on function public.toggle_home_post_like(uuid) from anon;
revoke all on function public.add_home_post_comment(uuid, text) from anon;
revoke all on function public.list_home_post_comments(uuid) from anon;
revoke all on function public.list_home_posts(integer) from anon;

grant execute on function public.toggle_home_post_like(uuid) to authenticated;
grant execute on function public.add_home_post_comment(uuid, text) to authenticated;
grant execute on function public.list_home_post_comments(uuid) to authenticated;
grant execute on function public.list_home_posts(integer) to authenticated;
