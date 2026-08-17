# VANAM Mobile — Family Test Group

Getting the app onto siblings' real phones, and knowing what their feedback
can and cannot tell us at each stage.

---

## 1. Read this first: what is actually testable today

The app currently has **no backend**. That means:

| Feature | Real or not |
|---|---|
| Login (invite code + PIN) | **Not real.** Any code and any 4-6 digit PIN is accepted. Nothing is verified. |
| Messages / conversation list | **Not real.** Hardcoded mock data (Amma, Nanna, Akka…). Identical on every phone. |
| Home feed posts | **Not real.** Hardcoded mock posts. |
| Profile name, counts | **Not real.** Placeholder values. |
| Reels, calling | **Not built.** Placeholder screens. |
| Dark mode, theme, layout | **Real.** |
| App install, icon, name | **Real.** |
| Telugu text rendering | **Real.** |
| OTA self-update | **Real** once the manifest is hosted. |

**Siblings cannot message each other yet.** If two of them open the app they
will see the same fake conversations, and nothing they type goes anywhere.
Say this to them up front — otherwise the first round of feedback is five
people reporting the same "my message didn't send" bug, which is not a bug.

This does not make an early test round useless. It makes it a **device and
distribution** test, which is genuinely valuable and is best done *before*
there is real data to lose.

---

## 2. Stage 1 test round — device & distribution (do this now)

**Goal:** find out whether the app installs and looks right on real phones
that are not the developer's emulator, and prove the update pipeline works
while the stakes are zero.

### What to ask siblings to check
1. **Install** — does the APK install at all? Which Android version and phone
   model? (Ask them; it matters.)
2. **App icon and name** — does it show as "Vanam" with the correct logo on
   the home screen and in the app drawer?
3. **Telugu text** — is any Telugu text rendered correctly, or are there
   tofu boxes (□□□) or broken conjuncts? **This is the highest-value check
   in stage 1** — Telugu rendering varies more across Android devices and
   manufacturer font packs than people expect, and a broken conjunct in a
   mantra later on is exactly the failure we cannot ship.
4. **Screen fit** — is anything cut off, overlapping, or scrolled off the
   edge? Ask for a screenshot rather than a description.
5. **Dark mode** — Profile → Dark Mode → System / Light / Dark. Does
   everything stay readable in all three?
6. **Speed** — does it feel slow to open or scroll? Note their phone model;
   an older budget phone is the more useful signal here.

### What NOT to ask them yet
Anything about messaging, login correctness, photos, calls, or reels. None of
it is real. Asking wastes their attention, and attention from family testers
is a limited resource — spend it on what the answers can actually change.

---

## 3. Stage 2 test round — the update pipeline

Do this once stage 1 has passed and the update manifest is hosted. It is the
single most important thing to rehearse before real data exists, because a
broken update path cannot be fixed remotely — it is the thing that fixes
everything else.

1. Everyone is on build N.
2. Publish build N+1 with a visible, obvious change (e.g. a different label
   somewhere) and a release note saying so.
3. Confirm each tester is prompted, and that installing keeps the app in
   place — **no uninstall prompt, no data reset**.
4. Then rehearse a *forced* update: publish N+2 with
   `minSupportedVersionCode` set to N+2 and confirm the prompt cannot be
   dismissed.

If step 3 shows an uninstall prompt, stop. That means a signing mismatch, and
it must be fixed before anyone stores anything real in the app.

---

## 4. Stage 3 — real feature testing

Only meaningful once the backend exists (Workers + D1 + Durable Objects, per
ARCHITECTURE.md section 5). At that point siblings become real test users
with real invite codes, and the checklist becomes:
- Does an invite code issued by the admin actually work, and does a wrong one
  actually fail?
- Do messages sent from one phone arrive on another?
- Do they arrive when the app was closed / the phone was offline and came back?
- Is anything readable in transit? (Verified by us, not them.)

---

## 5. Distributing the APK to testers

The in-app updater cannot deliver the *first* install. For that:

1. Build a signed release APK: `.\tool\release.ps1`
2. Upload it somewhere they can reach over HTTPS.
3. Share a **link to a download page**, not the APK file itself.

Share a link, not a file, because a forwarded APK gets re-shared for years
and goes stale, while a link always points at the current build. A stale APK
circulating in a family WhatsApp group is a real support problem later.

### What they will hit on first install
Android blocks installs from outside the Play Store by default. They will see
a warning and have to allow "install unknown apps" for their browser. This is
expected and unavoidable for non-Play distribution.

Write the walkthrough for this in **Telugu and English**, with screenshots.
Elders and less technical siblings will not get past the scary warning screen
without it, and "it wouldn't install" is the most likely reason a tester
silently drops out.

---

## 6. Collecting feedback

There is already a feedback button wired to Work Manager in the preview
shell. For non-technical testers, also accept plain WhatsApp messages and
screenshots — the goal is getting the report at all, not getting it in a
tidy format.

For each report worth acting on, record: phone model, Android version, what
they expected, what happened. Without the model and version, device-specific
rendering bugs are close to impossible to reproduce.
