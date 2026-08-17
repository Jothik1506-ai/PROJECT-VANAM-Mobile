<#
  ONE-TIME setup: generates the VANAM release signing keystore.

  Read docs/OTA-RELEASES.md section 2 before running this.

  This key is permanent. Android only installs an update signed with the same
  key as the installed app. If this keystore or its password is ever lost,
  every family member has to UNINSTALL VANAM before they can update again —
  which destroys their locally-stored E2EE private keys and message history.
  There is no recovery path.

  Back the generated .jks file up in at least two places that are not this
  laptop and not the git repo.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Alias = "vanam"
)

$ErrorActionPreference = "Stop"

if (Test-Path $OutputPath) {
    Write-Error @"
A file already exists at $OutputPath.

Refusing to overwrite it. If this is the existing VANAM release keystore,
you should be REUSING it, not generating a new one — see
docs/OTA-RELEASES.md section 2.
"@
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($OutputPath -like "$repoRoot*") {
    Write-Error @"
Refusing to write the keystore inside the repository ($repoRoot).

Keystores must never be committed. Choose a path outside the repo, for
example: C:\Users\$env:USERNAME\vanam-keys\vanam-release.jks
"@
    exit 1
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

Write-Host ""
Write-Host "Generating the VANAM release keystore." -ForegroundColor Green
Write-Host "You will be asked for a password and some identity details."
Write-Host ""
Write-Host "WRITE THE PASSWORD DOWN SOMEWHERE SAFE NOW." -ForegroundColor Yellow
Write-Host "Losing it is unrecoverable - see docs/OTA-RELEASES.md section 2."
Write-Host ""

& keytool -genkeypair -v `
    -keystore $OutputPath `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -alias $Alias

if ($LASTEXITCODE -ne 0) {
    Write-Error "keytool failed (exit $LASTEXITCODE). Keystore was not created."
    exit $LASTEXITCODE
}

$keyPropsPath = Join-Path $repoRoot "apps\mobile\android\key.properties"
$escaped = $OutputPath -replace '\\', '/'

Write-Host ""
Write-Host "Keystore created: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Next: create $keyPropsPath with:" -ForegroundColor Cyan
Write-Host ""
Write-Host "storeFile=$escaped"
Write-Host "storePassword=<the password you just set>"
Write-Host "keyAlias=$Alias"
Write-Host "keyPassword=<the password you just set>"
Write-Host ""
Write-Host "key.properties is gitignored. Never commit it." -ForegroundColor Yellow
Write-Host "Back up the .jks file to two places outside this laptop." -ForegroundColor Yellow
Write-Host ""
