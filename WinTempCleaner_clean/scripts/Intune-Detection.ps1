#Requires -Version 5.1

<#
.SYNOPSIS
    Intune Remediation — Detection Script for WinTempCleaner.

.DESCRIPTION
    Checks whether the current user's %TEMP% folder exceeds a size threshold.
    Exit 1 triggers the remediation script (Invoke-TempCleanup.ps1).
    Exit 0 = compliant, no action needed.

    Deploy this as the Detection script in an Intune Remediation pair.
    Pair with Invoke-TempCleanup.ps1 as the Remediation script.

.NOTES
    Project : WinTempCleaner
    GitHub  : https://github.com/gurungsandex/WinTempCleaner
#>

$ThresholdMB = 500   # Trigger remediation if user %TEMP% exceeds this

$tempPath = "$env:LOCALAPPDATA\Temp"

if (-not (Test-Path $tempPath)) {
    Write-Output "TEMP path not found — skipping."
    exit 0
}

$sizeMB = [Math]::Round(
    (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum / 1MB, 1
)

if ($sizeMB -gt $ThresholdMB) {
    Write-Output "NON-COMPLIANT: %TEMP% = $sizeMB MB (threshold: $ThresholdMB MB)"
    exit 1
} else {
    Write-Output "COMPLIANT: %TEMP% = $sizeMB MB"
    exit 0
}
