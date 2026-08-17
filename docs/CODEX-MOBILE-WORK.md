# Codex Mobile Work Note

Codex owns turning the Vanam mobile app from UI preview screens into working app behavior.

Current state:
- Most UI screens are present.
- Some screens are still preview-only or placeholder-backed.
- Features are not fully connected end-to-end yet.
- Claude Code is handling OTA/update and release mechanics.

Codex responsibility:
- Connect navigation and screen flows so the app works as one product.
- Make chat functionality work end-to-end, not only as UI.
- Make profile settings work and persist correctly.
- Make feedback submit to Work Manager with sender and screen context.
- Make Reels, Calls, Home, Messages, and Profile either work properly or show honest blocked/coming-soon states until their backend is ready.
- Add tests and verification for every working feature before handoff.

Feature expectations:
- Chat should send, receive, render, and persist messages correctly.
- Calls should not look active until signaling/media support exists.
- Reels should not look active until upload/playback support exists.
- Profile should save real user settings instead of only mock data.
- Feedback should identify who sent it and from which screen.

Family test users:
- Add siblings/family members as test users when auth/member management is ready.
- Use those test users to verify whether chat, calls, reels, profile, feedback, and navigation actually work from real family-member accounts.
- Each test user should have a clear name so feedback and bugs can be traced back to the person who saw the issue.

Coordination:
- Claude Code owns OTA/release setup.
- Codex owns working feature behavior, UI integration, tests, and verification.
- Do not mix OTA/release changes with feature commits unless explicitly requested.
