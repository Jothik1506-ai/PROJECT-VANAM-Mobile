-- Emergency recovery for a chat scope whose symmetric key is lost on all
-- currently-used devices. This rotates only the chat key wraps, not messages
-- or profiles. Old ciphertext may remain unreadable, but new messages can
-- resume immediately.

create or replace function public.reset_key_wraps_for_scope(
  p_scope text,
  p_scope_id text
)
returns void
language plpgsql
security definer
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

  delete from public.key_wraps
  where scope = p_scope and scope_id = p_scope_id;
end;
$$;

revoke all on function public.reset_key_wraps_for_scope(text, text) from public;
revoke all on function public.reset_key_wraps_for_scope(text, text) from anon;
grant execute on function public.reset_key_wraps_for_scope(text, text) to authenticated;
