# VANAM OTA Updates

Deploy this folder to Cloudflare Pages and attach:

```text
updates.vanam.aivafreelancia.in
```

Required public files:

```text
manifest.json
vanam-<version-name>-<version-code>.apk
```

The starter `manifest.json` is intentionally set to `latestVersionCode: 1`,
matching the current installed app, so it will not trigger an update yet.

For a real update:

1. Build a release APK with a higher `version:` build number in
   `apps/mobile/pubspec.yaml`.
2. Copy the signed APK into this folder with a versioned filename.
3. Replace `sha256`, `sizeBytes`, `latestVersionCode`, `latestVersionName`,
   `apkUrl`, and release notes in `manifest.json`.
4. Deploy this folder again.
