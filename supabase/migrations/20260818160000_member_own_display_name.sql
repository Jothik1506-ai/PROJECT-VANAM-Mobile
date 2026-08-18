-- Lets a member set their own display name after redeeming an invite,
-- instead of being permanently stuck with whatever name the admin typed
-- into the invite dialog. Relation labels (Amma/Nanna/Akka...) are
-- viewer-relative, not a fact about the person, so V1 never assigns a name
-- on someone else's behalf — the person picks their own name once, here.

alter table public.profiles
  add column if not exists name_confirmed boolean not null default false;

-- Existing rows (created before this migration) already have a real name
-- in place (either self-chosen already or acceptable as-is) — don't force
-- them through the new prompt.
update public.profiles set name_confirmed = true where name_confirmed = false;

create or replace function public.set_own_display_name(p_display_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can set their name';
  end if;

  if length(trim(coalesce(p_display_name, ''))) = 0 then
    raise exception 'Name cannot be empty';
  end if;

  if length(trim(p_display_name)) > 60 then
    raise exception 'Name is too long';
  end if;

  update public.profiles
  set display_name = trim(p_display_name), name_confirmed = true
  where id = auth.uid();
end;
$$;

grant execute on function public.set_own_display_name(text) to authenticated;
