# Vanam Mobile — project notes

## Theme
- The **default theme is the forest-green palette** (brand `#1F5D2E`, cream
  surface `#FAF6EC`), defined in `apps/mobile/lib/theme/tokens.dart`.
- The saffron-orange "festival" theme (brand `#E25822`) was a temporary
  seasonal variant and the Ganesh Chaturthi theme was removed. Do not
  reintroduce either as the default; seasonal themes are only added when the
  owner asks for one.
- Keep the whole UI on the green palette (notices, gradients, dark mode).

## Releases
- Current version: `1.0.0+28` in `apps/mobile/pubspec.yaml`. Bump the build
  number for every release; the OTA manifest lives in `vanam-ota-updates/`.

## Chat encryption
- Never auto-rotate a chat key on send; rotation deletes every member's key
  copy. Recovery is the explicit, confirmed "Reset" action in the chat screen.
