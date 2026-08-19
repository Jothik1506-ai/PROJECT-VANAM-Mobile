-- One-time cleanup for early VANAM test accounts.
--
-- Run this manually in Supabase SQL Editor before publishing the next fresh
-- family build. It targets exact display names only; review the preview query
-- result first. Deleting auth.users cascades into profiles, direct chat
-- participants/messages, notifications, and other FK-owned rows.

-- 1) Preview exactly what will be removed.
with test_names(display_name) as (
  values
    ('Jyotik'),
    ('jyotek'),
    ('jyotek 9'),
    ('ajo tech testing')
)
select
  p.id,
  p.display_name,
  p.role,
  p.status,
  p.created_at
from public.profiles p
join test_names t on lower(trim(p.display_name)) = lower(trim(t.display_name))
order by p.created_at;

-- 2) Delete the exact test users.
-- If the preview above shows any real family member, stop and remove that name
-- from the values list before running this block.
with test_names(display_name) as (
  values
    ('Jyotik'),
    ('jyotek'),
    ('jyotek 9'),
    ('ajo tech testing')
),
target_users as (
  select p.id
  from public.profiles p
  join test_names t on lower(trim(p.display_name)) = lower(trim(t.display_name))
)
delete from auth.users u
using target_users t
where u.id = t.id;

-- 3) Show remaining active members.
select id, display_name, role, status, created_at
from public.profiles
where status = 'active'
order by created_at;
