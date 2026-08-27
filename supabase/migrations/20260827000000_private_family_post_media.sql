-- Family photos were publicly downloadable: the family-post-media bucket
-- was created with public = true, which serves objects via a route that
-- bypasses storage.objects' RLS entirely — meaning anyone who obtained a
-- photo URL (screenshot, shared link, browser history, a proxy log, etc.)
-- could open it without being a Vanam member at all, regardless of the
-- (correctly-scoped) is_active_member() SELECT policy already in place.
--
-- Fix: make the bucket private. The existing SELECT policy on
-- storage.objects already requires is_active_member(), so signed URLs
-- (createSignedUrl, generated per-request from the app, short-lived) now
-- actually enforce that membership check instead of being bypassed by the
-- public flag. No policy changes needed — only the bucket's public flag.

update storage.buckets set public = false where id = 'family-post-media';
