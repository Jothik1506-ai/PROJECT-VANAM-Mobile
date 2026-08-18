-- Allow a member to permanently delete their own Home posts.
-- Admins can also delete any Home post for family moderation.

drop policy if exists home_posts_delete on public.home_posts;
create policy home_posts_delete on public.home_posts
  for delete using (
    public.is_admin() or author_id = auth.uid()
  );

drop policy if exists home_post_media_delete on public.home_post_media;
create policy home_post_media_delete on public.home_post_media
  for delete using (
    public.is_admin()
    or exists (
      select 1
      from public.home_posts p
      where p.id = post_id and p.author_id = auth.uid()
    )
  );

drop policy if exists family_post_media_delete on storage.objects;
create policy family_post_media_delete on storage.objects
  for delete using (
    bucket_id = 'family-post-media'
    and (public.is_admin() or owner = auth.uid())
  );
