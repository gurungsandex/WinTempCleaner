# Changelog

All notable changes to WinTempCleaner are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.0] — 2026-03-29

### Added
- `Invoke-TempCleanup.ps1` — core multi-user cleanup engine
- `-DryRun` mode — full simulation with zero file deletion
- `-MaxAgeDays` parameter — age-based file filtering (default: 7 days)
- `-ExcludeUsers` parameter — skip specific profiles (service accounts, etc.)
- `-IncludeSoftwareDistribution` — optional Windows Update cache clear with safe wuauserv restart
- `-IncludeRecycleBin` — optional Recycle Bin empty for all users
- In-use file detection via exclusive file handle test — locked files skipped, never force-killed
- Structured UTF-8 audit log per run, named with hostname and timestamp
- Disk state snapshot (before/after) in every log
- Exit code 0/1 for SCCM and Intune deployment compatibility
- `Install-ScheduledTask.ps1` — one-command Task Scheduler setup (SYSTEM account, configurable schedule)
- `Uninstall-ScheduledTask.ps1` — clean removal with optional log purge
- `Intune-Detection.ps1` — Intune Remediation detection script (threshold-based trigger)
- MIT License
- Full README with quick-start, parameter reference, deployment matrix, and troubleshooting guide
