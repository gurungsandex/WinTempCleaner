#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs a Windows Scheduled Task to run WinTempCleaner automatically.

.DESCRIPTION
    Creates a Task Scheduler entry that runs Invoke-TempCleanup.ps1
    on a recurring schedule using the SYSTEM account (full profile access).

    Run this once after cloning the repo. To uninstall, run Uninstall-ScheduledTask.ps1.

.PARAMETER ScriptPath
    Full path to Invoke-TempCleanup.ps1.
    Defaults to the scripts\ folder relative to this installer.

.PARAMETER TriggerTime
    Time of day to run the task. Default: 02:00 (2 AM).

.PARAMETER DaysOfWeek
    Days to run. Default: Monday, Wednesday, Friday.

.PARAMETER MaxAgeDays
    Passed through to the cleanup script. Default: 7.

.PARAMETER ExcludeUsers
    Comma-separated usernames to skip. Passed to the cleanup script.

.EXAMPLE
    # Default schedule: Mon/Wed/Fri at 2 AM
    .\Install-ScheduledTask.ps1

.EXAMPLE
    # Daily at midnight, 14-day filter
    .\Install-ScheduledTask.ps1 -TriggerTime "00:00" -DaysOfWeek "Daily" -MaxAgeDays 14

.NOTES
    Project : WinTempCleaner
    GitHub  : https://github.com/gurungsandex/WinTempCleaner
#>

param(
    [string]  $ScriptPath    = (Join-Path $PSScriptRoot "Invoke-TempCleanup.ps1"),
    [string]  $TriggerTime   = "02:00",
    [string[]]$DaysOfWeek    = @("Monday","Wednesday","Friday"),
    [int]     $MaxAgeDays    = 7,
    [string[]]$ExcludeUsers  = @()
)

$TaskName = "WinTempCleaner"
$TaskDesc = "Automated temp file cleanup — WinTempCleaner v1.0.0. Managed by IT."

# ── Validate script path ─────────────────────────────────────────────────────
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script not found: $ScriptPath`nClone the full repo and run from within the scripts\ folder."
    exit 1
}

# ── Build argument string ────────────────────────────────────────────────────
$args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -MaxAgeDays $MaxAgeDays"
if ($ExcludeUsers.Count -gt 0) {
    $args += " -ExcludeUsers " + ($ExcludeUsers | ForEach-Object { "`"$_`"" }) -join ","
}

# ── Build trigger ────────────────────────────────────────────────────────────
$triggerParams = @{ At = $TriggerTime }
if ($DaysOfWeek -eq "Daily") {
    $trigger = New-ScheduledTaskTrigger -Daily @triggerParams
} else {
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek @triggerParams
}

# ── Action runs as SYSTEM (access to all user profiles) ─────────────────────
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 1 `
    -RestartInterval (New-TimeSpan -Minutes 30) `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

# ── Remove existing task if present ─────────────────────────────────────────
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Removing existing task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# ── Register the task ────────────────────────────────────────────────────────
try {
    Register-ScheduledTask `
        -TaskName   $TaskName `
        -Description $TaskDesc `
        -Action     $action `
        -Trigger    $trigger `
        -Principal  $principal `
        -Settings   $settings `
        -Force | Out-Null

    Write-Host "`n[SUCCESS] Scheduled Task '$TaskName' installed." -ForegroundColor Green
    Write-Host "  Script  : $ScriptPath"
    Write-Host "  Schedule: $($DaysOfWeek -join '/') at $TriggerTime"
    Write-Host "  Account : SYSTEM"
    Write-Host "`nVerify in Task Scheduler > Task Scheduler Library > WinTempCleaner"
}
catch {
    Write-Error "Failed to register task: $($_.Exception.Message)"
    exit 1
}
