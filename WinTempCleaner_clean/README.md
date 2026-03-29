# 🧹 WinTempCleaner

**Production-grade Windows temp file cleanup for IT administrators and sysadmins.**

WinTempCleaner is a fully documented PowerShell tool that safely removes temporary files across all user profiles and system locations on any Windows machine. It is designed to run unattended via Task Scheduler, Intune, or SCCM — with full audit logging, dry-run support, and locked-file protection built in.

> Built and tested by Sandesh Gurung — IT Support Engineer with experience managing 1,000+ endpoints in HIPAA-regulated environments.

---

## Why this exists

Windows never reliably cleans its own temp files. After 12 months without intervention, an unmanaged endpoint can accumulate **12–18 GB** of temp bloat — degrading boot times, increasing disk I/O, and in regulated environments, leaving residual fragments of sensitive data on disk.

WinTempCleaner solves this with a single, auditable PowerShell script that is safe to deploy fleet-wide from day one.

---

## What it cleans

| Location | What Accumulates | Age Filter |
|---|---|---|
| `%USERPROFILE%\AppData\Local\Temp` | Installer residue, app scratch files, Office lock files | 7 days (default) |
| `C:\Windows\Temp` | System & service temp files | 1 day |
| `C:\Windows\Prefetch` | App launch traces (preserves NTOSBOOT) | 30 days |
| `C:\Windows\Logs\CBS` & `DISM` | Windows Update component logs | 30 days |
| `C:\Windows\Minidump` | Crash minidump files | 14 days |
| `INetCache` (per user) | IE / Legacy Edge browser cache | 7 days |
| Teams `tmp` (per user) | Microsoft Teams temporary files | 7 days |
| Chrome & Firefox cache (per user) | Browser disk cache | 7 days |
| Crash dumps (per user) | Application crash dumps | 7 days |
| Recent Items (per user) | Shortcut (.lnk) files | 7 days |
| `SoftwareDistribution\Download` | Windows Update packages *(optional)* | All |
| Recycle Bin | Deleted files awaiting purge *(optional)* | All |

**What it never touches:**
- Files in active use (in-use detection via exclusive file handle)
- Files newer than `MaxAgeDays`
- `NTOSBOOT-B00DFAAD.pf` (required for fast boot)
- Profiles listed in `-ExcludeUsers`
- Default / Public / system profiles

---

## Requirements

| Requirement | Detail |
|---|---|
| OS | Windows 10 (21H2+), Windows 11, Server 2019, Server 2022 |
| PowerShell | 5.1 or later (built into all modern Windows) |
| Privileges | **Administrator** required — script will not run otherwise |
| Dependencies | None — no modules, no installs |

---

## Quick Start

### 1. Clone the repo

```powershell
git clone https://github.com/gurungsandex/WinTempCleaner.git
cd WinTempCleaner
```

Or download the ZIP from GitHub → **Code → Download ZIP**, then extract.

---

### 2. Dry-run first (always)

Open PowerShell **as Administrator** and run:

```powershell
.\scripts\Invoke-TempCleanup.ps1 -DryRun
```

This scans every location and reports exactly what *would* be deleted — zero files are touched. Review the output or the log file written to `C:\WinTempCleaner\Logs\`.

---

### 3. Run the cleanup

Once you're satisfied with the dry-run report:

```powershell
.\scripts\Invoke-TempCleanup.ps1
```

That's it. The script will:
- Enumerate all real user profiles on the machine
- Clean temp locations for each profile
- Clean system-wide locations
- Write a full audit log with before/after disk stats
- Print a summary to the console

---

## All Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-DryRun` | Switch | Off | Simulate only — no files deleted |
| `-LogPath` | String | `C:\WinTempCleaner\Logs` | Where audit logs are written |
| `-MaxAgeDays` | Int | `7` | Only delete files older than this |
| `-ExcludeUsers` | String[] | `@()` | Usernames to skip entirely |
| `-IncludeSoftwareDistribution` | Switch | Off | Clear Windows Update download cache |
| `-IncludeRecycleBin` | Switch | Off | Empty Recycle Bin for all users |

### Usage examples

```powershell
# Dry-run — no deletions, full report
.\scripts\Invoke-TempCleanup.ps1 -DryRun

# Standard run — default 7-day filter
.\scripts\Invoke-TempCleanup.ps1

# Skip service accounts
.\scripts\Invoke-TempCleanup.ps1 -ExcludeUsers "svc_backup","svc_sql"

# Conservative — only clean files older than 2 weeks
.\scripts\Invoke-TempCleanup.ps1 -MaxAgeDays 14

# Full cleanup including Windows Update cache and Recycle Bin
.\scripts\Invoke-TempCleanup.ps1 -IncludeSoftwareDistribution -IncludeRecycleBin

# Custom log path
.\scripts\Invoke-TempCleanup.ps1 -LogPath "D:\IT\Logs"
```

---

## Automated Scheduling (Recommended)

For ongoing maintenance, install a Scheduled Task that runs the cleanup automatically:

```powershell
# Default: runs Mon/Wed/Fri at 2 AM as SYSTEM
.\scripts\Install-ScheduledTask.ps1

# Custom: daily at midnight, 14-day filter, skip a service account
.\scripts\Install-ScheduledTask.ps1 `
    -TriggerTime "00:00" `
    -DaysOfWeek "Daily" `
    -MaxAgeDays 14 `
    -ExcludeUsers "svc_backup"
```

The task runs as the **SYSTEM** account so it can access all user profiles on the machine.

To remove the task:

```powershell
# Remove task only
.\scripts\Uninstall-ScheduledTask.ps1

# Remove task AND delete all log files
.\scripts\Uninstall-ScheduledTask.ps1 -RemoveLogs
```

---

## Enterprise Deployment

### Microsoft Intune (Remediation Scripts)

Use the provided detection + remediation pair:

| Role | Script |
|---|---|
| Detection | `scripts/Intune-Detection.ps1` |
| Remediation | `scripts/Invoke-TempCleanup.ps1` |

The detection script triggers remediation when any user's `%TEMP%` exceeds **500 MB** (configurable via `$ThresholdMB` inside the file). Configure the Remediation in Intune → **Devices → Scripts and remediations → Remediations**.

### SCCM / MECM

Deploy as a package or script with the following command line:

```
PowerShell.exe -ExecutionPolicy Bypass -NonInteractive -NoProfile -File ".\scripts\Invoke-TempCleanup.ps1" -MaxAgeDays 7 -ExcludeUsers "svc_sccm"
```

Success return code: `0` | Error return code: `1`

### Execution Policy

If your environment enforces `AllSigned`, sign the script before deploying:

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
Set-AuthenticodeSignature -FilePath .\scripts\Invoke-TempCleanup.ps1 -Certificate $cert
```

---

## Audit Logs

Every run writes a timestamped log to `C:\WinTempCleaner\Logs\` (or your custom `-LogPath`):

```
WinTempCleaner_HOSTNAME_20260329_020015.log
```

Log entries include:
- Machine name, OS, running user, and mode (LIVE or DRY-RUN)
- Disk state before and after cleanup
- Every file deleted (path + size) or skipped (path + reason)
- Per-location summary (files removed, bytes freed)
- Final totals and duration

Log files are excluded from Git via `.gitignore`. In regulated environments (HIPAA, SOC 2), forward logs to your SIEM:

```ini
# Wazuh agent — ossec.conf
<localfile>
  <log_format>syslog</log_format>
  <location>C:\WinTempCleaner\Logs\*.log</location>
</localfile>

# Splunk Universal Forwarder — inputs.conf
[monitor://C:\WinTempCleaner\Logs\]
index = endpoint_events
sourcetype = wintempcleanup
```

---

## Scheduling Recommendations

| Environment | Frequency | Window |
|---|---|---|
| Standard workstation | Weekly | Tue/Thu 2 AM |
| Developer / power user | 3× per week | Mon/Wed/Fri 1 AM |
| Shared / kiosk machine | Daily | Midnight |
| RDS / VDI session host | On user logoff (GPO) | Per-session |
| Low-storage endpoint (<128 GB SSD) | 2× per week | Tue/Fri 2 AM |

---

## Safety Notes

- **Always dry-run first** on any new machine or after an OS update
- **Never set `-MaxAgeDays 0`** for user `%TEMP%` — active application files can be deleted
- **Never clean during active user sessions** — schedule for off-hours
- **Do not remove `NTOSBOOT-B00DFAAD.pf`** — the script preserves this automatically
- **`-IncludeSoftwareDistribution`** is safe: the script stops `wuauserv` before clearing and restarts it after. Do not combine with manual Windows Update operations running at the same time.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| 0 bytes freed despite known bloat | Script ran without admin | Always open PowerShell as Administrator |
| High "files skipped (locked)" count | AV scanning temp files during cleanup | Add temp paths to AV exclusion list; shift schedule to post-scan window |
| Windows Update fails after run | `SoftwareDistribution` cleared while service running | Use `-IncludeSoftwareDistribution` switch (handles service stop/start automatically) |
| Log directory not created | Disk full or path permission issue | Verify SYSTEM has write access to `C:\WinTempCleaner\Logs` |
| Exit code 1 on every run | Persistent locked files (backup agent, AV) | Check log for ERROR entries; adjust exclusions or schedule timing |
| Script blocked by execution policy | `AllSigned` or `Restricted` policy | See Execution Policy section above |

---

## Project Structure

```
WinTempCleaner/
├── scripts/
│   ├── Invoke-TempCleanup.ps1       # Main cleanup script
│   ├── Install-ScheduledTask.ps1    # Task Scheduler setup
│   ├── Uninstall-ScheduledTask.ps1  # Clean removal
│   └── Intune-Detection.ps1         # Intune Remediation detection script
├── logs/
│   └── README.md                    # Placeholder (logs are gitignored)
├── docs/
│   └── temp-file-reference.md       # Deep-dive: what each location contains
├── .gitignore
├── CHANGELOG.md
├── LICENSE                          # MIT
└── README.md
```

---

## Contributing

Pull requests are welcome. Please:
- Keep all scripts compatible with PowerShell 5.1
- Include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) on any new functions
- Test with `-DryRun` before submitting changes that touch file deletion logic
- Update `CHANGELOG.md` with your changes

---

## License

MIT — see [LICENSE](LICENSE) for full terms.

---

## Author

**Sandesh Gurung**
IT Support Engineer · Cybersecurity Practitioner

- GitHub: [@gurungsandex](https://github.com/gurungsandex)
- LinkedIn: [linkedin.com/in/sandeshgrg](https://linkedin.com/in/sandeshgrg)
- Portfolio: [gurungsandex.com.np](https://gurungsandex.com.np)
