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
- Current version: `1.0.1+29` in `apps/mobile/pubspec.yaml` (released on Google Play, Oct 2026). Bump the build
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
