# winget-local-cache

A PowerShell script that maintains a local cache of winget package installers. It checks each package for a newer version and downloads it if not already cached.

## Prerequisites

- Windows with [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) installed
- PowerShell 5.1 or later

## Setup

1. Edit `manifest.json` to set your cache directory and the list of packages to cache:

```json
{
    "cacheDirectory": "D:\\winget-local-cache",
    "packages": [
        "Git.Git",
        "Microsoft.VisualStudioCode",
        "Notepad++.Notepad++"
    ]
}
```

- `cacheDirectory` — path where installer files will be stored
- `packages` — list of winget package IDs to cache

## Usage

Run the script from the directory containing `manifest.json`:

```powershell
.\Update-WinGet-Cache.ps1
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DeleteOld` | Switch | Remove previously cached versions after a successful download of the latest version |
| `-WhatIf` | Switch | Preview what would be downloaded/deleted without making any changes |
| `-LogFile` | String | Path to the log file (default: `Update-WinGet-Cache.log` next to the script) |

### Examples

Download latest versions of all packages:
```powershell
.\Update-WinGet-Cache.ps1
```

Download and remove old cached versions:
```powershell
.\Update-WinGet-Cache.ps1 -DeleteOld
```

Preview what would happen without making changes:
```powershell
.\Update-WinGet-Cache.ps1 -WhatIf
```

Write logs to a custom path:
```powershell
.\Update-WinGet-Cache.ps1 -LogFile "C:\Logs\winget-cache.log"
```

## Cache Layout

Each package version is stored in its own subfolder under the cache directory:

```
D:\winget-local-cache\
├── Git.Git_2.47.1\
│   └── Git-2.47.1-64-bit.exe
├── Microsoft.VisualStudioCode_1.99.0\
│   └── VSCodeSetup-x64-1.99.0.exe
└── Notepad++.Notepad++_8.7.9\
    └── npp.8.7.9.Installer.x64.exe
```

If a version folder already exists, the package is skipped as up to date.
