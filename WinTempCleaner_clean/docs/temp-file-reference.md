# Windows Temp File Location Reference

This document provides a detailed technical breakdown of every temp file location that WinTempCleaner targets. Use it for auditing, policy documentation, or understanding what the script does under the hood.

---

## Per-User Locations

These paths exist once per user profile under `C:\Users\<username>\`. They are resolved by enumerating profiles rather than using the `%TEMP%` environment variable, which only resolves for the currently logged-in user.

---

### `AppData\Local\Temp` — Primary User Temp Folder

**Full path:** `C:\Users\<username>\AppData\Local\Temp`
**Environment variable:** `%TEMP%` / `%TMP%` (user-scoped via HKCU\Environment)

**What accumulates:**
- Installer packages (.msi, .msp) — created during software installs and rarely cleaned on failure
- Microsoft Office lock files (`~$filename.docx`) — persist after crashes
- Application scratch files — virtually every Win32 app writes here during normal operation
- PDF reader extraction artifacts — Acrobat, Foxit, etc.
- Windows Installer patch caches
- Browser download staging files (incomplete downloads)

**Created by:** Any application running under that user account

**Safe to delete:** Yes — with a minimum age filter of 7 days. Files actively in use will be detected by the exclusive handle test and skipped automatically.

**Accumulation rate:** 200–800 MB/month for a typical office knowledge worker. Up to 3 GB/month for developers or users running frequent installers.

**Risk if not cleaned:** HIGH — primary driver of disk consumption on managed endpoints.

---

### `AppData\Local\Microsoft\Windows\INetCache`

**Full path:** `C:\Users\<username>\AppData\Local\Microsoft\Windows\INetCache`

**What accumulates:**
- Cached web pages, images, scripts, and stylesheets from Internet Explorer and Legacy Microsoft Edge
- Offline copies of Outlook Web Access sessions
- SharePoint page cache artifacts

**Created by:** Internet Explorer rendering engine, Legacy Edge

**Safe to delete:** Yes — cache rebuilds automatically on next browser launch.

**Accumulation rate:** 100–600 MB/month for users accessing web-based applications.

**Risk if not cleaned:** LOW — performance impact is moderate; primary concern is stale cached content causing display issues in web apps.

---

### `AppData\Roaming\Microsoft\Windows\Recent`

**Full path:** `C:\Users\<username>\AppData\Roaming\Microsoft\Windows\Recent`

**What accumulates:**
- `.lnk` shortcut files pointing to recently opened documents, folders, and applications
- These are not the actual files — only the shortcuts

**Created by:** Windows Shell (explorer.exe) on every file open

**Safe to delete:** Yes — the Recent Items list in File Explorer and Start Menu will be cleared. No actual files are affected.

**Accumulation rate:** Low — typically hundreds of small .lnk files, under 10 MB total.

**Risk if not cleaned:** LOW.

---

### `AppData\Local\Microsoft\Windows\Explorer`

**Full path:** `C:\Users\<username>\AppData\Local\Microsoft\Windows\Explorer`

**What accumulates:**
- `thumbcache_*.db` — cached thumbnail images for files viewed in File Explorer
- These databases grow with each new folder browsed

**Created by:** Windows Explorer (explorer.exe)

**Safe to delete:** Yes — thumbnails regenerate on next folder view.

**Accumulation rate:** 20–200 MB depending on how many image/video folders the user browses.

**Risk if not cleaned:** LOW — occasional cause of "thumbnail not showing" bugs when the cache becomes corrupt.

---

### `AppData\Local\Microsoft\Teams\tmp`

**Full path:** `C:\Users\<username>\AppData\Local\Microsoft\Teams\tmp`

**What accumulates:**
- Teams meeting recording fragments
- File transfer staging artifacts
- Crash residue from the Electron-based Teams client

**Created by:** Microsoft Teams desktop client

**Safe to delete:** Yes.

**Accumulation rate:** Highly variable — 50 MB to 2 GB/month depending on meeting load and file sharing activity.

**Risk if not cleaned:** MEDIUM in high-Teams-usage environments.

---

### `AppData\Local\Google\Chrome\User Data\Default\Cache`

**Full path:** `C:\Users\<username>\AppData\Local\Google\Chrome\User Data\Default\Cache`

**What accumulates:**
- Cached web resources (HTML, CSS, JavaScript, images, fonts)
- Chrome manages this cache automatically but does not aggressively purge old entries

**Created by:** Google Chrome

**Safe to delete:** Yes — cache rebuilds on next browser launch. Users may notice slightly slower initial page loads for recently visited sites.

**Accumulation rate:** 200–500 MB depending on browsing activity.

**Risk if not cleaned:** LOW.

---

### `AppData\Local\Mozilla\Firefox\Profiles`

**Full path:** `C:\Users\<username>\AppData\Local\Mozilla\Firefox\Profiles`

**What accumulates:**
- Disk cache under each profile's `cache2\` subfolder
- Session restore files

**Created by:** Mozilla Firefox

**Safe to delete:** Cache subfolder only — WinTempCleaner targets files by age, not entire profile directories. Firefox profile data (bookmarks, passwords, extensions) is stored in `AppData\Roaming`, not here.

**Accumulation rate:** 100–400 MB.

**Risk if not cleaned:** LOW.

---

### `AppData\Local\CrashDumps`

**Full path:** `C:\Users\<username>\AppData\Local\CrashDumps`

**What accumulates:**
- `.dmp` files — full or mini memory dumps from application crashes
- These are binary snapshots of process memory at the time of the crash

**Created by:** Windows Error Reporting (WER) when a user-space application crashes

**Safe to delete:** Yes — after 14 days, crash dumps are unlikely to be needed for active debugging.

**HIPAA / Compliance note:** Crash dumps can contain fragments of whatever was in memory at crash time — this may include ePHI if a clinical application was running. Regular cleanup is a direct compensating control.

**Accumulation rate:** Low in stable environments; can spike significantly during application instability periods.

**Risk if not cleaned:** MEDIUM (compliance) / LOW (performance).

---

## System-Wide Locations

These locations require Administrator access and exist once per machine, not per user.

---

### `C:\Windows\Temp`

**What accumulates:**
- Temp files written by Windows services running as SYSTEM
- Print spooler staging files
- Windows Update extraction artifacts (staging before move to SoftwareDistribution)
- DISM and servicing temp files during patch application

**Created by:** SYSTEM account, Windows services, LocalSystem services

**Safe to delete:** Yes — WinTempCleaner uses a 1-day age filter here (shorter than user temp) because system temp cycles faster and locked files are still protected by the handle check.

**Risk if not cleaned:** MEDIUM.

---

### `C:\Windows\Prefetch`

**What accumulates:**
- `.pf` trace files — one per application launch, recording which disk sectors were read at startup
- Used by the Superfetch/SysMain service to preload application data into RAM before launch

**Created by:** SysMain (Superfetch) service

**Safe to delete:** Yes — with one exception: `NTOSBOOT-B00DFAAD.pf` must be preserved. WinTempCleaner skips this file automatically.

**Note:** Deleting prefetch files causes a one-time slowdown on next launch of each application as the trace files rebuild. This is temporary.

**Risk if not cleaned:** LOW — Prefetch is capped at 128 files and self-manages reasonably well.

---

### `C:\Windows\Logs\CBS` and `C:\Windows\Logs\DISM`

**What accumulates:**
- CBS (Component-Based Servicing) logs from Windows Update and feature installations
- DISM operation logs
- These grow significantly on machines that receive frequent updates

**Created by:** Windows Update Agent, DISM, SFC

**Safe to delete:** Files older than 30 days. Retain recent logs for troubleshooting update failures.

**Risk if not cleaned:** LOW — but CBS logs specifically can grow very large (several GB) on Server machines with frequent updates.

---

### `C:\Windows\Minidump`

**What accumulates:**
- BSOD (Blue Screen of Death) minidump files
- Small memory snapshots captured when the kernel crashes

**Created by:** Windows kernel on system crash

**Safe to delete:** Files older than 14 days. If a machine is actively BSODing, retain these for debugging.

**Risk if not cleaned:** LOW.

---

### `C:\ProgramData\Microsoft\Windows\WER\ReportArchive`

**What accumulates:**
- Archived Windows Error Reporting packages — application and kernel crash reports that have already been submitted to Microsoft (or suppressed)

**Created by:** Windows Error Reporting service

**Safe to delete:** Files older than 30 days.

**Risk if not cleaned:** LOW.

---

### `C:\Windows\SoftwareDistribution\Download` *(optional)*

**What accumulates:**
- Downloaded Windows Update packages — `.cab` and `.psf` files
- Includes both pending updates (not yet installed) and already-applied update packages

**Created by:** Windows Update Agent (wuauserv)

**Safe to delete:** Yes — but only after stopping the `wuauserv` service. WinTempCleaner handles this automatically when `-IncludeSoftwareDistribution` is specified. Windows Update will re-download required packages on the next update cycle.

**Accumulation rate:** 500 MB–4 GB per major patch cycle. Very large on machines that have missed several patch cycles.

**Risk if not cleaned:** HIGH — this is one of the single largest contributors to disk consumption on long-running endpoints, particularly in environments where update downloads are cached but installs are deferred.

---

## Why %TEMP% Is Per-User

The environment variables `%TEMP%` and `%TMP%` are resolved in the context of the current user session. Windows looks them up in `HKEY_CURRENT_USER\Environment`, where they point to `%USERPROFILE%\AppData\Local\Temp`.

This means:
- Running a script that cleans `%TEMP%` only cleans the folder of the account running the script
- To clean all users, you must enumerate `C:\Users`, construct each profile's temp path manually, and process them independently
- Service accounts and the SYSTEM account resolve `%TEMP%` to `C:\Windows\Temp`, not a user profile path

WinTempCleaner handles all of this by enumerating `C:\Users` directly and excluding Default/Public/system profile folders.
