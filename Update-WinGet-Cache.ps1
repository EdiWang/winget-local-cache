param(
    [switch]$DeleteOld
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir "manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "manifest.json not found at: $manifestPath"
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$cacheDir = $manifest.cacheDirectory

if ([string]::IsNullOrWhiteSpace($cacheDir)) {
    Write-Error "cacheDirectory is not defined in manifest.json"
    exit 1
}

if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Write-Host "Created cache directory: $cacheDir"
}

$packages = $manifest.packages

if ($null -eq $packages -or $packages.Count -eq 0) {
    Write-Warning "No packages defined in manifest.json"
    exit 0
}

Write-Host "Cache directory: $cacheDir"
Write-Host "Packages to process: $($packages.Count)"
if ($DeleteOld) {
    Write-Host "DeleteOld: enabled - old versions will be removed after successful download" -ForegroundColor DarkYellow
}

foreach ($packageId in $packages) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Processing: $packageId" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Get latest version info from winget
    $showOutput = & winget show --id $packageId --exact --accept-source-agreements 2>&1 | Out-String

    # Parse version from the output
    $versionMatch = [regex]::Match($showOutput, '(?m)^.*Version\s*[:：]\s*(.+)$')

    if (-not $versionMatch.Success) {
        Write-Warning "Could not determine latest version for $packageId. Skipping."
        Write-Warning "winget output:`n$showOutput"
        continue
    }

    $latestVersion = $versionMatch.Groups[1].Value.Trim()
    Write-Host "Latest version: $latestVersion"

    # Find existing local versions by folder name pattern: {PackageId}_{Version}
    $existingFolders = Get-ChildItem -Path $cacheDir -Directory -Filter "${packageId}_*" -ErrorAction SilentlyContinue

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

    # Download the latest version
    Write-Host "Downloading $packageId v$latestVersion ..." -ForegroundColor Yellow
    & winget download --id $packageId --exact -d $cacheDir --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
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
        Write-Warning "Download failed for $packageId (exit code: $LASTEXITCODE)."
    }
}

Write-Host "`nDone. All packages processed." -ForegroundColor Cyan
