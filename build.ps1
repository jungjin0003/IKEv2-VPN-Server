# Package the IKEv2VPN .spk on Windows.
#
# This ONLY assembles the .spk from a PREBUILT strongSwan; it never compiles
# strongSwan (that needs a Linux toolchain - use ./build.sh on Linux for a
# full source build). It invokes build.sh in --spk-only mode via Git Bash.
$ErrorActionPreference = "Stop"

# require a prebuilt strongSwan (bundled under src/package/strongswan/)
$charon = Join-Path $PSScriptRoot "src\package\strongswan\libexec\ipsec\charon"
$swanctl = Join-Path $PSScriptRoot "src\package\strongswan\sbin\swanctl"
if (-not (Test-Path $charon) -or -not (Test-Path $swanctl)) {
    Write-Error "Prebuilt strongSwan not found under src\package\strongswan\. Build it first on Linux with ./build.sh (or drop a strongswan-*-IKEv2VPN-static.tar.gz next to build.sh)."
}

# regenerate icons if missing
if (-not (Test-Path (Join-Path $PSScriptRoot "src\PACKAGE_ICON.PNG"))) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "tools\make-icons.ps1")
}

# locate Git Bash
$bash = $null
$cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($cmd) { $bash = $cmd.Source }
if (-not $bash) {
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe",
                     "$env:ProgramFiles\Git\usr\bin\bash.exe",
                     "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
                     "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if (Test-Path $p) { $bash = $p; break }
    }
}
if (-not $bash) {
    Write-Error "Git Bash not found. Install Git for Windows, or build on Linux with ./build.sh"
}

# assemble the .spk only (never compile strongSwan)
$script = (Join-Path $PSScriptRoot "build.sh") -replace '\\', '/'
& $bash $script --spk-only
if ($LASTEXITCODE -ne 0) { Write-Error "build failed (exit $LASTEXITCODE)" }
