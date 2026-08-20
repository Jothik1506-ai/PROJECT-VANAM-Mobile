# VANAM OTA Updates

Deploy this folder to Cloudflare Pages and attach:

```text
updates.vanam.aivafreelancia.in
```

Required public files on Cloudflare:

```text
manifest.json
_headers
```

The APK is hosted as a GitHub Release asset because Cloudflare's manual
static uploader has a 25 MB per-file limit. The GitHub tag must match the
manifest URL, for example `v1.0.0-13`.

The checked-in `manifest.json` describes the signed APK in this folder.
Upload the APK to GitHub Releases first and deploy `manifest.json` to
Cloudflare last so clients never see a release before its APK is available.

For a real update:

1. Build a release APK with a higher `version:` build number in
   `apps/mobile/pubspec.yaml`.
2. Copy the signed APK into this folder with a versioned filename.
3. Replace `sha256`, `sizeBytes`, `latestVersionCode`, `latestVersionName`,
   `apkUrl`, and release notes in `manifest.json`.
4. Deploy this folder again.
