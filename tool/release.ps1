<#
  Builds a signed release APK, verifies its signature, computes its checksum,
  and emits the matching update-manifest JSON.

  Doing all of this in one step is deliberate: the manifest's sha256 must
  describe the exact APK being published. Computing them separately is how
  they drift, and a drifted checksum means every client refuses the update.

  Usage:
    .\tool\release.ps1
    .\tool\release.ps1 -OutputDir C:\vanam-releases

  See docs/OTA-RELEASES.md section 6.
#>

param(
    [string]$OutputDir = "",
    [string]$WorkManagerActivityUrl = "https://manager.aivafreelancia.in/api/vanam/mobile/activity",
    [string]$WorkManagerActivitySecret = $env:WORK_MANAGER_ACTIVITY_SECRET
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot "apps\mobile"
$keyProps = Join-Path $appDir "android\key.properties"

if (-not (Test-Path $keyProps)) {
    Write-Error @"
No signing config found at:
  $keyProps

Release builds must be signed with the permanent VANAM release key, never
the debug key. A debug-signed build that reaches a real phone can never be
updated in place - the user would have to uninstall, losing their E2EE keys.

Run tool\make-keystore.ps1 first, then create key.properties.
See docs/OTA-RELEASES.md section 2.
"@
    exit 1
}

if (-not $WorkManagerActivitySecret) {
    throw "WORK_MANAGER_ACTIVITY_SECRET is required for a release build."
}

# --- read version from pubspec (single source of truth) -------------------
$pubspec = Get-Content (Join-Path $appDir "pubspec.yaml") -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    Write-Error "Could not parse 'version: x.y.z+N' from pubspec.yaml"
    exit 1
}
$versionName = $Matches[1]
$versionCode = [int]$Matches[2]

Write-Host ""
Write-Host "Building VANAM $versionName (versionCode $versionCode)" -ForegroundColor Green
Write-Host ""

Push-Location $appDir
try {
    $buildArgs = @(
        "build", "apk", "--release", "--flavor", "ota",
        "--dart-define=VANAM_UPDATE_CHECKS_ENABLED=true",
        "--dart-define=WORK_MANAGER_ACTIVITY_URL=$WorkManagerActivityUrl"
    )
    $buildArgs += "--dart-define=WORK_MANAGER_ACTIVITY_SECRET=$WorkManagerActivitySecret"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-ota-release.apk"
if (-not (Test-Path $apk)) { throw "Expected APK not found at $apk" }

# --- verify it is NOT debug-signed ----------------------------------------
# This is the check that catches the most damaging possible mistake.
Write-Host ""
Write-Host "Verifying signature..." -ForegroundColor Cyan
$certInfo = & keytool -printcert -jarfile $apk 2>&1 | Out-String

if ($certInfo -match "CN=Android Debug") {
    Write-Error @"
REFUSING TO PUBLISH: this APK is signed with the ANDROID DEBUG KEY.

Distributing it would permanently break the update path for anyone who
installs it - they would have to uninstall (losing their E2EE private keys)
before a properly-signed build could ever install over it.

Check that android/key.properties points at the real release keystore.
"@
    exit 1
}
Write-Host "Signature OK (not a debug key)." -ForegroundColor Green

# --- checksum + rename ----------------------------------------------------
$sha = (Get-FileHash -Path $apk -Algorithm SHA256).Hash.ToLower()
$sizeBytes = (Get-Item $apk).Length

if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot "build-output" }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# Version-stamped filename: published APKs are immutable. Never overwrite a
# filename that has already been distributed.
$releaseName = "vanam-$versionName-$versionCode.apk"
$releasePath = Join-Path $OutputDir $releaseName
Copy-Item $apk $releasePath -Force

$releaseTag = "v$versionName-$versionCode"
$manifest = [ordered]@{
    latestVersionCode       = $versionCode
    latestVersionName       = $versionName
    minSupportedVersionCode = 0
    apkUrl                  = "https://github.com/Jothik1506-ai/PROJECT-VANAM-Mobile/releases/download/$releaseTag/$releaseName"
    sha256                  = $sha
    sizeBytes               = $sizeBytes
    releaseNotes            = "Home post sharing to Vanam chats, Work Manager mobile activity reporting, and fresh signed release build."
    releaseNotesTe          = "Vanam chats lo home post share, Work Manager mobile activity reporting, mariyu fresh signed release build."
    publishedAt             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
}

$manifestPath = Join-Path $OutputDir "manifest.json"
$manifest | ConvertTo-Json | Out-File -FilePath $manifestPath -Encoding utf8

Write-Host ""
Write-Host "APK:      $releasePath" -ForegroundColor Green
Write-Host "Size:     $([math]::Round($sizeBytes/1MB,1)) MB"
Write-Host "SHA-256:  $sha"
Write-Host "Manifest: $manifestPath" -ForegroundColor Green
Write-Host ""
Write-Host "Before publishing:" -ForegroundColor Yellow
Write-Host "  1. Fill in releaseNotes / releaseNotesTe in manifest.json."
Write-Host "  2. Upload the APK to R2 under this exact filename."
Write-Host "  3. INSTALL IT OVER THE PREVIOUS RELEASE on a real device and"
Write-Host "     confirm it updates in place with no uninstall prompt."
Write-Host "  4. Only then publish manifest.json."
Write-Host ""
Write-Host "Step 3 is what catches signing mistakes. Do not skip it." -ForegroundColor Yellow
Write-Host ""
