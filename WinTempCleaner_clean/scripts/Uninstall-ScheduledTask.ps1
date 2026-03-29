#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes the WinTempCleaner scheduled task and optionally cleans up logs.

.PARAMETER RemoveLogs
    Also deletes all log files from C:\WinTempCleaner\Logs.

.EXAMPLE
    .\Uninstall-ScheduledTask.ps1

.EXAMPLE
    .\Uninstall-ScheduledTask.ps1 -RemoveLogs
#>

param([switch]$RemoveLogs)

$TaskName = "WinTempCleaner"
$LogPath  = "C:\WinTempCleaner\Logs"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[SUCCESS] Scheduled Task '$TaskName' removed." -ForegroundColor Green
} else {
    Write-Host "[INFO] Task '$TaskName' not found — nothing to remove." -ForegroundColor Yellow
}

if ($RemoveLogs -and (Test-Path $LogPath)) {
    Remove-Item -Path $LogPath -Recurse -Force
    Write-Host "[SUCCESS] Log directory removed: $LogPath" -ForegroundColor Green
}
