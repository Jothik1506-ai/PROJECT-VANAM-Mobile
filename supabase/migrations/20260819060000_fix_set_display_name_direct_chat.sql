-- Fix set_own_display_name() so direct conversation creation does not rely on
-- ON CONFLICT against a partial unique index. Some live databases applied the
-- repair migration with a partial index, which cannot be targeted by
-- `on conflict (direct_pair_key)` and caused the name screen to fail.

create or replace function public.set_own_display_name(p_display_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  was_first_time boolean;
  clean_name text;
  other_member public.profiles;
  pair_key text;
  conversation_id uuid;
begin
  if not public.is_active_member() then
    raise exception 'Only active family members can set their name';
  end if;

  clean_name := trim(coalesce(p_display_name, ''));

  if length(clean_name) = 0 then
    raise exception 'Name cannot be empty';
  end if;

  if length(clean_name) > 60 then
    raise exception 'Name is too long';
  end if;

  select not name_confirmed into was_first_time
  from public.profiles
  where id = auth.uid();

  update public.profiles
  set display_name = clean_name, name_confirmed = true
  where id = auth.uid();

  if was_first_time then
    insert into public.messages (group_id, sender_id, body, kind)
    values (
      'family-group',
      auth.uid(),
      convert_to(clean_name || ' joined Vanam', 'UTF8'),
      'system'
    );

    for other_member in
      select *
      from public.profiles
      where id <> auth.uid() and status = 'active'
    loop
      pair_key := least(auth.uid()::text, other_member.id::text)
        || ':'
        || greatest(auth.uid()::text, other_member.id::text);

      select id into conversation_id
      from public.conversations
      where direct_pair_key = pair_key
      limit 1;

      if conversation_id is null then
        insert into public.conversations (type, direct_pair_key)
        values ('direct', pair_key)
        returning id into conversation_id;
      end if;

      insert into public.conversation_participants (conversation_id, user_id)
      values
        (conversation_id, auth.uid()),
        (conversation_id, other_member.id)
      on conflict do nothing;
    end loop;
  end if;
end;
$$;

grant execute on function public.set_own_display_name(text) to authenticated;
