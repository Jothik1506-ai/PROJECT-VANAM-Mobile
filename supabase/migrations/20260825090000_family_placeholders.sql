-- Planned family members who do not have app login access yet.
--
-- Keep these separate from public.profiles. A profiles row represents a real
-- auth user with device keys and encrypted chat access; placeholder rows do
-- not participate in E2EE, direct conversations, messages, push tokens, or
-- session checks.
create table if not exists public.family_placeholders (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  relation_note text,
  access_status text not null default 'ghost'
    check (access_status in ('ghost', 'invited', 'promoted', 'archived')),
  promoted_profile_id uuid references public.profiles (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.family_placeholders is
  'Non-login family placeholders. They are safe to show in admin/work-manager views without making encrypted chats wait for missing member keys.';

create index if not exists family_placeholders_status_idx
  on public.family_placeholders (access_status);

alter table public.family_placeholders enable row level security;

drop policy if exists family_placeholders_select_active_members
  on public.family_placeholders;
create policy family_placeholders_select_active_members
  on public.family_placeholders
  for select
  to authenticated
  using (public.is_active_member());

drop policy if exists family_placeholders_admin_insert
  on public.family_placeholders;
create policy family_placeholders_admin_insert
  on public.family_placeholders
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists family_placeholders_admin_update
  on public.family_placeholders;
create policy family_placeholders_admin_update
  on public.family_placeholders
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists family_placeholders_admin_delete
  on public.family_placeholders;
create policy family_placeholders_admin_delete
  on public.family_placeholders
  for delete
  to authenticated
  using (public.is_admin());

create or replace function public.touch_family_placeholders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_family_placeholders_updated_at
  on public.family_placeholders;
create trigger touch_family_placeholders_updated_at
  before update on public.family_placeholders
  for each row
  execute function public.touch_family_placeholders_updated_at();

grant select on public.family_placeholders to authenticated;
grant insert, update, delete on public.family_placeholders to authenticated;
