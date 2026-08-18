# VANAM Mobile — Android-First Family Chat: UI & Architecture Plan (V1)

Owner: Claude Code (architecture, acceptance criteria) → Codex (implementation, verification).
Companion repo: `PROJECT-VANAM/Vanam web` (public web platform, festivals/content).
This repo is standalone: private family app, not part of the public build.

**Revision note (2026-08-17):** Scope pulled back to an Android-only V1 chat
app. The earlier four-pillar plan (Home/Reels/Messages+Calling/Profile) is
**not** V1 — it's preserved in git history (see prior commit on this file)
as the eventual direction, but V1 ships text chat only. Reels, calling, and
a home feed are explicitly deferred (Section 9).

## Context
Family-only, admin-approved Android app. End-to-end encrypted text chat.
Bilingual Telugu/English. Calm, private, family-focused. Google Play Console
is already set up, so V1 targets a real internal-testing release, not just a
local build.

## Locked Decisions
| Area | Decision |
|---|---|
| Platform | **Flutter, Android-only for V1.** No iOS build, signing, or App Store work in V1 — Flutter is chosen so iOS can be added later without a rewrite, but nothing iOS-specific is built now. |
| Distribution | Google Play Console (already available). V1 ships to the **Internal Testing** track. |
| V1 scope | Admin-approved access, E2EE text chat, simple profile, basic chat UI. **No reels, no calling, no home feed** — see Section 9. |
| Groups | Single family group. No DMs, no multi-group. |
| Encryption | Signal Protocol pattern for text messages. Client generates keys; server never sees plaintext or private keys. |
| Access | Admin-issued invite code + one-time PIN. No open signup. |
| Admin console | Separate web app (`admin.vanam.aivafreelancia.in`), not in this mobile app. |
| Read receipts | None — intentionally excluded. |
| Storage | Cloud-backed, encrypted in transit and at rest. Private keys in Android Keystore only, never plain SQLite. |

## 1. Screen List (V1)
- Splash — auth check, redirect
- Login — invite code + PIN entry
- Chat List — single family group, unread badge
- Chat Detail — message thread, composer, reactions
- Media Viewer — inline/fullscreen photo (image attachments only, no video)
- Profile (self) — view/edit name, avatar, language preference
- Settings — language, notifications, privacy, logout

No bottom tab bar in V1 — one main screen (Chat List) doesn't need one.
Structure navigation so a tab bar can be added later (Section 9) without a
rewrite, but don't build it now.

## 2. Navigation Flow
```
Splash → [authenticated?] → Chat List
                          → Login → validate → derive keys → Profile setup → Chat List

Chat List → Chat Detail → Media Viewer
         → Profile icon → Profile (self) → Settings → Logout → Login
```

## 3. MVP Wireframe Notes

**Login screen (approved visual direction, 2026-08-17):** cream background,
circular logo mark centered near top, "Welcome to Vanam" headline (bold),
"Your family, always connected" subtext, forest-green (`#1f5d2e`) full-width
rounded button. This visual language is locked. **Fields differ from the
original mockup** — that version showed mobile+password, Google login, OTP
login, and Sign Up, which is an open-registration pattern and conflicts with
the locked admin-gated model. Actual V1 fields:

```
┌─────────────────────────────────┐
│                                 │
│         [Logo — vanam-logo]     │  (circular mark, traced from source PNG)
│                                 │
│      Welcome to Vanam           │  (bold headline)
│   Your family, always connected │  (subtext, muted)
│                                 │
│  [Invite Code Input]            │  (monospace/uppercase style)
│   placeholder: "Invite code"    │
│                                 │
│  [PIN Input]                    │  (masked, numeric)
│   placeholder: "PIN"            │
│                                 │
│  ┌─────────────────┐            │
│  │     Log In       │            │  (forest-green, full-width, rounded)
│  └─────────────────┘            │
│                                 │
│  "Need an invite?               │  (replaces "Sign Up" —
│   Contact your family admin."    │   no self-registration exists)
│                                 │
└─────────────────────────────────┘
```

No password field, no Google login, no OTP login, no Sign Up link — all
removed because there is no open-registration path in this app. "Forgot
password?" is also removed (no password exists); if a member loses their PIN
they contact the admin for a new invite.

**Other screens:**
- Header always shows a padlock icon — encryption is non-negotiable, always visible.
- Chat List shows exactly one group row.
- Composer is sticky bottom, auto-expanding text + attachment icon (image only).
- Profile: avatar, name (Te/En), language toggle — kept deliberately simple, no bio, no post grid (those come with the feed features in a later phase).
- Settings groups: Language, Notifications, Privacy & Safety, About, Logout.

## 3a. Brand Assets
- Source logo: `C:\Users\vanam\Downloads\VANAM Logo.png` (single continuous-
  stroke calligraphy reading వనం, deep forest green `#1f5d2e` on off-white,
  ~6 MB, 2816×1536 — too large to ship as-is).
- Codex must trace this to a clean SVG (`assets/brand/vanam-logo.svg`) before
  using it anywhere in the app — do not embed the raw PNG in login/splash.
- Required exports from the SVG source:
  - Android adaptive icon (foreground + background layers, all mipmap densities)
  - Splash screen asset (Android 12+ splash API)
  - In-app circular logo mark used on the Login screen (as shown above)
- Keep the traced SVG as the single source of truth; regenerate exports from it rather than hand-editing each density.

## 4. Components
Core: `MessageBubble`, `MessageList`, `MessageComposer`, `ReactionPicker`
Nav/structure: `Header`, `Splash`, single-group list
Forms: `TextInput`, `PINInput`, `LanguageToggle`
Auth: `LoginForm`, `SessionManager` (Android Keystore-backed key storage)
Profile: `ProfileHeader`, `EditProfileForm` (name, avatar, language only)
Utility: `MediaViewer` (image only), `Loading`, `Error/Toast`, `Badge`

**Not built in V1:** `ReelsPlayer`, `PostCard`, `FeedList`, `CreatePostSheet`,
`IncomingCallScreen`, `ActiveCallControls`, `ParticipantTile`,
`CallSignalingClient`. These belong to Phase 2/3 (Section 9).

Design tokens: forest green brand (`#1f5d2e`, shared with web platform), grey message bubbles, red for destructive actions, Noto Sans Telugu + system Latin font, 8px spacing grid.

## 5. Backend

**Revision (2026-08-18): Supabase, not Cloudflare-native.** The section
below superseded the original Cloudflare Workers + D1 + Durable Objects
design. Reasoning: invite-only members, profiles, and messages map cleanly
onto Postgres tables with Row Level Security; Realtime is available without
building Durable Object session-fan-out by hand; and it's simply faster to
build and verify for an MVP. Cloudflare isn't gone — it keeps the jobs it's
already doing well:

| Need | Provider |
|---|---|
| Auth, invite redemption, profiles, messages, realtime delivery | **Supabase** (Postgres + Auth + Realtime) |
| Web platform hosting | **Cloudflare Pages** (unchanged, separate repo) |
| OTA update manifest + APK hosting | **Cloudflare** (unchanged, see docs/OTA-RELEASES.md) |
| Media (avatars, later reels) | **Cloudflare R2** (deferred — not needed for V1 text chat) |
| Push notifications | **Firebase** (deferred to whenever push is scheduled — not V1) |

No VPS, no self-hosted server. Revisit Supabase only if it becomes
genuinely limiting — not by default drift.

**Not provisioned in V1:** Cloudflare Stream (reels), Cloudflare Calls
(calling), R2, Firebase. Add only when the phase that needs them is
scheduled — don't stand up infrastructure ahead of the feature that needs it.

### Auth model — invite code + PIN, not Supabase's default

Supabase Auth is built around email/phone/OAuth/anonymous sign-in. VANAM's
locked model has none of those — invite code + PIN only, no open signup
(Section 3a / 7). The chosen mapping, using only what a Postgres function can
do (no Edge Function required for V1):

1. Client calls `supabase.auth.signInAnonymously()` — gets a real
   `auth.uid()` and session with no email/phone attached to it.
2. Client calls the `redeem_invite(code, pin)` RPC (a `SECURITY DEFINER`
   Postgres function — see `supabase/schema.sql`), passing the invite code
   and PIN entered on the Login screen.
3. The function validates the invite (unexpired, unused, PIN hash matches),
   marks it consumed, and creates a `profiles` row with
   `id = auth.uid()` — permanently linking that anonymous session to a real
   family member.
4. Every other table's Row Level Security checks `auth.uid()` against an
   *existing, non-revoked* `profiles` row. An anonymous session that never
   redeemed an invite can read or write nothing.

This keeps the "admin-approved, no self-signup" property intact — an
anonymous Supabase session is worthless until a real invite is redeemed.

### Schema

See `supabase/schema.sql` for the actual DDL (`profiles`, `invite_codes`,
`messages`, RLS policies, `redeem_invite()`, `create_invite()`). Message
`body` is `bytea` — ciphertext only, matching Section 6; Supabase never
receives or stores plaintext.

Deferred, not in V1 schema: `devices` (multi-device support), `feedback`
(the existing Work Manager integration is a separate external system, not
Supabase-backed).

## 6. Encryption Model
Text messages only in V1 — keep this honest and simple:
- Client generates key pair locally on first login (Curve25519/Ed25519)
- Public key uploaded to server; private key stored in **Android Keystore**, never in plain SQLite, never leaves the device
- Message encrypted client-side before send; server (D1 + Durable Object) only ever stores/relays ciphertext
- Privacy screen states this plainly: "Messages: end-to-end encrypted." No claims about features that don't exist yet.

## 7. Onboarding & Access Approval
**Admin (web console, separate repo/project):**
1. Admin creates invite: name, optional email, role (Member only in V1)
2. System generates invite code + 6-digit one-time PIN, 7-day expiry
3. Admin shares code+PIN via WhatsApp/in-person
4. Admin can revoke unused invites

**Member (this app):**
1. Enter invite code + PIN → validated server-side
2. Confirm identity (name pre-filled from invite, editable)
3. App generates E2EE key pair locally; public key uploaded, private key stored in Android Keystore
4. Set profile: name, optional avatar, language preference
5. Chat List loads

Revocation: admin can revoke a member; existing message history stays visible to others; revoked user cannot re-login without a fresh invite.

## 8. Chat, Profile, Settings Requirements

**Chat:**
- Chronological order, date separators, sender initials avatar (forest green)
- Emoji reactions, relative timestamps (tap for exact)
- Optimistic send (greyed until ACK), retry on failure
- Offline queue: compose while offline, auto-send on reconnect
- Padlock/encryption indicator in header, always visible, cannot be disabled
- No read receipts, no typing indicator relayed to others
- Max ~500 chars/message; image attachment with preview (no video in V1)
- Respect system text-size settings; screen-reader reads sender + text + time

**Profile (self):**
- Edit name (Te/En), avatar, language preference
- No bio, no post history, no activity feed — those arrive with later phases

**Settings:**
- Language: Telugu and/or English, can select both simultaneously
- Notifications: new messages, mentions, mute group (independent toggles)
- Privacy & Safety: E2EE status (read-only, always on for messages), clear local cache, session info, data-deletion request
- About: version, privacy policy link, terms link
- Logout: confirmation prompt, clears all local keys and session

## 9. Deferred — Not V1

These are real, planned, and intentionally out of this build:

- **Phase 2 — Calling.** 1:1 first (direct WebRTC, naturally E2E), then group calls via a managed SFU (e.g. Cloudflare Calls — transport-encrypted, not E2E; that trade-off gets its own honest writeup when this phase is scheduled). Requires its own architecture pass, not assumed from this doc.
- **Phase 3 — Home Feed + Reels.** Chronological family photo/text feed, then short vertical family video (Cloudflare Stream for hosting/transcoding). Introduces the bottom tab bar (order: Reels / Messages / Home / Profile) that V1 deliberately skips.
- **iOS.** Flutter keeps this possible without a rewrite, but no iOS build, signing, TestFlight, or App Store work happens until explicitly scheduled.
- Push notifications, message search, DMs beyond the single group, call recording, algorithmic feed ranking.

Do not scaffold infrastructure (Cloudflare Stream, Calls, iOS signing) for these ahead of need.

## 10. Build Order (V1, Android-only)
1. **Repo scaffold** — Flutter project, Android build target only, Google Play Console app entry created, Internal Testing track configured.
2. **Auth foundation** — invite code + PIN login, local key generation, Android Keystore integration.
3. **Simple Profile** — set/edit name, avatar, language on first login.
4. **E2EE text chat** — Workers + D1 + Durable Object backend, MessageBubble/List/Composer UI, offline queue.
5. **Settings** — language, notifications, privacy, logout.
6. **Play Store release** — signed AAB, uploaded to Internal Testing track, verification gates (Section 11) evidenced.

Phase 2 (Calling) and Phase 3 (Home Feed + Reels) get their own architecture docs when scheduled — not designed speculatively now.

## 11. What Codex Implements

**A. Repo scaffolding**
- Flutter app in `apps/mobile/`, Android build config only (no iOS target files added)
- `packages/e2ee/` (message key handling)
- `packages/api-client/` (Workers REST client)
- `packages/realtime/` (Durable Object WebSocket client for chat)
- CI/CD: Android build pipeline, signing config, Play Console Internal Testing upload

**B. Backend** — per Section 5 endpoints and tables.

**C. Encryption** — per Section 6.

**D. Verification gates before handoff back to Claude for review**
- [ ] Builds and runs on Android emulator and a real Android device
- [ ] Invite code + PIN login works end-to-end
- [ ] Profile set/edit persists (name, avatar, language)
- [ ] One full message roundtrip: encrypt → send → fetch → decrypt
- [ ] Offline queue verified (compose offline, auto-send on reconnect)
- [ ] Plaintext message never observed on the wire or on the server (network audit)
- [ ] Language preference persists across restarts
- [ ] Logout clears local keys (inspect Android Keystore)
- [ ] Signed AAB uploaded to Google Play Console Internal Testing track and installable via the testing link

**E. Explicitly out of scope for V1**
Reels, calling (1:1 and group), home feed, iOS build/signing, push notifications, message search, DMs beyond the single group, read receipts, typing indicators, call recording.

## Acceptance Criteria (V1 Definition of Done)
1. Join via invite code + PIN; public key uploaded, private key stored securely in Android Keystore.
2. Simple profile set on first login (name, avatar, language) and editable after.
3. Messages render chronologically with reactions; bilingual UI works; true E2EE verified.
4. Offline queue and auto-send verified.
5. Settings persist; logout clears keys.
6. Single group only, calm forest-green + accent visual design.
7. Runs on Android 10+, respects system text size.
8. Signed build live on Google Play Console Internal Testing track, installable by real family testers.
9. Codex scaffolding complete, build pipeline verified, all Section 11D gates evidenced.

## Next Steps
1. Jothik confirms this Android-first V1 scope.
2. Codex scaffolds repo per Section 11, opens PR.
3. Claude reviews scaffolding against acceptance criteria before UI build begins.
4. Phase 2 (Calling) architecture gets its own pass once V1 is on Internal Testing and stable.
