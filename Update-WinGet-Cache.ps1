param(
    [switch]$DeleteOld,
    [switch]$WhatIf,
    [string]$LogFile = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Update-WinGet-Cache.log")
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir "manifest.json"

# Fix #6: start transcript logging to file
$transcriptStarted = $false
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    try {
        Start-Transcript -Path $LogFile -Append -ErrorAction Stop
        $transcriptStarted = $true
    }
    catch {
        Write-Warning "Could not start log transcript: $_"
    }
}

# Helper to stop transcript before exiting
function Stop-Log {
    if ($script:transcriptStarted) {
        Stop-Transcript
        $script:transcriptStarted = $false
    }
}

if (-not (Test-Path $manifestPath)) {
    Write-Error "manifest.json not found at: $manifestPath"
    Stop-Log
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$cacheDir = $manifest.cacheDirectory

if ([string]::IsNullOrWhiteSpace($cacheDir)) {
    Write-Error "cacheDirectory is not defined in manifest.json"
    Stop-Log
    exit 1
}

if (-not (Test-Path $cacheDir)) {
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    Write-Host "$(if ($WhatIf) { '[WhatIf] Would create' } else { 'Created' }) cache directory: $cacheDir"
}

# Fix #8: wrap in @() so single-item or null JSON values are always treated as an array
$packages = @($manifest.packages)

if ($packages.Count -eq 0) {
    Write-Warning "No packages defined in manifest.json"
    Stop-Log
    exit 0
}

Write-Host "Cache directory: $cacheDir"
Write-Host "Packages to process: $($packages.Count)"
if ($DeleteOld) {
    Write-Host "DeleteOld: enabled - old versions will be removed after successful download" -ForegroundColor DarkYellow
}
# Fix #5: announce WhatIf mode
if ($WhatIf) {
    Write-Host "WhatIf: enabled - no changes will be made" -ForegroundColor DarkYellow
}

foreach ($packageId in $packages) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Processing: $packageId" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Get latest version info from winget
    $showOutput = & winget show --id $packageId --exact --accept-source-agreements 2>&1 | Out-String

    # Fix #1: anchor "Version:" to line start (after optional whitespace) so lines like
    # "Release Notes Version:" or "Installer Type: ..." are not mistakenly matched
    $versionMatch = [regex]::Match($showOutput, '(?m)^\s*Version\s*[:：]\s*([\d]\S*)')

    if (-not $versionMatch.Success) {
        # Fix #9: consistent Warning + continue for all package-level failures
        Write-Warning "[$packageId] Could not determine latest version. Skipping."
        Write-Warning "winget output:`n$showOutput"
        continue
    }

    $latestVersion = $versionMatch.Groups[1].Value.Trim()
    Write-Host "Latest version: $latestVersion"

    # Find existing local versions by folder name pattern: {PackageId}_{Version}
    $existingFolders = @(Get-ChildItem -Path $cacheDir -Directory -Filter "${packageId}_*" -ErrorAction SilentlyContinue)

    $localVersions = @()
    foreach ($folder in $existingFolders) {
        $ver = $folder.Name.Substring($packageId.Length + 1)
        $localVersions += $ver
    }

    if ($localVersions.Count -gt 0) {
        Write-Host "Local version(s): $($localVersions -join ', ')"
    }
    else {
        Write-Host "No local version found."
    }

    # Check if the latest version already exists locally
    $latestFolderPath = Join-Path $cacheDir "${packageId}_${latestVersion}"

    if (Test-Path $latestFolderPath) {
        Write-Host "Up to date." -ForegroundColor Green
        continue
    }

    # Fix #5: WhatIf dry-run - preview what would happen without making changes
    if ($WhatIf) {
        Write-Host "[WhatIf] Would create $latestFolderPath" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would download $packageId v$latestVersion into $latestFolderPath" -ForegroundColor Yellow
        if ($DeleteOld -and $existingFolders.Count -gt 0) {
            foreach ($folder in $existingFolders) {
                Write-Host "[WhatIf] Would remove old version: $($folder.Name)" -ForegroundColor DarkYellow
            }
        }
        continue
    }

    # Download the latest version
    # winget download -d does not create a package subfolder, so we create it first
    Write-Host "Downloading $packageId v$latestVersion ..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Path $latestFolderPath -Force | Out-Null

    $downloadExitCode = -1
    try {
        & winget download --id $packageId --version $latestVersion --exact --accept-package-agreements --accept-source-agreements -d $latestFolderPath
        $downloadExitCode = $LASTEXITCODE
    }
    catch {
        Write-Warning "[$packageId] Download threw an exception: $_"
    }

    if ($downloadExitCode -eq 0) {
        # Verify the folder contains files (winget may report success but download nothing)
        $downloadedFiles = @(Get-ChildItem -Path $latestFolderPath -File -ErrorAction SilentlyContinue)
        if ($downloadedFiles.Count -eq 0) {
            Write-Warning "[$packageId] Download succeeded but no files found in: $latestFolderPath"
            Remove-Item -Path $latestFolderPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        Write-Host "Downloaded successfully." -ForegroundColor Green

        # Remove old versions if -DeleteOld was specified
        if ($DeleteOld -and $existingFolders.Count -gt 0) {
            foreach ($folder in $existingFolders) {
                Write-Host "Removing old version: $($folder.Name)" -ForegroundColor DarkYellow
                Remove-Item -Path $folder.FullName -Recurse -Force
            }
        }
    }
    else {
        Write-Warning "[$packageId] Download failed (exit code: $downloadExitCode)."
        # Clean up the empty folder created before the failed download
        Remove-Item -Path $latestFolderPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nDone. All packages processed." -ForegroundColor Cyan
Stop-Log
