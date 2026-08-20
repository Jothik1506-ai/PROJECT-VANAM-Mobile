# Work Manager Mobile Activity

Vanam Mobile reports safe admin/activity metadata to AIVA Work Manager.

It sends:
- family member id
- display name
- username
- role/status
- app version
- platform/device label
- push-enabled boolean
- last login / active / feedback timestamps

It never sends:
- message content
- ciphertext
- private keys
- recovery codes
- raw FCM/APNs push tokens

## Build Defines

Set these when building an APK or OTA release:

```powershell
flutter build apk --release `
  --dart-define=WORK_MANAGER_ACTIVITY_URL=https://aiva-work-manager-by4q.onrender.com/api/vanam/mobile/activity `
  --dart-define=WORK_MANAGER_ACTIVITY_SECRET=<same value as Work Manager VANAM_MOBILE_SHARED_SECRET>
```

Without `WORK_MANAGER_ACTIVITY_SECRET`, the app still works normally but skips activity reporting.

## Work Manager

The Work Manager server must have:

```env
VANAM_MOBILE_SHARED_SECRET=<same secret used by the mobile build>
```

The activity table is visible from the Vanam project workspace's **Vanam Mobile Activity** tab.
