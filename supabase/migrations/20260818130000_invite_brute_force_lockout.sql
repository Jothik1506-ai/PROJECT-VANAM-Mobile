-- Close a real gap: redeem_invite() had no rate limiting. A PIN is only
-- 4-6 digits — without this, a single anonymous session (trivial to obtain,
-- even with CAPTCHA on sign-in) could loop-guess every PIN against a known
-- or overheard invite code before it expires or the real invitee redeems
-- it. Lock the invite after too many wrong PINs instead.

alter table public.invite_codes
  add column if not exists failed_attempts int not null default 0;

comment on column public.invite_codes.failed_attempts is
  'Wrong-PIN attempts against this code. Locked out (revoked) after too many — see redeem_invite().';

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
  max_attempts constant int := 5;
begin
  if auth.uid() is null then
    raise exception 'Must be signed in (even anonymously) to redeem an invite';
  end if;

  select * into invite
  from public.invite_codes
  where code = invite_code
  for update; -- lock the row: two simultaneous redemptions/guesses must not race

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
    -- Wrong PIN: count it, and lock the whole invite out permanently once
    -- the limit is hit — not just slow the caller down. A locked invite
    -- needs a fresh one from the admin; that's the correct outcome for
    -- something that looks like an attack, not an accident.
    update public.invite_codes
    set failed_attempts = failed_attempts + 1,
        revoked = (failed_attempts + 1) >= max_attempts
    where id = invite.id;

    if (invite.failed_attempts + 1) >= max_attempts then
      raise exception 'Too many incorrect attempts. This invite has been locked — ask your admin for a new one.';
    end if;
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
