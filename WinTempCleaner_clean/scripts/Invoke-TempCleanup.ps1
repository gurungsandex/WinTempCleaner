#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    WinTempCleaner — Enterprise-grade temp file cleanup for Windows endpoints.

.DESCRIPTION
    Safely removes temporary files across all user profiles and system
    locations on any Windows machine. Supports dry-run mode, age-based
    filtering, in-use file detection, structured audit logging, and
    optional Windows Update cache cleanup.

    Designed for IT administrators managing single machines or large
    endpoint fleets (via Intune, SCCM, or Task Scheduler).

.PARAMETER DryRun
    Simulates the cleanup and reports what WOULD be deleted without
    removing any files. Always run this first on a new machine.

.PARAMETER LogPath
    Directory where audit log files are written.
    Default: C:\WinTempCleaner\Logs
    Created automatically if it does not exist.

.PARAMETER ExcludeUsers
    Usernames to skip entirely. Use for service accounts, admin accounts,
    or any profile that should not be touched.
    Example: -ExcludeUsers "svc_backup","svc_sql","Administrator"

.PARAMETER MaxAgeDays
    Only deletes files older than this many days.
    Default: 7
    Set higher (e.g. 14) in conservative environments.
    Never set to 0 on user %TEMP% — active files will be deleted.

.PARAMETER IncludeSoftwareDistribution
    Also clears the Windows Update download cache
    (C:\Windows\SoftwareDistribution\Download).
    The script safely stops and restarts the wuauserv service around this.

.PARAMETER IncludeRecycleBin
    Empties the Recycle Bin for all users on the machine.

.EXAMPLE
    # Step 1 — always dry-run first
    .\Invoke-TempCleanup.ps1 -DryRun

.EXAMPLE
    # Standard production run with 7-day age filter
    .\Invoke-TempCleanup.ps1

.EXAMPLE
    # Exclude service accounts, use 14-day filter
    .\Invoke-TempCleanup.ps1 -ExcludeUsers "svc_backup","svc_sql" -MaxAgeDays 14

.EXAMPLE
    # Full cleanup including Windows Update cache and Recycle Bin
    .\Invoke-TempCleanup.ps1 -IncludeSoftwareDistribution -IncludeRecycleBin

.EXAMPLE
    # Custom log path
    .\Invoke-TempCleanup.ps1 -LogPath "D:\IT\Logs\TempCleanup"

.NOTES
    Project     : WinTempCleaner
    Author      : Sandesh Gurung
    GitHub      : https://github.com/gurungsandex/WinTempCleaner
    Version     : 1.0.0
    Tested On   : Windows 10 21H2+, Windows 11 22H2+, Server 2019, Server 2022
    License     : MIT

    CHANGELOG:
      1.0.0 - Initial public release
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]  $DryRun,
    [string]  $LogPath        = "C:\WinTempCleaner\Logs",
    [string[]]$ExcludeUsers   = @(),
    [int]     $MaxAgeDays     = 7,
    [switch]  $IncludeSoftwareDistribution,
    [switch]  $IncludeRecycleBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ===========================================================================
# REGION: INITIALIZATION
# ===========================================================================

$Script:Version   = "1.0.0"
$Script:RunID     = (Get-Date -Format "yyyyMMdd_HHmmss")
$Script:LogFile   = Join-Path $LogPath "WinTempCleaner_$($env:COMPUTERNAME)_$RunID.log"
$Script:StartTime = Get-Date
$Script:Stats     = @{
    FilesRemoved = 0
    BytesFreed   = 0
    FilesSkipped = 0
    Errors       = 0
    Locations    = 0
}

# ===========================================================================
# REGION: LOGGING
# ===========================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','HEADER')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        'INFO'    { 'Cyan'    }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SUCCESS' { 'Green'   }
        'HEADER'  { 'White'   }
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
        Deletes files from a single target directory with safety checks.
    .DESCRIPTION
        - Skips paths that do not exist
        - Applies age filter (LastWriteTime older than MaxAgeDays)
        - Tests each file for an exclusive lock before attempting deletion
        - Locked/in-use files are logged and skipped, never force-killed
        - Respects DryRun mode throughout
    #>
    param(
        [string]  $Path,
        [string]  $Label,
        [int]     $AgeDays    = $MaxAgeDays,
        [switch]  $Recurse,
        [string[]]$SkipNames  = @()
    )

    if (-not (Test-Path $Path)) {
        Write-Log "SKIP — not found: $Path" -Level WARN
        return
    }

    Write-Log "Scanning [$Label] : $Path"
    $Script:Stats.Locations++

    $cutoff    = (Get-Date).AddDays(-$AgeDays)
    $getParams = @{ Path = $Path; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $getParams['Recurse'] = $true }

    $files = Get-ChildItem @getParams | Where-Object {
        -not $_.PSIsContainer -and
        $_.LastWriteTime -lt $cutoff -and
        ($SkipNames.Count -eq 0 -or ($SkipNames | Where-Object { $_ -eq $_.Name }).Count -eq 0)
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

            # ── In-use detection via exclusive file handle ────────────────
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
                Write-Log "  LOCKED — skipping: $($file.Name)" -Level WARN
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
            Write-Log "  ERROR: $($file.FullName) — $($_.Exception.Message)" -Level ERROR
        }
    }

    $verb = if ($DryRun) { "Would free" } else { "Freed" }
    Write-Log ("  [{0}] {1} files | {2} {3}" -f
        $Label, $localRemoved, $verb, (Format-Bytes $localBytes)) -Level SUCCESS
}

# ===========================================================================
# REGION: PER-USER CLEANUP
# ===========================================================================

function Invoke-UserTempCleanup {
    param(
        [string]$ProfilePath,
        [string]$Username
    )

    Write-Log "--- User: $Username ---" -Level HEADER

    $targets = @(
        @{
            Path    = "$ProfilePath\AppData\Local\Temp"
            Label   = "%TEMP%"
            Recurse = $true
        }
        @{
            Path    = "$ProfilePath\AppData\Local\Microsoft\Windows\INetCache"
            Label   = "IE/Edge Cache"
            Recurse = $true
        }
        @{
            Path    = "$ProfilePath\AppData\Roaming\Microsoft\Windows\Recent"
            Label   = "Recent Items"
            Recurse = $false
        }
        @{
            Path    = "$ProfilePath\AppData\Local\Microsoft\Windows\Explorer"
            Label   = "Thumbnail Cache"
            Recurse = $false
        }
        @{
            Path    = "$ProfilePath\AppData\Local\Microsoft\Teams\tmp"
            Label   = "Teams Tmp"
            Recurse = $true
        }
        @{
            Path    = "$ProfilePath\AppData\Local\Google\Chrome\User Data\Default\Cache"
            Label   = "Chrome Cache"
            Recurse = $true
        }
        @{
            Path    = "$ProfilePath\AppData\Local\Mozilla\Firefox\Profiles"
            Label   = "Firefox Cache"
            Recurse = $true
        }
        @{
            Path    = "$ProfilePath\AppData\Local\CrashDumps"
            Label   = "Crash Dumps"
            Recurse = $true
        }
    )

    foreach ($t in $targets) {
        Remove-TempDirectory -Path $t.Path -Label $t.Label -Recurse:$t.Recurse
    }
}

# ===========================================================================
# REGION: SYSTEM-WIDE CLEANUP
# ===========================================================================

function Invoke-SystemTempCleanup {

    Write-Log "--- System Locations ---" -Level HEADER

    # Windows system temp (age 1 day — system temp cycles faster)
    Remove-TempDirectory -Path "C:\Windows\Temp" `
        -Label "Windows Temp" -Recurse -AgeDays 1

    # Prefetch — skip NTOSBOOT which is required for fast boot
    Remove-TempDirectory -Path "C:\Windows\Prefetch" `
        -Label "Prefetch" -SkipNames @("NTOSBOOT-B00DFAAD.pf") -AgeDays 30

    # CBS and DISM logs — retain last 30 days for troubleshooting
    Remove-TempDirectory -Path "C:\Windows\Logs\CBS"  -Label "CBS Logs"  -AgeDays 30
    Remove-TempDirectory -Path "C:\Windows\Logs\DISM" -Label "DISM Logs" -AgeDays 30

    # Minidumps and WER archives
    Remove-TempDirectory -Path "C:\Windows\Minidump" -Label "Minidumps" -AgeDays 14
    Remove-TempDirectory -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" `
        -Label "WER Archives" -Recurse -AgeDays 30

    # Windows Update download cache (optional)
    if ($IncludeSoftwareDistribution) {
        Write-Log "Stopping wuauserv to clear Windows Update download cache..." -Level WARN
        if (-not $DryRun) {
            Stop-Service  -Name wuauserv -Force -ErrorAction SilentlyContinue
            Remove-TempDirectory -Path "C:\Windows\SoftwareDistribution\Download" `
                -Label "WU Download Cache" -Recurse -AgeDays 0
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-Log "wuauserv restarted." -Level SUCCESS
        } else {
            Write-Log "[DRY-RUN] Would stop wuauserv and clear SoftwareDistribution\Download"
        }
    }

    # Recycle Bin (optional)
    if ($IncludeRecycleBin) {
        Write-Log "Emptying Recycle Bin for all users..."
        if (-not $DryRun) {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-Log "Recycle Bin emptied." -Level SUCCESS
            } catch {
                Write-Log "Recycle Bin error: $($_.Exception.Message)" -Level ERROR
                $Script:Stats.Errors++
            }
        } else {
            Write-Log "[DRY-RUN] Would empty Recycle Bin."
        }
    }
}

# ===========================================================================
# REGION: SYSTEM INFO SNAPSHOT
# ===========================================================================

function Get-DiskSnapshot {
    $disk = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($disk) {
        $used  = $disk.Used
        $free  = $disk.Free
        $total = $used + $free
        Write-Log ("  C:\\ — Total: {0} | Used: {1} | Free: {2} ({3:N1}% free)" -f
            (Format-Bytes $total),
            (Format-Bytes $used),
            (Format-Bytes $free),
            ($free / $total * 100))
    }
}

# ===========================================================================
# REGION: MAIN EXECUTION
# ===========================================================================

# ── Banner ──────────────────────────────────────────────────────────────────
Write-Log "========================================================" -Level HEADER
Write-Log "  WinTempCleaner v$Script:Version" -Level HEADER
Write-Log "  https://github.com/gurungsandex/WinTempCleaner" -Level HEADER
Write-Log "========================================================" -Level HEADER
Write-Log "  Host      : $env:COMPUTERNAME"
Write-Log "  OS        : $((Get-WmiObject Win32_OperatingSystem).Caption)"
Write-Log "  Run by    : $env:USERNAME"
Write-Log "  Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "  Mode      : $(if ($DryRun) { 'DRY-RUN (no files deleted)' } else { 'LIVE' })"
Write-Log "  MaxAgeDays: $MaxAgeDays"
Write-Log "  Log file  : $Script:LogFile"
Write-Log "--------------------------------------------------------" -Level HEADER

# ── Pre-cleanup disk state ───────────────────────────────────────────────────
Write-Log "Disk state BEFORE cleanup:"
Get-DiskSnapshot

# ── Enumerate user profiles ──────────────────────────────────────────────────
$systemProfiles = @("Public", "Default", "Default User", "All Users", "defaultuser0")
$userProfiles   = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction Stop |
    Where-Object {
        $_.Name -notin $systemProfiles -and
        $_.Name -notin $ExcludeUsers   -and
        (Test-Path "$($_.FullName)\AppData")
    }

Write-Log "User profiles found : $($userProfiles.Count)"
if ($ExcludeUsers.Count -gt 0) {
    Write-Log "Excluded users      : $($ExcludeUsers -join ', ')"
}
Write-Log "--------------------------------------------------------" -Level HEADER

# ── Per-user cleanup ─────────────────────────────────────────────────────────
foreach ($profile in $userProfiles) {
    try {
        Invoke-UserTempCleanup -ProfilePath $profile.FullName -Username $profile.Name
    }
    catch {
        Write-Log "FATAL: Could not process $($profile.Name) — $($_.Exception.Message)" -Level ERROR
        $Script:Stats.Errors++
    }
}

# ── System cleanup ───────────────────────────────────────────────────────────
Invoke-SystemTempCleanup

# ── Post-cleanup disk state ──────────────────────────────────────────────────
Write-Log "--------------------------------------------------------" -Level HEADER
Write-Log "Disk state AFTER cleanup:"
Get-DiskSnapshot

# ── Summary ──────────────────────────────────────────────────────────────────
$elapsed = (Get-Date) - $Script:StartTime
Write-Log "========================================================" -Level HEADER
Write-Log "  CLEANUP COMPLETE" -Level HEADER
Write-Log "========================================================" -Level HEADER
Write-Log ("  Files removed  : {0}"   -f $Script:Stats.FilesRemoved)
Write-Log ("  Space freed    : {0}"   -f (Format-Bytes $Script:Stats.BytesFreed))
Write-Log ("  Files skipped  : {0} (locked/in-use)" -f $Script:Stats.FilesSkipped)
Write-Log ("  Locations hit  : {0}"   -f $Script:Stats.Locations)
Write-Log ("  Errors         : {0}"   -f $Script:Stats.Errors)
Write-Log ("  Duration       : {0}"   -f $elapsed.ToString('mm\:ss'))
Write-Log ("  Log saved to   : {0}"   -f $Script:LogFile)
Write-Log "========================================================" -Level HEADER

if ($DryRun) {
    Write-Log "DRY-RUN complete. No files were deleted. Review the log above and re-run without -DryRun to apply." -Level WARN
}

# Exit code: 0 = success, 1 = one or more errors (SCCM/Intune detection compatible)
if ($Script:Stats.Errors -gt 0) { exit 1 } else { exit 0 }
