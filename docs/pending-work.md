# Pending Work — Vanam Mobile

Tracks features discussed/planned but not yet built. Update as items are
started, finished, or re-scoped.

---

## Video Sharing (shipped 2026-09-12)

**Status:** Built and live. Home posts can attach one video (50MB/60s cap,
tap-to-play, no autoplay) via `family-video-media` (private bucket + signed
URLs, same pattern as photos). Kept below for the V2/V3 follow-ups that
weren't part of the V1 scope.

**Scope decision needed:** where does video go first?
- **Home posts** — a family member attaches a video clip alongside/instead
  of photos (recommended starting point — reuses the existing post
  composer, lowest-risk).
- **Stories** — a 24h video status update (WhatsApp-style), extending the
  existing 24h photo Stories feature.
- **Reels** — currently just replays Home post *photos* as a full-screen
  browsable feed, not real video. Extending this to true video reels is a
  separate, later piece of work.

Recommendation: **Home posts only for v1**, then extend to Stories once
proven with real family usage. Doing all three surfaces at once multiplies
risk (compression, playback, storage costs) before any of it has been
tested.

### Technical building blocks needed

1. **Video picking** — `image_picker`'s `pickVideo()` is already available
   (package already a dependency); no new package needed for this part.
2. **Playback** — no video playback exists in the app today. Need to add a
   `video_player` package dependency.
3. **Thumbnails** — a static preview image is needed for the feed (can't
   autoplay every video in a scrolling list). Either generate client-side
   at upload time (`video_thumbnail` package) or accept a blank/first-frame
   placeholder for v1.
4. **Storage schema** — extend `home_post_media`'s `media_type` check
   constraint to allow `'video'`; add `duration_seconds` and
   `thumbnail_path` columns. Recommend a **new private bucket**
   (`family-video-media`) rather than reusing `family-post-media`, so video
   gets its own size-limit policy independent of photos.
5. **Signed URLs** — the same private-bucket + signed-URL pattern already
   fixed for photos (see `docs/APP-ISSUES-AUDIT.md`) extends naturally.
   Supabase Storage signed URLs support HTTP range requests, which
   `video_player` needs for scrubbing/streaming playback.

### Real constraints to decide upfront

- **File size cap.** A raw phone video can be 100MB+ for a minute of 4K
  footage. Needs a hard cap (e.g. 60 seconds / 50MB) enforced client-side
  *before* upload starts, or storage costs and upload times balloon fast —
  especially given some family members are on slower/rural connections.
- **Compression.** Without client-side compression, whatever the phone's
  camera produced gets uploaded as-is. A `video_compress`-style package
  before upload is the "do it right" path but adds real complexity
  (processing time, codec compatibility across Android versions). v1 can
  reasonably skip this and just cap duration/size instead.
- **Autoplay behavior.** Muted autoplay-on-scroll-into-view
  (Instagram/Reels-style) needs visibility detection (`visibility_detector`
  package) and must respect the same lazy-loading discipline as the round-3
  Home feed fix — a video must not start downloading until its post
  actually scrolls into view, or the exact "everything loads at once" bug
  that was just fixed gets reintroduced for video.
- **Storage budget.** Supabase's free tier has a real storage ceiling;
  video eats it dramatically faster than photos. Worth deciding a rough
  budget/retention policy (does old video content ever get purged?) before
  this ships, not after the bucket fills up.

### Phased rollout

- **V1** — attach one video per Home post, capped duration/size,
  tap-to-play (not autoplay), no compression, first-frame or generic
  thumbnail.
- **V2** — thumbnails generated properly, autoplay-on-scroll (muted,
  tap-to-unmute), multiple videos per post.
- **V3** — client-side compression before upload, video Stories,
  storage/retention policy if usage grows.

**Next step:** confirm scope (Home posts, V1 first) with Jothik, then turn
this into an actual implementation plan with exact schema/migration
details.

---

## Restricted Members ("Ghost" role) — planning only, next version

**Status:** Scope discussed 2026-09-12 via three confirmed decisions below.
**Not started.** This is a real security/permissions feature (touches E2EE
key distribution and RLS), so it gets its own migration + review pass before
any code lands — do not fold it into an unrelated release.

**What it is** (do not confuse with `family_placeholders` —
`supabase/migrations/20260825090000_family_placeholders.sql` — that table is
for people who can't log in at all yet; this is the opposite: a **real
logged-in account** with a **restricted messaging permission**). Whether to
actually reuse `family_placeholders` as the promotion path into this role, or
add an independent flag on `profiles`, is still open — flagged below.

### Confirmed behavior

1. A restricted member has a normal account (real login, real E2EE device
   keys) — same as everyone else. Only their *messaging permissions* differ.
2. **Family group chat: read-only.** They can decrypt and see messages in
   `family-group` (needs the shared group key like any member — no crypto
   change there), but `send_message` must reject a send from this role.
   Enforced in `list_messages`/`send_message`'s RPC body (`supabase/schema.sql`
   + `20260818120000_initial_schema.sql`), not just hidden client-side — a
   restricted member's own device must not be able to call the RPC directly
   and post anyway.
3. **Direct messages: founder-only, and invisible to everyone else.** A
   restricted member can open exactly one DM — with Jothik (the founder) —
   and no other member can see, list, or start a conversation with them at
   all. This is stronger than "blocked from DMing" — they must not appear as
   a DM target in anyone else's member picker except the founder's.
   `list_direct_conversations()` (`20260819070000_direct_chat_messages.sql`)
   already returns only conversations the caller participates in, so the
   founder's own view is unaffected either way; the new rule is entirely
   about *other* members' member-picker/search results excluding restricted
   accounts, and about the direct-conversation-creation path (not yet
   located/named in this codebase — needs finding before implementation)
   refusing to open a DM between two non-founder members when either side is
   restricted.

### Still open (answer before implementation starts)

- **Where does the role live?** A new `profiles.member_tier` (or similar)
  enum column, vs. repurposing `family_placeholders.access_status`. The
  latter reuses existing admin UI/RLS scaffolding but conflates two
  different concepts (no-login placeholder vs. restricted real account) —
  leaning toward a new independent column unless there's a reason to merge
  them.
- **Who can promote/demote?** Presumably admin-only (`is_admin()`, already
  used throughout the schema), but confirm restricted status can be lifted
  later (e.g. a restricted member later becomes a full member) without
  losing their message history.
- **Group key exposure.** Since a restricted member can read the group with
  the same shared key as everyone else, revoking their access later means a
  **key rotation** (`key_sync_service.dart`'s `rotateScopeKey`) — same as any
  member removal. Confirm that's acceptable (it already is for normal
  removals, so likely fine, just noting it's not free).
- **UI surfaces to update:** member picker/search (wherever "start a new DM"
  currently lists members), the family member list itself (should the
  founder see who's restricted vs. full?), and the send box in the group
  chat screen (needs a "read-only" state, not just a hidden send button —
  same client-must-not-trust-itself principle as point 2 above).

**Next step:** locate the direct-conversation-creation RPC/flow (not
identified yet), decide the schema question above, then write the actual
migration + RLS policy diff before any Dart code changes.
