# VANAM Mobile: Ghost Users Plan

Status: PLAN ONLY. No code or database was changed while writing this.
Author: Claude Code (planning sub-agent), 2026-09-26.
Scope: `apps/mobile` (Flutter) + `supabase/` (migrations, functions). The
Vanam web repo (`../Vanam web`) is a static site with a privacy policy only.
It has no Supabase auth and no shared data model, so it is out of scope
except for the privacy/deletion wording in `privacy-policy.html`.

Everything below comes from the checked-in migrations. The live database can
differ (an earlier migration notes that `send_message` had drifted from
`schema.sql`). Before any phase ships, confirm each function against the live
DB with `select pg_get_functiondef('public.<fn>'::regproc);`.

---

## 0. How VANAM accounts actually work (the facts this plan relies on)

| Fact | Evidence |
|---|---|
| No open signup. Only an admin creates accounts, through `admin_create_member(display_name)`, which inserts into `auth.users` + `auth.identities` + `public.profiles` in one call. | `20260820020000_username_password_auth.sql`, `20260820040000_fix_auth_users_null_tokens.sql` |
| Login is a username/password pair. The email is a synthetic `vanam_<slug>@vanam.local`, so there is **no real email or phone**. Email nudges are impossible; push notifications are the only way to reach a member outside the app. | same |
| Every new or reset account gets the **same hard-coded default password `vanam_2026`**. `profiles.password_changed = false` until the member sets their own. | same, `admin_reset_member_password` |
| One-time recovery code: 8 hex chars, bcrypt-hashed in `profiles.recovery_code_hash`. `reset_password_with_recovery_code` is callable by `anon` and has no rate limit. | `20260820030000_e2ee_and_password_recovery.sql` |
| Onboarding flags on `profiles`: `password_changed` (set own password) and `name_confirmed` (set own display name). The first `set_own_display_name` call posts the "joined Vanam" system message, auto-creates a DM conversation with every other active member, and sends `app_notifications`. | `20260818160000_member_own_display_name.sql`, `20260819080000_in_app_notifications.sql` |
| Old flow: anonymous auth + `invite_codes` + `redeem_invite`. The rows are still there. Legacy members with `username IS NULL` show as `needsCredentials` in the admin screen. | `20260818120000_initial_schema.sql`, `apps/mobile/lib/invites/invite.dart` |
| `profiles.status` is `active` or `revoked`. Revoke is a plain `update profiles set status='revoked'`. It does **not** rotate keys, delete push tokens or remove DM participation. | `apps/mobile/lib/invites/invite_service.dart` (`revokeInvite`) |
| E2EE: the device X25519 public key lives in `profiles.public_key` (nullable). Per-scope symmetric keys are sealed per member in `key_wraps (scope, scope_id, member_id)`, one row per member per scope, with no key version. | `20260820030000_e2ee_and_password_recovery.sql`, `20260820123905_recover_reinstalled_device_keys.sql`, `20260821074722_recover_stuck_chat_keys.sql` |
| **`family_placeholders` already exists, with `access_status in ('ghost','invited','promoted','archived')`**, default `'ghost'`. No Dart code and no web code reads or writes it yet. | `20260825090000_family_placeholders.sql` (grep of `apps/mobile/lib` finds no references) |
| **A "Ghost role" (restricted member) is already specced but not built**: a real account that can only read the family group and can DM only the founder, and is invisible to everyone else. | `docs/pending-work.md`, section "Restricted Members ("Ghost" role)" |
| Activity tracking lives **outside Supabase**. The app posts `lastLoginAt` / `lastActiveAt` (throttled to every 5 min) / push / feedback timestamps to Work Manager (`/api/vanam/mobile/activity`). It is skipped entirely if the build has no `WORK_MANAGER_ACTIVITY_SECRET`. Work Manager's `list_vanam_mobile_activity` returned **0 rows** on 2026-09-26, so the pipeline is either not configured in the shipped builds or not receiving data. | `apps/mobile/lib/work_manager/work_manager_activity.dart`, `docs/WORK-MANAGER-ACTIVITY.md` |
| In-DB activity signals: `auth.users.last_sign_in_at`, `messages.sent_at` (`kind='user'`), `direct_messages.sent_at` / `read_at`, `home_posts`, `home_post_comments`, `home_post_likes`, `stories`, `story_views.viewed_at`, `app_notifications.read_at`, `push_tokens.last_registered_at`. | migrations listed above |
| There is no account deletion flow (no in-app "delete my account", no RPC) and no scheduled jobs (`pg_cron` is not used). The only cleanup so far is the manual one-off script `supabase/cleanup/20260819_remove_test_members.sql`. | grep |
| Hard-delete blockers: `messages.sender_id`, `direct_messages.sender_id` and `invite_codes.created_by/redeemed_by` reference `profiles(id)` with **no `on delete` action**, so deleting a member who has sent anything fails unless those rows are handled first (the cleanup script deletes them by hand). | initial schema, `20260819070000_direct_chat_messages.sql` |

---

## 1. What "ghost user" can mean here, ranked by how well it fits VANAM

| # | Meaning | Applies? | Why |
|---|---|---|---|
| G1 | **Restricted "Ghost role" member**: read-only in the group, DMs with the founder only, invisible to others | **Yes. Most likely what Jothik means.** | Already named "Ghost role" in `docs/pending-work.md` (decided 2026-09-12, not started) |
| G2 | **Placeholder family members** with no login (`family_placeholders.access_status='ghost'`), converted later through the invite-to-claim flow | **Yes. The table exists, the feature does not.** | `20260825090000_family_placeholders.sql` |
| G3 | **Never-activated / half-onboarded accounts**: created by an admin but the person never logged in, never changed `vanam_2026`, or never confirmed a name | **Yes. Also a security risk.** | `password_changed`, `name_confirmed` |
| G4 | **Orphan / broken accounts**: auth rows with no profile, profiles with no public key, stale key wraps, dead push tokens, revoked-but-not-cleaned members, expired invite codes | **Yes** | anonymous legacy flow, `key_wraps`, `push_tokens`, `invite_codes` |
| G5 | **Dormant members**: fully onboarded but inactive for N days | **Yes (low urgency at family scale)** | `last_sign_in_at` + content tables |
| G6 | Fake / spam / bot accounts | **Mostly no.** There is no public signup. The real risk is account takeover (default password, anon recovery brute force), not bots. | see section 7 |
| G7 | Privacy "ghost mode" (hide online status / last seen) | **Not today.** There is no presence or last-seen feature. The closest existing signals are DM read receipts (`direct_messages.read_at`) and story views (`story_views`). This only becomes relevant if those grow. | `ARCHITECTURE.md` lists no presence feature |

---

## 2. G1: Restricted "Ghost role" member (specced feature)

### 2.1 Design (answers the open items in `pending-work.md`)
- **Where the role lives:** add a new column,
  `profiles.member_tier text not null default 'full' check (member_tier in ('full','restricted'))`.
  Do not reuse `family_placeholders.access_status`, because a placeholder
  has no login and a restricted member does. A placeholder can still be
  promoted straight into a restricted account (see G2).
- **The DM creation path the spec could not find is `set_own_display_name`.** The version in `20260819080000_in_app_notifications.sql` loops over every active member and creates a `conversations` row plus `conversation_participants` rows on the member's first name confirmation. That loop must skip restricted members, except for the founder pair.
- **Founder identity:** add `profiles.is_founder boolean default false`, with a
  partial unique index so only one row can be true. Alternatively use
  `app_config(founder_id)`. Hard-coding a UUID is fragile.
- **Server-side enforcement (never client-only):**
  - `send_message`: `raise exception` when the caller's `member_tier='restricted'`.
  - `send_direct_message`: allowed only if the other participant is the founder.
  - `set_own_display_name`: when either side is restricted, create a DM only if the other side is the founder. Post the join system message only if Jothik wants restricted joins to be visible.
  - `list_direct_conversations`, member pickers and `profiles_select`: non-founder members must not see restricted profiles at all. This needs the `profiles_select` policy to become `is_active_member() and (member_tier='full' or id=auth.uid() or is_founder_caller())`. Check every RPC that joins `profiles` (they are `security definer` and bypass RLS). Examples: `list_messages` sender names, `list_home_posts` authors, `list_active_stories`.
  - `reset_key_wraps_for_scope('group', ...)`: block restricted callers. Today **any** active member can wipe the group key for everyone, which is a denial-of-service lever.
  - Home feed and stories: decide whether restricted members can post, comment, like or view stories. The spec does not say (question Q4).
- **E2EE:** a restricted member receives the group key wrap like everyone else, so they can read the group. Demoting or revoking them later needs a group key rotation (see 4.4 on key epochs).
- **Admin UI:** in `admin_invites_screen.dart`, add a tier chip and a Promote/Restrict action through an `admin_set_member_tier(member_id, tier)` RPC with an `is_admin()` check. Also show a read-only state on the group chat composer.

### 2.2 Effort
Migration + RPC rewrites + RLS: 1.5-2 days. Dart UI: 1 day. Two-device
test matrix (founder, full member, restricted member): 0.5-1 day.
**Total about 3-4 days**, plus a separate security review pass (the spec
itself says this needs one).

---

## 3. G2: Placeholder family members (`family_placeholders`)

### 3.1 Current state
The table and RLS exist. Active members can select; only admins can
insert, update or delete. No UI and no RPCs use it. The placeholder never
touches E2EE, DMs, push or sessions, which is correct.

### 3.2 Claim flow (design)
1. Admin adds a placeholder (name + relation note). It is shown greyed out
   in the family list as "Not on VANAM yet".
2. **Invite:** the admin taps "Send login" on a placeholder, which calls
   `admin_promote_placeholder(placeholder_id)` (security definer, `is_admin()`).
   That RPC calls the existing `admin_create_member` logic, sets
   `promoted_profile_id`, sets `access_status='invited'`, and returns
   username, password and recovery code for the existing QR screen.
3. **Claim:** when the new profile completes onboarding (`password_changed`
   and `name_confirmed` both true, detected inside `set_own_display_name`
   or `mark_own_password_changed`), set `access_status='promoted'`.
4. **Archive:** the admin archives placeholders for people who will never
   join (`access_status='archived'`).
5. Optional: "Invite to claim" with no admin involved (a member shares a
   claim link). **Not recommended.** It weakens the admin-approved-only
   model.

### 3.3 Cleanup policy
- An `invited` placeholder whose profile is still `password_changed=false`
  after 14 days goes on the admin list as "invite not claimed" (see G3).
- An `archived` placeholder is hard-deleted after 90 days. It holds only a
  name and a note, has no E2EE implications, and nothing else depends on it.
- `relation_note` is personal data about someone who never consented.
  Keep it minimal and delete it on request (section 8).

### 3.4 Detection SQL
```sql
-- Placeholder funnel
select access_status, count(*) from public.family_placeholders group by 1;

-- Invited but never claimed
select fp.id, fp.display_name, fp.updated_at, p.username, p.password_changed, p.name_confirmed
from public.family_placeholders fp
join public.profiles p on p.id = fp.promoted_profile_id
where fp.access_status = 'invited'
  and (p.password_changed = false or p.name_confirmed = false);

-- Broken links: promoted, but the profile was deleted (FK is ON DELETE SET NULL)
select id, display_name from public.family_placeholders
where access_status in ('invited','promoted') and promoted_profile_id is null;
```

### 3.5 Effort
RPC + status transitions: 0.5 day. Admin UI list and actions: 1 day.
Family-list rendering: 0.5 day. **About 2 days.**

---

## 4. G3 + G4: Never-activated, half-onboarded and orphan accounts

### 4.1 Detection SQL (run as the service role / in the SQL editor; read-only)
```sql
-- A. Never changed the default password: TAKEOVER RISK (anyone who knows or guesses
--    vanam_<name> can log in with vanam_2026)
select p.id, p.display_name, p.username, p.status, p.created_at, u.last_sign_in_at
from public.profiles p join auth.users u on u.id = p.id
where p.password_changed = false and p.status = 'active'
order by p.created_at;

-- A2. Stronger check: the stored hash still equals the default password
select u.id, p.username from auth.users u join public.profiles p on p.id = u.id
where u.encrypted_password = crypt('vanam_2026', u.encrypted_password);

-- B. Logged in but never confirmed their name (they never "joined": no join event, no DMs)
select id, display_name, username, created_at from public.profiles
where status = 'active' and name_confirmed = false;

-- C. Never signed in at all
select p.id, p.display_name, p.username, p.created_at
from public.profiles p join auth.users u on u.id = p.id
where u.last_sign_in_at is null;
-- note: admin_create_member stamps auth.identities.last_sign_in_at = now() at creation,
-- so use auth.users.last_sign_in_at, not identities.

-- D. Legacy members with no login credentials (old invite/PIN flow)
select id, display_name, created_at from public.profiles
where username is null and status = 'active';

-- E. Auth users with no profile (anonymous sessions from the old flow that never
--    redeemed an invite, or failed creations)
select u.id, u.created_at, u.is_anonymous, u.last_sign_in_at
from auth.users u left join public.profiles p on p.id = u.id
where p.id is null;
-- A profile without an auth user cannot exist (profiles.id FK ON DELETE CASCADE).

-- F. Active members with no E2EE public key (never opened chat on a device, or key upload failed)
select id, display_name, created_at from public.profiles
where status = 'active' and public_key is null;

-- G. Active members missing the group key wrap (stuck waiting for someone to reseal)
select p.id, p.display_name from public.profiles p
where p.status = 'active' and p.public_key is not null
  and not exists (select 1 from public.key_wraps k
                  where k.scope='group' and k.scope_id='family-group' and k.member_id=p.id);

-- H. Revoked members that still hold residue
select p.id, p.display_name,
  (select count(*) from public.key_wraps k where k.member_id=p.id)   as key_wraps,
  (select count(*) from public.push_tokens t where t.member_id=p.id) as push_tokens,
  (select count(*) from public.conversation_participants c where c.user_id=p.id) as dm_threads
from public.profiles p where p.status = 'revoked';

-- I. Stale push tokens
select member_id, platform, app_version, last_registered_at from public.push_tokens
where last_registered_at < now() - interval '60 days';

-- J. Dead legacy invite codes
select id, invitee_name, expires_at, failed_attempts from public.invite_codes
where redeemed_by is null and (revoked or expires_at < now());

-- K. Orphan storage objects (media whose DB row is gone)
select o.bucket_id, o.name, o.created_at from storage.objects o
where o.bucket_id = 'family-post-media'
  and not exists (select 1 from public.home_post_media m where m.storage_path = o.name)
union all
select o.bucket_id, o.name, o.created_at from storage.objects o
where o.bucket_id = 'family-story-media'
  and not exists (select 1 from public.stories s where s.storage_path = o.name);
```
Known gap: the server cannot tell whether an existing `key_wraps` row was
sealed to the member's current `public_key`, because the wrap does not
record which key it was sealed to. That is why the client has
`delete_own_key_wrap` recovery. Fix: add a `key_wraps.sealed_to_key_hash`
column (a sha256 of the public key) so stale wraps become queryable.

### 4.2 Actions
| Case | Action | Grace period |
|---|---|---|
| A (default password) | Security fix first (section 7). Show on the admin dashboard with a "Resend login QR" button that calls `admin_reset_member_password`, which also re-mints the recovery code. | Auto-**lock** (`status='revoked'`, reversible) if not claimed within 14 days. Never auto-delete. |
| B (name not confirmed) | The app already forces the name screen on next login. Show "joined but not finished" to the admin. | None needed |
| C (never signed in) | The admin asks the person directly (family scale). | Lock at 30 days. Offer to delete at 90 days, with admin confirmation. |
| D (legacy, no username) | The admin runs "Issue login" (exists). | Manual |
| E (auth user without profile) | These can do nothing (every RLS policy is gated on a profile). **Hard-delete** after 7 days through an admin-only cleanup function. | 7 days |
| F / G (key gaps) | Admin dashboard badge. G resolves itself when any keyed device opens the group chat. If it stays open for more than 7 days, show a "needs a keyed device to open chat" hint. | Informational |
| H (revoked residue) | On revoke: delete `push_tokens`, delete that member's `key_wraps`, **rotate the group key** (see 4.4). Keep DM threads read-only. | Immediately on revoke |
| I (stale push) | Delete tokens older than 90 days. FCM "unregistered" responses in `supabase/functions/push-notifications` should delete the token immediately. | 90 days |
| J (dead invites) | Hard-delete 30 days after expiry. `pin_hash` is credential material and there is no reason to keep it. | 30 days |
| K (orphan media) | Delete after 7 days (the gap covers in-flight uploads). | 7 days |

### 4.3 Soft-delete vs hard-delete
- **Soft (default):** `status='revoked'`. It is reversible, keeps message
  history intact, and RLS already blocks the member everywhere.
- **Anonymise (for erasure requests):** set `display_name='Former member'`,
  and null out `username`, `public_key` and `recovery_code_hash`. Delete
  `push_tokens`, `key_wraps`, `app_notifications`, `story_views`, stories,
  their posts and comments and media, and `auth.users` credentials (set the
  password to random, or delete the identity). Keep a tombstone profile row
  so other members' threads stay consistent.
- **Hard-delete:** deleting `auth.users` cascades to `profiles`, then to
  most child tables. First decide what happens to `messages` and
  `direct_messages`, since those FKs do not cascade. **Recommendation:**
  delete the leaving member's messages in 1:1 DMs, and keep group messages
  re-attributed to the tombstone. They are ciphertext the server cannot
  read anyway, but they are still the person's data. This choice is
  question Q6. Also fix the FKs with a migration to `on delete set null`
  (sender) or an explicit delete RPC. Do not rely on the manual script.

### 4.4 E2EE implications (important)
- `key_wraps` holds **one row per member per scope, with no version**. A
  true rotation (needed when anyone is revoked or demoted) replaces the
  scope key, so devices without a local cache lose old history. `reset_key_wraps_for_scope` already accepts this ("old ciphertext may remain unreadable").
- For clean revocation, add **key epochs**:
  `key_wraps.key_epoch int`, `messages.key_epoch int`, with unique key
  `(scope, scope_id, member_id, key_epoch)`. On revoke, an admin device
  generates epoch N+1 and seals it only for remaining members. Old epochs
  stay readable by the members who had them. The revoked member never gets
  N+1.
- Deleting a member's `key_wraps` does not remove what they already
  decrypted and cached on their device. State this honestly in the notice.

### 4.5 Effort
Detection views + admin dashboard read-out: 1-1.5 days. Revoke-cleanup RPC
(`admin_revoke_member`: status, push tokens, wraps, rotate trigger): 1 day.
Key epochs: 2-3 days plus a careful two-device test. Scheduled cleanup:
0.5-1 day.

---

## 5. G5: Dormant members

### 5.1 "Last seen anywhere" query
```sql
create or replace view admin_member_activity as   -- expose only via an is_admin() RPC, never directly
select p.id, p.display_name, p.username, p.role, p.status,  -- add p.member_tier once G1 ships
       p.created_at, u.last_sign_in_at,
       greatest(
         u.last_sign_in_at,
         (select max(sent_at)      from public.messages m        where m.sender_id = p.id and m.kind = 'user'),
         (select max(sent_at)      from public.direct_messages d where d.sender_id = p.id),
         (select max(created_at)   from public.home_posts h      where h.author_id = p.id),
         (select max(created_at)   from public.stories s         where s.author_id = p.id),
         (select max(viewed_at)    from public.story_views v     where v.viewer_id = p.id),
         (select max(read_at)      from public.app_notifications n where n.recipient_id = p.id),
         (select max(last_registered_at) from public.push_tokens t where t.member_id = p.id)
       ) as last_activity_at
from public.profiles p join auth.users u on u.id = p.id;
```
(`home_post_comments` and `home_post_likes` can be added once their author
column names are confirmed on the live DB.)

Caveat: `last_sign_in_at` moves only on a real sign-in. A persisted
session that just refreshes its token does not update it. That is why the
content signals and the Work Manager `lastActiveAt` value matter. Fix the
Work Manager pipeline (0 rows today) or add an in-DB `profiles.last_active_at`
touched by a throttled `touch_last_active()` RPC called from `app_shell.dart`
next to the existing `reportActive` call. **Recommendation: the in-DB
column**, because it does not depend on a build-time secret.

### 5.2 Buckets and actions (proposed defaults, question Q2)
| Bucket | Action |
|---|---|
| 14-29 days inactive | Nothing. Show as "quiet" on the dashboard. |
| 30-89 days | One push nudge ("Your family posted N updates"). Metadata only, never message content (E2EE boundary). At most one per 30 days. |
| 90-364 days | Admin sees "dormant". Optionally clean up push tokens. No data deletion. |
| 365+ days | Admin decides: keep, revoke (soft) or start erasure. Erasure needs the 48-hour notice flow (section 8) and admin confirmation. **Never automatic** for a family app. |

### 5.3 Metrics
Total members by status/tier. Onboarding funnel (created, signed in,
password changed, name confirmed, public key uploaded, group key wrap
received, first message). Weekly/monthly active members. Dormancy
buckets. Cohort by `created_at` month. Placeholder funnel (ghost,
invited, promoted).

---

## 6. Admin dashboard and reporting

Two surfaces already exist. Pick one or both (question Q7):
1. **In-app admin screen** (`admin_invites_screen.dart`): add filter chips
   (Pending password / Name not set / No key / Dormant / Revoked /
   Placeholders) plus per-row actions (Resend QR, Lock, Restrict, Promote
   placeholder, Start erasure).
2. **Work Manager "Vanam Mobile Activity" tab**: it already receives
   metadata. Add a nightly summary push from a Supabase Edge Function (counts
   only, no names beyond what the tab already shows) instead of relying on
   the device-sent secret.

Backend: a single `admin_ghost_report()` SECURITY DEFINER RPC that returns
the counts and lists from sections 3-5, with an `is_admin()` guard on the
first line and `revoke all ... from public, anon`. Do not expose the raw
views or `auth.users` to `authenticated`.

---

## 7. Security findings that turn "ghosts" into real risk (fix first)

1. **Shared default password `vanam_2026`** on every new or reset account. An unclaimed account can be taken over by anyone who knows the username pattern `vanam_<name>` (predictable from display names). Fix: generate a random per-account temp password (it is already returned only once to the admin QR screen, so the UX is unchanged), and auto-lock unclaimed accounts after 14 days.
2. **`recovery_code_hash` and `username` are readable by every active member.** `profiles_select` is `is_active_member()` on the whole row, and `listInvites()` does `select *`. An 8-hex-char code is about 32 bits, which is crackable offline from a bcrypt hash. Fix: move `recovery_code_hash` (and `pin_hash`-style secrets) to an admin/service-only table, or `revoke select (recovery_code_hash) on public.profiles from authenticated` and switch the client to explicit column lists.
3. **`reset_password_with_recovery_code` is granted to `anon` with no attempt limit.** Add a per-username failure counter and lockout (mirror `invite_brute_force_lockout`). Consider a longer code.
4. **`upload_key_wrap` is SECURITY DEFINER with no membership check** (as checked in, 20260820030000). Any authenticated caller, including a revoked one, can insert a wrap for any member or scope where none exists yet. Confirm on the live DB. Fix: require that the caller is entitled to the scope, and that the target is an active participant.
5. **`reset_key_wraps_for_scope` can be called by any active member** for the group. Restrict it to admins, or require a recent failed-decrypt state.
6. Revoke leaves push tokens, key wraps and DM participation behind (G4-H).
7. `supabase/cleanup/20260819_remove_test_members.sql` matches by display name. A family member named "jk" would be deleted. Replace it with id-based admin tooling.

Estimated effort for items 1-5: **1-1.5 days** (migration + small Dart change for item 2's column list), plus a test pass on login, reset and recovery.

---

## 8. DPDP Act 2023 obligations (India)

Assumption: VANAM (Jothik / the operator) is the **Data Fiduciary**. The
personal/domestic-purpose exemption (s.3(c)(ii)) covers the family members
themselves, not the operator of the app. The DPDP Rules 2025 were
notified in November 2025 with phased commencement (most obligations about
18 months later). **Confirm the exact dates with counsel.** Designing for
them now is cheap.

| Obligation | What it means for ghosts | Plan item |
|---|---|---|
| Notice + consent (s.5, s.6) | Members get accounts created *for* them by the admin. They need a notice screen with consent at first login (before or with the set-password screen). Placeholders (G2) never consented at all, so keep placeholder data minimal. | Consent screen + `profiles.consented_at`, `consent_version` |
| Erasure when the purpose is served or consent is withdrawn (s.8(7), s.12) | Dormant or never-activated accounts should not be kept indefinitely. Provide in-app "Delete my account" plus a path for placeholders (a request to the admin). | Anonymise/erase flow (4.3), retention table |
| Notice before erasure | The Rules require 48-hour prior notice before inactivity-based erasure for large platforms. VANAM is not in that class, but **adopt it anyway**: a push notice plus an in-app banner at least 48 hours before (recommended: 30 days before, then a 48-hour reminder). | Scheduled job with a `deletion_scheduled_at` column |
| Children (s.9) | A family app will likely include under-18s. That needs verifiable parental consent, and no tracking or targeted behavioural monitoring of children. The dormancy "nudges" must not profile children. | Q9: is any member under 18? `profiles.is_minor`, `guardian_id` |
| Grievance redressal (s.8(10), s.13) | Publish a contact. `privacy-policy.html` currently says "contact the admin through the app or the Work Manager feedback channel". Add a response SLA (the Rules suggest 90 days at most). | Privacy policy update |
| Security safeguards + breach notice (s.8(5), (6)) | Section 7 items are the safeguard gaps. A takeover of an unclaimed account would be a notifiable breach. | Section 7 |
| Log retention | The Rules require keeping processing logs for at least 1 year. Keep an `admin_audit_log` (who revoked, erased or reset whom, and when) even after the data is erased. | New table, admin-only |

Also: **Google Play policy** requires that apps with account creation
offer account deletion in the app **and** through a web link. VANAM has
neither. The Vanam web repo is the natural place for the web deletion
request page.

---

## 9. RLS and security principles for everything above
- All ghost reports and cleanup run through `SECURITY DEFINER` RPCs with
  `if not public.is_admin() then raise ...` as the first statement,
  `set search_path = public, pg_temp`, and `revoke all from public, anon`.
- Never grant `authenticated` read access to `auth.users` or to the activity
  view.
- Scheduled cleanup runs with the service role (`pg_cron` or a scheduled
  Edge Function) and **logs every deletion** to `admin_audit_log`.
- Every destructive job runs in two passes: report (dry run), then act
  after the grace period. Deletes use ids, never names.
- The E2EE boundary is unchanged. Nudges, reports and Work Manager
  payloads carry metadata only: no ciphertext, no keys, no recovery codes.

---

## 10. Phased implementation

| Phase | Contents | Effort |
|---|---|---|
| **Phase 1: Visibility + close the takeover holes** (recommended first) | Section 7 items 1-5. `admin_ghost_report()` RPC with queries A-K and the dormancy view (read-only). Admin screen filter chips. In-DB `profiles.last_active_at` with a throttled touch RPC. No deletion yet. | **3-4 days** |
| Phase 2: Revoke done right | `admin_revoke_member` (push tokens, wraps, audit log). Key epochs + rotation on revoke. Id-based cleanup RPC replacing the name-based script. Cleanup for E, I, J, K with grace periods (dry-run report first). | 4-5 days |
| Phase 3: Ghost role (G1) | Per section 2, plus a dedicated security review. | 3-4 days + review |
| Phase 4: Placeholders claim flow (G2) | Per section 3. | ~2 days |
| Phase 5: DPDP + Play compliance | Consent screen, in-app and web account deletion (anonymise path), 30-day/48-hour erasure notice job, privacy policy update, minor handling. | 3-4 days |
| Phase 6 (optional) | Dormancy push nudges. "Ghost mode" privacy toggles (hide DM read receipts / story views) if Jothik wants them. | 1-2 days |

The ordering assumes Jothik's intended meaning is not yet known. If he
confirms he meant G1 only, move Phase 3 up, but still do the Phase 1
security items first: a restricted member who can read `recovery_code_hash`
or call `reset_key_wraps_for_scope` defeats the restriction.

---

## 11. Assumptions (marked, to verify)
- A1: The live DB matches the checked-in migrations for `upload_key_wrap`, `profiles_select`, `set_own_display_name` and `reset_password_with_recovery_code`.
- A2: Anonymous sign-in may still be enabled in the Supabase project from the V1 flow. `config.toml` has no explicit setting. If it is on, disable it: nothing uses it any more, and it is the only way case-E orphans get created.
- A3: The family is small (tens of members), so "manual admin decision" is acceptable for anything destructive.
- A4: Work Manager activity is currently empty (0 rows on 2026-09-26). Either the release builds lack `WORK_MANAGER_ACTIVITY_SECRET`, or the endpoint is not storing data.
- A5: VANAM is the only Data Fiduciary. No third-party processor contracts were reviewed (Supabase, FCM, Render/Work Manager).

## 12. Questions for Jothik
1. **Which "ghost" do you mean?** The restricted "Ghost role" from `pending-work.md` (G1), placeholder family members with no login (G2), or cleaning up inactive and broken accounts (G3-G5)? Or all of them?
2. What inactivity threshold counts as "dormant": 30, 90 or 365 days?
3. Is **deleting** accounts or data ever allowed, or only locking (revoke)? If deletion is allowed: when someone leaves, do their group messages stay (as "Former member") or get deleted?
4. Restricted members: can they post, comment, like or view stories on the Home feed, or only read the group chat?
5. Should other members see that a restricted member exists at all (for example in the member count or join messages)?
6. When a member is revoked, is it acceptable that members without a local cache lose readable old history (a key rotation without epochs)? Or should we spend the extra 2-3 days on key epochs?
7. Where should ghost reports live: the in-app admin screen, the Work Manager tab, or both?
8. Can we replace the shared `vanam_2026` default password with random per-account passwords now? (No UX change: the QR screen already shows it once.)
9. Are any members under 18 (DPDP s.9 parental consent)?
10. Do you want push nudges to dormant members, and how often at most?
