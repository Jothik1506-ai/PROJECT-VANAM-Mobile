-- Fix: redeem_invite() crashed with a raw Postgres error
-- ("duplicate key value violates unique constraint \"profiles_pkey\"")
-- instead of a friendly message whenever the current session already had
-- a profiles row — e.g. re-scanning an invite QR code, tapping Log In
-- twice, or the QR scanner's auto-submit racing a manual submit.
--
-- Fix: if this session (auth.uid()) already has a profile, just return it
-- — idempotent, not an error. A device's session is fixed to one member;
-- once it's redeemed anything, redeeming again (the same code, a stray
-- second scan, or even a different code by mistake) can only mean "this
-- device is already registered", never "let me become a different person".
create or replace function public.redeem_invite(
  invite_code text,
  invite_pin text
)
returns public.profiles
language plpgsql
security definer
as $$
declare
  invite public.invite_codes;
  new_profile public.profiles;
  existing_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in (even anonymously) to redeem an invite';
  end if;

  select * into existing_profile
  from public.profiles
  where id = auth.uid();

  if existing_profile.id is not null then
    return existing_profile;
  end if;

  select * into invite
  from public.invite_codes
  where code = invite_code
  for update; -- lock the row: two simultaneous redemptions of the same code must not both succeed

  if invite.id is null then
    raise exception 'Invalid invite code';
  end if;
  if invite.revoked then
    raise exception 'This invite has been revoked';
  end if;
  if invite.redeemed_by is not null then
    raise exception 'This invite has already been used';
  end if;
  if invite.expires_at < now() then
    raise exception 'This invite has expired';
  end if;
  if invite.pin_hash <> crypt(invite_pin, invite.pin_hash) then
    raise exception 'Incorrect PIN';
  end if;

  insert into public.profiles (id, display_name)
  values (auth.uid(), invite.invitee_name)
  returning * into new_profile;

  update public.invite_codes
  set redeemed_by = auth.uid(), redeemed_at = now()
  where id = invite.id;

  return new_profile;
end;
$$;

comment on function public.redeem_invite is
  'The only path from an anonymous session to a real profiles row. Idempotent: a session that already has a profile just gets it back. See ARCHITECTURE.md Section 5, auth model.';
