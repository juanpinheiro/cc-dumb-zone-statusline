# install.ps1 — PowerShell wrapper for cc-dumb-zone-statusline
# Delegates to Git Bash or WSL; does NOT reimplement install.sh logic.
# PowerShell 5.1 compatible — no ??, no ?., no ternaries.

Set-StrictMode -Version 1

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Step 1 — Find bash
# ---------------------------------------------------------------------------
Write-Host "[ps-wrapper] Searching for bash..."

$bashCandidates = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe'
)

$bash = $null

foreach ($candidate in $bashCandidates) {
    if (Test-Path $candidate) {
        $bash = $candidate
        break
    }
}

if ($null -eq $bash) {
    $pathBash = $null
    try {
        $pathBash = (Get-Command bash -ErrorAction Stop).Source
    } catch {
        $pathBash = $null
    }
    if ($null -ne $pathBash -and $pathBash -ne '') {
        $bash = $pathBash
    }
}

if ($null -eq $bash) {
    $wslBash = 'C:\Windows\System32\bash.exe'
    if (Test-Path $wslBash) {
        $bash = $wslBash
    }
}

if ($null -eq $bash) {
    Write-Error "[ps-wrapper] No bash found. Install Git Bash from https://git-scm.com/download/win`nOR enable WSL with: wsl --install"
    exit 1
}

Write-Host "[ps-wrapper] Using bash: $bash"

# ---------------------------------------------------------------------------
# Step 2 — Download install.sh to a temp file
# ---------------------------------------------------------------------------
$tempInstall = [System.IO.Path]::GetTempFileName()
# Replace .tmp extension with .sh so bash accepts it cleanly
$tempInstall = [System.IO.Path]::ChangeExtension($tempInstall, 'sh')

try {
    $version = $env:VERSION
    if ($null -eq $version) { $version = '' }

    if ($version -ne '') {
        $url = "https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/$version/install.sh"
    } else {
        $url = 'https://raw.githubusercontent.com/juanpinheiro/cc-dumb-zone-statusline/main/install.sh'
    }

    Write-Host "[ps-wrapper] Downloading install.sh from $url"
    Invoke-WebRequest -Uri $url -OutFile $tempInstall -UseBasicParsing

    # ---------------------------------------------------------------------------
    # Step 3 — Delegate to bash
    # ---------------------------------------------------------------------------
    $force = $env:FORCE
    if ($null -eq $force) { $force = '' }

    # Build env-prefixed command; quote the temp path for bash (forward slashes, handle spaces).
    $bashPath = $tempInstall -replace '\\', '/'

    Write-Host "[ps-wrapper] Delegating to bash..."
    & $bash -c "FORCE='$force' VERSION='$version' bash '$bashPath'"
    $bashExitCode = $LASTEXITCODE
} finally {
    if (Test-Path $tempInstall) {
        Remove-Item $tempInstall -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Step 4 — Propagate exit code
# ---------------------------------------------------------------------------
exit $bashExitCode
