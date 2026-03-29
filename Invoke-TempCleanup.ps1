#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Enterprise Temp File Cleanup Script for Multi-User Windows Endpoints

.DESCRIPTION
    Safely removes temporary files across all user profiles and system
    locations on a Windows endpoint. Designed for HIPAA-regulated
    environments with full audit logging, dry-run support, and
    skip-in-use file handling. Compliant with NIST SP 800-53 CM-7.

.PARAMETER DryRun
    When specified, the script reports what WOULD be deleted without
    removing any files. Use for validation before production runs.

.PARAMETER LogPath
    Directory to write audit log files. Defaults to
    C:\IT\Logs\TempCleanup. Created automatically if absent.

.PARAMETER ExcludeUsers
    Array of usernames to skip entirely (e.g., service accounts).

.PARAMETER MaxAgeDays
    Only delete files older than this many days. Default: 7.
    Critical protection: files < 7 days old are left untouched.

.PARAMETER IncludeSoftwareDistribution
    When set, also clears Windows Update download cache
    (SoftwareDistribution\Download). Restarts wuauserv after.

.EXAMPLE
    # Full dry-run to assess impact
    .\Invoke-TempCleanup.ps1 -DryRun

.EXAMPLE
    # Production run, skip service accounts, files older than 14 days
    .\Invoke-TempCleanup.ps1 -ExcludeUsers "svc_backup","svc_sql" -MaxAgeDays 14

.EXAMPLE
    # Full cleanup including Windows Update cache
    .\Invoke-TempCleanup.ps1 -IncludeSoftwareDistribution

.NOTES
    Author      : Sandesh Gurung — IT Systems Administration
    Version     : 2.1.0
    Last Updated: 2026-03-01
    Tested On   : Windows 10 21H2, Windows 11 23H2, Server 2019/2022
    Compliance  : HIPAA Addressable § 164.310(d)(2), NIST CM-7
    CHANGELOG:
      2.1.0 - Added SoftwareDistribution cleanup, improved CBS log rotation
      2.0.0 - Multi-user refactor, per-user statistics, dry-run mode
      1.0.0 - Initial release
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [string]$LogPath        = "C:\IT\Logs\TempCleanup",
    [string[]]$ExcludeUsers = @(),
    [int]$MaxAgeDays        = 7,
    [switch]$IncludeSoftwareDistribution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # Log and continue; don't halt on one bad file

# ===========================================================================
# REGION: INITIALIZATION & LOGGING
# ===========================================================================

$Script:RunID     = (Get-Date -Format "yyyyMMdd_HHmmss")
$Script:LogFile   = Join-Path $LogPath "TempCleanup_$RunID.log"
$Script:StartTime = Get-Date
$Script:Stats     = @{ FilesRemoved = 0; BytesFreed = 0; FilesSkipped = 0; Errors = 0 }

function Write-Log {
    <# Writes timestamped entries to both console and log file. #>
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level = 'INFO')

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'INFO'    { 'Cyan'    }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SUCCESS' { 'Green'   }
    }
    Write-Host $logEntry -ForegroundColor $color

    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    Add-Content -Path $Script:LogFile -Value $logEntry -Encoding UTF8
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

# ===========================================================================
# REGION: CORE CLEANUP ENGINE
# ===========================================================================

function Remove-TempDirectory {
    <#
    .SYNOPSIS
        Safely removes files from a target directory with age filter,
        in-use detection, and dry-run awareness.
    #>
    param(
        [string]$Path,
        [string]$Label,
        [int]$AgeDays      = $MaxAgeDays,
        [switch]$Recurse,
        [string[]]$SkipFiles = @()    # File name patterns to always preserve
    )

    if (-not (Test-Path $Path)) {
        Write-Log "SKIP — Path not found: $Path" -Level WARN
        return
    }

    Write-Log "Scanning: [$Label] => $Path"

    $cutoff    = (Get-Date).AddDays(-$AgeDays)
    $getParams = @{ Path = $Path; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $getParams['Recurse'] = $true }

    $files = Get-ChildItem @getParams |
             Where-Object {
                 -not $_.PSIsContainer -and
                 $_.LastWriteTime -lt $cutoff -and
                 ($SkipFiles.Count -eq 0 -or
                  -not ($SkipFiles | Where-Object { $_.Name -like $_ }))
             }

    $localRemoved = 0
    $localBytes   = 0

    foreach ($file in $files) {
        try {
            $size = $file.Length

            if ($DryRun) {
                Write-Log "  [DRY-RUN] Would delete: $($file.FullName) ($(Format-Bytes $size))"
                $Script:Stats.FilesRemoved++
                $Script:Stats.BytesFreed += $size
                continue
            }

            # ── In-use detection ──────────────────────────────────────────
            # Attempt exclusive open; if it throws, the file is locked by another process
            $stream = $null
            try {
                $stream = [System.IO.File]::Open(
                    $file.FullName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )
                $stream.Close()
            }
            catch {
                $Script:Stats.FilesSkipped++
                Write-Log "  LOCKED (skip): $($file.FullName)" -Level WARN
                continue
            }

            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $Script:Stats.FilesRemoved++
            $Script:Stats.BytesFreed += $size
            $localRemoved++
            $localBytes   += $size
        }
        catch {
            $Script:Stats.Errors++
            Write-Log "  ERROR deleting $($file.FullName): $($_.Exception.Message)" -Level ERROR
        }
    }

    Write-Log ("  Done [{0}]: {1} files removed, {2} freed" -f
        $Label, $localRemoved, (Format-Bytes $localBytes)) -Level SUCCESS
}

# ===========================================================================
# REGION: PER-USER CLEANUP
# ===========================================================================

function Invoke-UserTempCleanup {
    <#
    .SYNOPSIS
        Runs temp cleanup against a single user profile.
    #>
    param([string]$ProfilePath, [string]$Username)

    Write-Log "=== Starting user cleanup: $Username ($ProfilePath) ==="

    $targets = @(
        # Primary temp folder (%TEMP% for this profile)
        @{ Path = "$ProfilePath\AppData\Local\Temp";                              Label = "User %TEMP%";      Recurse = $true  }

        # Internet Explorer / Legacy Edge cache
        @{ Path = "$ProfilePath\AppData\Local\Microsoft\Windows\INetCache";       Label = "INetCache";        Recurse = $true  }

        # Recent documents shortcut list (LNK files — not actual data files)
        @{ Path = "$ProfilePath\AppData\Roaming\Microsoft\Windows\Recent";        Label = "Recent Items";     Recurse = $false }

        # Thumbnail cache database
        @{ Path = "$ProfilePath\AppData\Local\Microsoft\Windows\Explorer";        Label = "Thumbnail Cache";  Recurse = $false }

        # Microsoft Teams temporary files (significant bloat in enterprise envs)
        @{ Path = "$ProfilePath\AppData\Local\Microsoft\Teams\tmp";               Label = "Teams Tmp";        Recurse = $true  }

        # User-space application crash dumps (may contain ePHI — HIPAA relevance)
        @{ Path = "$ProfilePath\AppData\Local\CrashDumps";                        Label = "Crash Dumps";      Recurse = $true  }
    )

    foreach ($t in $targets) {
        Remove-TempDirectory -Path $t.Path -Label $t.Label -Recurse:$t.Recurse
    }

    Write-Log "=== Completed user cleanup: $Username ==="
}

# ===========================================================================
# REGION: SYSTEM-WIDE CLEANUP
# ===========================================================================

function Invoke-SystemTempCleanup {

    Write-Log "=== Starting SYSTEM temp cleanup ==="

    # C:\Windows\Temp — shorter age filter; system temp changes faster
    Remove-TempDirectory -Path "C:\Windows\Temp" -Label "Windows Temp" -Recurse -AgeDays 1

    # Prefetch — preserve NTOSBOOT-*.pf which is critical for boot performance
    Remove-TempDirectory -Path "C:\Windows\Prefetch" -Label "Prefetch" `
        -SkipFiles @("NTOSBOOT-B00DFAAD.pf") -AgeDays 30

    # Component-Based Servicing & DISM logs — keep last 30 days for troubleshooting
    Remove-TempDirectory -Path "C:\Windows\Logs\CBS"  -Label "CBS Logs"  -AgeDays 30
    Remove-TempDirectory -Path "C:\Windows\Logs\DISM" -Label "DISM Logs" -AgeDays 30

    # System-level crash dumps and Windows Error Reporting archives
    Remove-TempDirectory -Path "C:\Windows\Minidump" -Label "Minidumps" -AgeDays 14
    Remove-TempDirectory -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" `
        -Label "WER Archives" -AgeDays 30 -Recurse

    # Windows Update download cache — optional; controlled by switch parameter
    if ($IncludeSoftwareDistribution) {
        Write-Log "Stopping Windows Update service to safely clear download cache..."
        if (-not $DryRun) {
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Remove-TempDirectory -Path "C:\Windows\SoftwareDistribution\Download" `
                -Label "WU Download Cache" -Recurse -AgeDays 0
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-Log "Windows Update service restarted." -Level SUCCESS
        } else {
            Write-Log "[DRY-RUN] Would stop wuauserv and clear SoftwareDistribution\Download"
        }
    }

    Write-Log "=== SYSTEM temp cleanup complete ==="
}

# ===========================================================================
# REGION: MAIN EXECUTION BLOCK
# ===========================================================================

# ── Script banner ────────────────────────────────────────────────────────────
$modeLabel = if ($DryRun) { " *** DRY-RUN MODE — NO FILES WILL BE DELETED ***" } else { "" }
Write-Log "╔══════════════════════════════════════════════════════╗"
Write-Log "║  Enterprise Temp File Cleanup  v2.1.0               ║"
Write-Log "║  Host   : $($env:COMPUTERNAME)"
Write-Log "║  Run by : $($env:USERNAME)"
Write-Log "╚══════════════════════════════════════════════════════╝"
if ($DryRun) { Write-Log $modeLabel -Level WARN }

# ── Enumerate user profiles ──────────────────────────────────────────────────
$profilesRoot = "C:\Users"
$userProfiles  = Get-ChildItem -Path $profilesRoot -Directory -ErrorAction Stop |
    Where-Object {
        $_.Name -notin @("Public", "Default", "Default User", "All Users") -and
        $_.Name -notin $ExcludeUsers -and
        (Test-Path "$($_.FullName)\AppData")
    }

Write-Log "Found $($userProfiles.Count) user profiles to process."
Write-Log "Excluded users  : $($ExcludeUsers -join ', ')"
Write-Log "Age threshold   : $MaxAgeDays days"

# ── Process each user profile ─────────────────────────────────────────────────
foreach ($profile in $userProfiles) {
    try {
        Invoke-UserTempCleanup -ProfilePath $profile.FullName -Username $profile.Name
    }
    catch {
        Write-Log "FATAL ERROR processing user $($profile.Name): $($_.Exception.Message)" -Level ERROR
        $Script:Stats.Errors++
    }
}

# ── System-wide locations ────────────────────────────────────────────────────
Invoke-SystemTempCleanup

# ── Final summary ────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $Script:StartTime
Write-Log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Log "CLEANUP SUMMARY"
Write-Log "  Files removed : $($Script:Stats.FilesRemoved)"
Write-Log "  Space freed   : $(Format-Bytes $Script:Stats.BytesFreed)"
Write-Log "  Files skipped : $($Script:Stats.FilesSkipped) (locked/in-use)"
Write-Log "  Errors        : $($Script:Stats.Errors)"
Write-Log "  Duration      : $($elapsed.ToString('mm\:ss'))"
Write-Log "  Log file      : $Script:LogFile"
Write-Log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Return non-zero exit code if errors occurred — enables SCCM/Intune detection rules
if ($Script:Stats.Errors -gt 0) { exit 1 } else { exit 0 }
