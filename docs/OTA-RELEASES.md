# VANAM Mobile — OTA Updates & Release Process

**Context:** VANAM Mobile is distributed **outside the Google Play Store**
(the Play Console account is not ours). This has one large consequence:

> There is no Play Store auto-update. If the app cannot update itself, a
> family member's phone keeps running whatever build they first installed —
> forever, including through a security fix.

So self-updating is not a nice-to-have here. It is the distribution channel.

---

## 1. Approach: self-hosted APK + in-app updater

**Decision:** host signed APKs on Cloudflare R2, publish a small JSON
manifest, and have the app check that manifest and install newer builds.

Why this over the alternatives:

| Option | Verdict |
|---|---|
| **Self-hosted APK + in-app updater** | **Chosen.** Works for every kind of change — Dart, native, dependencies, permissions. Same Cloudflare stack the rest of VANAM already uses. No vendor cost, no third-party in the trust path of a private family app. |
| Shorebird (Flutter code push) | Rejected for V1. Patches Dart code only — cannot ship native/dependency changes, which this app *will* need (encryption libs now, WebRTC in Phase 2). Would still require the APK path as a fallback, so it adds a second mechanism rather than replacing one. Reconsider later purely as a fast-hotfix accelerator. |
| Firebase App Distribution | Rejected. Built for tester builds, not an ongoing consumer update channel; adds a Google dependency we just moved away from. |
| "Send a new APK on WhatsApp each time" | Rejected as the primary channel. Works exactly once, then decays — people ignore it, and you cannot push a security fix. Acceptable only as the *initial* install method. |

### Trust model, stated honestly
Outside the Play Store we lose Play's signature verification and malware
scanning. We replace them with:
1. **A stable release signing key** (Android enforces that updates are signed
   by the same key — this is the real integrity guarantee).
2. **SHA-256 checksum** of each APK published in the manifest and verified
   after download, before install.
3. **HTTPS-only** manifest and APK fetch.

That is meaningfully weaker than Play in one specific way: nobody is scanning
our builds. It is acceptable here because the audience is a closed family
group installing a build we produce ourselves.

---

## 2. The signing key — the single highest-risk item

**Android will only install an update signed with the same key as the
installed app.** There is no recovery path if the key is lost: every family
member must uninstall (destroying their locally-stored E2EE private keys and
message history) and reinstall from scratch.

Rules:
- Generate **one** release keystore. Use it for every build, forever.
- Back it up in **at least two** places that are not this laptop and not the
  git repo (e.g. a password manager attachment + an encrypted drive).
- `key.properties`, `*.jks`, and `*.keystore` are gitignored. Never commit them.
- Never ship a build signed with the debug key. Debug keys are generated
  per-machine and are not stable — a debug-signed build that reaches a real
  phone poisons that install permanently.

### One-time setup
```bash
keytool -genkey -v \
  -keystore vanam-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias vanam
```

Then create `android/key.properties` (gitignored):
```properties
storeFile=C:/path/outside/the/repo/vanam-release.jks
storePassword=<your password>
keyAlias=vanam
keyPassword=<your password>
```

`android/app/build.gradle.kts` reads this file and falls back to an explicit
build failure — not to the debug key — if it is missing for a release build.

---

## 3. Versioning

`pubspec.yaml`'s `version: 1.0.0+3` maps to:
- `1.0.0` → `versionName` — what humans see ("1.0.0")
- `3` → `versionCode` — what Android compares

**`versionCode` must increase on every released build.** Android refuses to
install a package whose `versionCode` is lower than or equal to the installed
one. The update check compares `versionCode`, never the display string.

---

## 4. The update manifest

A single JSON file served over HTTPS. The app fetches it on launch.

```json
{
  "latestVersionCode": 3,
  "latestVersionName": "1.0.0",
  "minSupportedVersionCode": 2,
  "apkUrl": "https://updates.vanam.aivafreelancia.in/vanam-1.0.0-3.apk",
  "sha256": "5f2e...c81a",
  "sizeBytes": 24117248,
  "releaseNotes": "Faster message loading and a fix for Telugu text wrapping.",
  "releaseNotesTe": "సందేశాలు వేగంగా లోడ్ అవుతాయి.",
  "publishedAt": "2026-08-17T18:00:00Z"
}
```

Field meanings:
- `latestVersionCode` — if greater than the installed code, an update exists.
- `minSupportedVersionCode` — **forced update threshold.** If the installed
  code is *below* this, the update is mandatory and cannot be dismissed. This
  is how a security fix gets pushed to an E2EE app. Use it sparingly.
- `sha256` — verified after download, before the install intent fires. A
  mismatch aborts the install.

---

## 5. Hosting

| Artifact | Where |
|---|---|
| `manifest.json` | Cloudflare Worker or Pages, at `updates.vanam.aivafreelancia.in/manifest.json` |
| `vanam-<name>-<code>.apk` | Cloudflare R2, public read, immutable per filename |

Keep every released APK — never overwrite a filename. If a build turns out
bad, you roll forward to a new `versionCode`; you cannot roll back an
already-installed app without an uninstall.

Set a short cache TTL (≤5 min) on `manifest.json` so a forced update actually
propagates. APKs are immutable, so they can cache for a year.

---

## 6. Release checklist

1. Bump `version:` in `pubspec.yaml` (increment the `+N` build number).
2. `flutter build apk --release` (or `--split-per-abi` for smaller downloads).
3. Verify it is **not** debug-signed:
   `keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk`
4. Compute the checksum: `sha256sum app-release.apk`
5. Upload the APK to R2 under a **new, versioned filename**.
6. Update `manifest.json` — `latestVersionCode`, `apkUrl`, `sha256`,
   `sizeBytes`, release notes.
7. Install over the *previous* release on a real device and confirm it
   updates in place (no uninstall prompt, app data preserved).
8. Only then set `minSupportedVersionCode` if the update must be forced.

Step 7 is the one that catches signing mistakes. Do not skip it.

---

## 7. First install (bootstrapping)

The in-app updater cannot deliver the *first* install. For that:
- Host a download page at `vanam.aivafreelancia.in/app` with the APK link and
  a short "how to allow install from your browser" walkthrough in Telugu and
  English — elders will hit Android's "unknown sources" prompt and need it.
- Share that page link over WhatsApp, not a raw APK file. Links stay current;
  forwarded APK files go stale and get re-shared for years.

---

## 8. Android requirements

- `INTERNET` permission — fetch manifest and APK.
- `REQUEST_INSTALL_PACKAGES` permission — trigger the package installer.
  This is a sensitive permission; it is required for self-updating and would
  need justification if this app were ever submitted to Play.
- A `FileProvider` — Android 7+ forbids passing `file://` URIs across apps,
  so the downloaded APK is handed over as a `content://` URI.
- The user still confirms each install at the OS level. There is no silent
  update path for a non-system app, and that is correct.

---

## 9. What is deliberately not built

- **Silent/background updates** — not possible for a normal app, and not
  desirable; the user should see what is being installed.
- **Automatic rollback** — not achievable without an uninstall. Mitigation is
  step 7 of the checklist: test the upgrade path before publishing.
- **Delta/patch updates** — full APK each time. At this app's size and this
  audience's size, the complexity is not worth the bandwidth saving.
