-- A reinstall or "clear app data" destroys the device-local E2EE private
-- key. The profile then receives a new public key, while old wraps remain
-- sealed to the lost key. Let a member discard only their own stale wrap so
-- another participant can reseal the unchanged conversation key for them.

drop policy if exists key_wraps_delete_self on public.key_wraps;
create policy key_wraps_delete_self on public.key_wraps
  for delete
  to authenticated
  using ((select auth.uid()) = member_id);

create or replace function public.delete_own_key_wrap(
  p_scope text,
  p_scope_id text
)
returns void
language sql
security invoker
set search_path = public
as $$
  delete from public.key_wraps
  where member_id = (select auth.uid())
    and scope = p_scope
    and scope_id = p_scope_id;
$$;

-- Unlike the original group-only helper, this checks both scope types and
-- verifies that the caller is entitled to the requested scope. It is
-- SECURITY DEFINER only because callers cannot select other members' wraps.
create or replace function public.scope_key_exists(
  p_scope text,
  p_scope_id text
)
returns boolean
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
begin
  if p_scope = 'group' then
    if p_scope_id <> 'family-group' or not public.is_active_member() then
      raise exception 'Not an active family member';
    end if;
  elsif p_scope = 'direct' then
    if not public.is_conversation_participant(p_scope_id::uuid) then
      raise exception 'Not a conversation participant';
    end if;
  else
    raise exception 'Unknown key scope';
  end if;

  return exists (
    select 1
    from public.key_wraps
    where scope = p_scope and scope_id = p_scope_id
  );
end;
$$;

revoke all on function public.delete_own_key_wrap(text, text) from public;
revoke all on function public.scope_key_exists(text, text) from public;
grant execute on function public.delete_own_key_wrap(text, text) to authenticated;
grant execute on function public.scope_key_exists(text, text) to authenticated;
