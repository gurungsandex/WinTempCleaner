#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WinTempCleaner - Cleans temporary files on Windows to improve system performance.

.DESCRIPTION
    Deletes temporary files across all user profiles and system locations.
    Safe to run: skips files in use, skips files newer than 7 days,
    and writes a log after every run.

.PARAMETER DryRun
    Shows what WOULD be deleted without deleting anything.
    Always run this first to preview the cleanup.

.PARAMETER IncludeSoftwareDistribution
    Also clears the Windows Update download cache for extra space recovery.

.PARAMETER IncludeRecycleBin
    Also empties the Recycle Bin for all users.

.PARAMETER MaxAgeDays
    Only delete files older than this many days. Default is 7.

.EXAMPLE
    Preview only - nothing deleted:
    .\WinTempCleaner.ps1 -DryRun

.EXAMPLE
    Run the cleanup:
    .\WinTempCleaner.ps1

.EXAMPLE
    Full cleanup including Windows Update cache and Recycle Bin:
    .\WinTempCleaner.ps1 -IncludeSoftwareDistribution -IncludeRecycleBin

.NOTES
    Author  : Sandesh Gurung
    GitHub  : https://github.com/gurungsandex/WinTempCleaner
    Version : 1.0.0
    License : MIT
#>

param(
    [switch]$DryRun,
    [switch]$IncludeSoftwareDistribution,
    [switch]$IncludeRecycleBin,
    [int]$MaxAgeDays = 7
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------

$LogFolder = "C:\WinTempCleaner\Logs"
$LogFile   = Join-Path $LogFolder ("WinTempCleaner_{0}_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss"))
$StartTime = Get-Date
$Stats     = @{ Removed = 0; Freed = 0; Skipped = 0; Errors = 0 }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $color = switch ($Level) {
        "INFO"    { "Cyan"    }
        "SUCCESS" { "Green"   }
        "WARN"    { "Yellow"  }
        "ERROR"   { "Red"     }
        default   { "White"   }
    }
    Write-Host $entry -ForegroundColor $color
    if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

# ---------------------------------------------------------------------------
# CORE CLEANUP FUNCTION
# ---------------------------------------------------------------------------

function Clear-Folder {
    param(
        [string]$Path,
        [string]$Label,
        [int]$AgeDays   = $MaxAgeDays,
        [switch]$Recurse
    )

    if (-not (Test-Path $Path)) { return }

    Write-Log "Scanning: $Label"

    $cutoff = (Get-Date).AddDays(-$AgeDays)
    $params = @{ Path = $Path; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params['Recurse'] = $true }

    $files = Get-ChildItem @params | Where-Object {
        -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff
    }

    $removed = 0
    $freed   = 0

    foreach ($file in $files) {
        try {
            $size = $file.Length

            if ($DryRun) {
                Write-Log "  [PREVIEW] $($file.FullName) ($(Format-Bytes $size))"
                $Stats.Removed++
                $Stats.Freed += $size
                continue
            }

            # Check if file is in use before trying to delete
            try {
                $stream = [System.IO.File]::Open($file.FullName, 'Open', 'ReadWrite', 'None')
                $stream.Close()
            } catch {
                $Stats.Skipped++
                continue
            }

            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $Stats.Removed++
            $Stats.Freed += $size
            $removed++
            $freed   += $size
        }
        catch {
            $Stats.Errors++
            Write-Log "  Could not delete: $($file.Name)" -Level ERROR
        }
    }

    if (-not $DryRun) {
        Write-Log "  Done: $removed files removed, $(Format-Bytes $freed) freed" -Level SUCCESS
    }
}

# ---------------------------------------------------------------------------
# WHAT GETS CLEANED
# ---------------------------------------------------------------------------

function Start-UserCleanup {
    param([string]$ProfilePath, [string]$Username)

    Write-Log "--- Cleaning user: $Username ---"

    Clear-Folder "$ProfilePath\AppData\Local\Temp"                                          -Label "Temp Files"         -Recurse
    Clear-Folder "$ProfilePath\AppData\Local\Microsoft\Windows\INetCache"                   -Label "Browser Cache"      -Recurse
    Clear-Folder "$ProfilePath\AppData\Roaming\Microsoft\Windows\Recent"                    -Label "Recent Items"
    Clear-Folder "$ProfilePath\AppData\Local\Microsoft\Windows\Explorer"                    -Label "Thumbnail Cache"
    Clear-Folder "$ProfilePath\AppData\Local\Microsoft\Teams\tmp"                           -Label "Teams Temp"         -Recurse
    Clear-Folder "$ProfilePath\AppData\Local\Google\Chrome\User Data\Default\Cache"         -Label "Chrome Cache"       -Recurse
    Clear-Folder "$ProfilePath\AppData\Local\Mozilla\Firefox\Profiles"                      -Label "Firefox Cache"      -Recurse
    Clear-Folder "$ProfilePath\AppData\Local\CrashDumps"                                    -Label "Crash Dumps"        -Recurse
}

function Start-SystemCleanup {

    Write-Log "--- Cleaning system locations ---"

    Clear-Folder "C:\Windows\Temp"          -Label "Windows Temp"   -Recurse -AgeDays 1
    Clear-Folder "C:\Windows\Logs\CBS"      -Label "CBS Logs"                -AgeDays 30
    Clear-Folder "C:\Windows\Logs\DISM"     -Label "DISM Logs"               -AgeDays 30
    Clear-Folder "C:\Windows\Minidump"      -Label "Minidumps"               -AgeDays 14
    Clear-Folder "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" -Label "Error Reports" -Recurse -AgeDays 30

    # Prefetch - skip the NTOSBOOT file which Windows needs for fast boot
    $prefetchFiles = Get-ChildItem "C:\Windows\Prefetch" -Filter "*.pf" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "NTOSBOOT-B00DFAAD.pf" -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
    foreach ($f in $prefetchFiles) {
        try { Remove-Item $f.FullName -Force } catch {}
    }
    Write-Log "  Done: Prefetch cleaned" -Level SUCCESS

    # Optional: Windows Update cache
    if ($IncludeSoftwareDistribution) {
        Write-Log "Clearing Windows Update cache..."
        if (-not $DryRun) {
            Stop-Service  -Name wuauserv -Force -ErrorAction SilentlyContinue
            Clear-Folder "C:\Windows\SoftwareDistribution\Download" -Label "Windows Update Cache" -Recurse -AgeDays 0
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        } else {
            Write-Log "  [PREVIEW] Would clear Windows Update download cache"
        }
    }

    # Optional: Recycle Bin
    if ($IncludeRecycleBin) {
        Write-Log "Emptying Recycle Bin..."
        if (-not $DryRun) {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-Log "  Done: Recycle Bin emptied" -Level SUCCESS
            } catch {
                Write-Log "  Could not empty Recycle Bin" -Level ERROR
            }
        } else {
            Write-Log "  [PREVIEW] Would empty Recycle Bin"
        }
    }
}

# ---------------------------------------------------------------------------
# DISK SPACE HELPER
# ---------------------------------------------------------------------------

function Get-DiskSpace {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($drive) {
        $free  = $drive.Free
        $total = $drive.Used + $drive.Free
        return "Free: $(Format-Bytes $free) of $(Format-Bytes $total)"
    }
    return "Unavailable"
}

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------

Write-Log "========================================================"
Write-Log "  WinTempCleaner v1.0.0"
Write-Log "  https://github.com/gurungsandex/WinTempCleaner"
Write-Log "========================================================"
Write-Log "  Computer : $env:COMPUTERNAME"
Write-Log "  Mode     : $(if ($DryRun) { 'PREVIEW (nothing will be deleted)' } else { 'LIVE CLEANUP' })"
Write-Log "  Age filter: Files older than $MaxAgeDays days"
Write-Log "  Disk now : $(Get-DiskSpace)"
Write-Log "========================================================"

# Find all real user profiles
$skipProfiles = @("Public", "Default", "Default User", "All Users", "defaultuser0")
$profiles = Get-ChildItem "C:\Users" -Directory -ErrorAction Stop |
    Where-Object { $_.Name -notin $skipProfiles -and (Test-Path "$($_.FullName)\AppData") }

Write-Log "Found $($profiles.Count) user profile(s) to clean."

foreach ($profile in $profiles) {
    try {
        Start-UserCleanup -ProfilePath $profile.FullName -Username $profile.Name
    } catch {
        Write-Log "Could not process user $($profile.Name): $($_.Exception.Message)" -Level ERROR
        $Stats.Errors++
    }
}

Start-SystemCleanup

# Final summary
$elapsed = (Get-Date) - $StartTime
Write-Log "========================================================"
Write-Log "  DONE"
Write-Log "========================================================"
Write-Log "  Files cleaned : $($Stats.Removed)"
Write-Log "  Space freed   : $(Format-Bytes $Stats.Freed)"
Write-Log "  Files skipped : $($Stats.Skipped) (in use by Windows)"
Write-Log "  Errors        : $($Stats.Errors)"
Write-Log "  Time taken    : $($elapsed.ToString('mm\:ss'))"
Write-Log "  Disk now      : $(Get-DiskSpace)"
Write-Log "  Log saved to  : $LogFile"
Write-Log "========================================================"

if ($DryRun) {
    Write-Log ""
    Write-Log "This was a PREVIEW. No files were deleted." -Level WARN
    Write-Log "Run without -DryRun to perform the actual cleanup." -Level WARN
}

exit $(if ($Stats.Errors -gt 0) { 1 } else { 0 })
