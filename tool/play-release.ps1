<#
  Builds the signed Google Play App Bundle.

  Play builds deliberately disable VANAM's APK updater and omit Android's
  REQUEST_INSTALL_PACKAGES permission. Updates for this build are delivered
  by Google Play after a newer versionCode is uploaded.
#>

param(
    [string]$WorkManagerActivityUrl = "https://manager.aivafreelancia.in/api/vanam/mobile/activity",
    [string]$WorkManagerActivitySecret = $env:WORK_MANAGER_ACTIVITY_SECRET
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot "apps\mobile"
$keyProps = Join-Path $appDir "android\key.properties"

if (-not (Test-Path $keyProps)) {
    throw "Release signing config is missing at $keyProps"
}

if (-not $WorkManagerActivitySecret) {
    throw "WORK_MANAGER_ACTIVITY_SECRET is required for a Play release build."
}

Push-Location $appDir
try {
    $buildArgs = @(
        "build", "appbundle", "--release", "--flavor", "play",
        "--dart-define=VANAM_UPDATE_CHECKS_ENABLED=false",
        "--dart-define=WORK_MANAGER_ACTIVITY_URL=$WorkManagerActivityUrl"
    )
    $buildArgs += "--dart-define=WORK_MANAGER_ACTIVITY_SECRET=$WorkManagerActivitySecret"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}

$bundle = Join-Path $appDir "build\app\outputs\bundle\playRelease\app-play-release.aab"
if (-not (Test-Path $bundle)) { throw "Expected App Bundle not found at $bundle" }

$certInfo = & keytool -printcert -jarfile $bundle 2>&1 | Out-String
if ($certInfo -match "CN=Android Debug") {
    throw "Refusing to publish an App Bundle signed with the Android debug key."
}

Write-Host ""
Write-Host "Google Play bundle ready:" -ForegroundColor Green
Write-Host "  $bundle"
Write-Host ""
