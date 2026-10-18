# Vanam Mobile — project notes

## Theme
- The **default theme is the forest-green palette** (brand `#1F5D2E`, cream
  surface `#FAF6EC`), defined in `apps/mobile/lib/theme/tokens.dart`.
- The saffron-orange "festival" theme (brand `#E25822`) was a temporary
  seasonal variant and the Ganesh Chaturthi theme was removed. Do not
  reintroduce either as the default; seasonal themes are only added when the
  owner asks for one.
- Keep the whole UI on the green palette (notices, gradients, dark mode).

## Build & test (run from `apps/mobile`)
- `flutter pub get`
- `flutter analyze` must be clean before every release.
- `flutter test` must pass before every release.
- Release scripts (PowerShell, need `android/key.properties` and
  `WORK_MANAGER_ACTIVITY_SECRET`): `tool/release.ps1` builds the signed APK
  and manifest; `tool/play-release.ps1` builds the Play bundle.

## Releases
- Current version: `1.0.2+30` in `apps/mobile/pubspec.yaml` (1.0.1+29 is the one live on Google Play, Oct 2026). Bump the build
  number for every release; the OTA manifest lives in `vanam-ota-updates/` and must be updated
  with the new APK's URL and SHA-256 (see `docs/OTA-RELEASES.md`).
- Backend is Supabase (`supabase/migrations/`); apply new migrations before
  shipping a build that depends on them.
- `ARCHITECTURE.md` starts with a "Current state" section; keep it in sync
  when features land.

## Chat encryption
- Never auto-rotate a chat key on send; rotation deletes every member's key
  copy. Recovery is the explicit, confirmed "Reset" action in the chat screen.

## Chat attachments
- Files are encrypted on the phone with the chat key before upload (bucket
  `chat-attachments` only holds ciphertext). Never upload a plaintext file.
- The 20261015090000 migration must be applied before shipping a build that
  can send attachments. Builds older than the attachment release show an
  attachment message as raw `vanam:att:1:{...}` text.

## Chat history
- `list_messages` / `list_direct_messages` return the NEWEST page and take
  `p_before` for older pages (migration 20261015120000). Never go back to
  `order by sent_at asc ... limit N`: that silently hides new messages once a
  chat passes the limit.

## Pages and ids
- Every screen is registered in `apps/mobile/lib/navigation/app_page.dart`
  (`AppPage`): a unique, stable `id` (e.g. `tab.home`), a `label`, a kind and
  a description; the four tabs also have a `tabIndex`. Feedback, Crashlytics
  and the tab state keys all use it.
- Add new screens there first. Never rename or reuse an `id` (reports are
  matched on it). `test/app_page_test.dart` fails on duplicate ids or labels.
