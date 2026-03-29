# 🧹 WinTempCleaner

⚠️ Work in Progress

This project is still actively being developed and improved.

- Use this script at your own risk
- The author is not responsible for any data loss, system issues,
  or unintended deletions that may occur
- Always run with -DryRun first to preview what will be deleted

Found a bug or have a suggestion? Contributions are welcome!
- 🐛 Open an Issue to report a bug or error
- 💡 Start a Discussion to suggest improvements
- 🔧 Submit a Pull Request if you'd like to contribute a fix

.
.
.

# Free up disk space and improve Windows performance by cleaning temporary files.**

WinTempCleaner is a PowerShell script that safely removes junk files that Windows leaves behind over time — installer leftovers, browser cache, crash dumps, system logs, and more. No installs required. Works on any Windows 10 or Windows 11 PC.

---

## What It Cleans

| Location | What Gets Removed |
|---|---|
| User Temp folder | Installer leftovers, app scratch files |
| Browser Cache | Chrome, Firefox, Edge cached files |
| Windows Temp | System temporary files |
| Microsoft Teams | Temporary meeting and transfer files |
| Crash Dumps | Application crash files |
| Prefetch | Old app launch traces |
| CBS / DISM Logs | Old Windows Update logs |
| Windows Update Cache | Downloaded update packages *(optional)* |
| Recycle Bin | Files waiting to be permanently deleted *(optional)* |

**Safety built in:**
- ✅ Skips files currently in use by Windows
- ✅ Skips files newer than 7 days
- ✅ Preview mode — see what will be deleted before anything is removed
- ✅ Saves a log file after every run

---

## How to Download

1. Click the green **`<> Code`** button at the top of this page
2. Click **Download ZIP**
3. Open your **Downloads** folder
4. Right-click the ZIP → click **Extract All** → click **Extract**

You will now have a folder called **`WinTempCleaner-main`** in your Downloads.

---

## How to Run

### Step 1 — Open PowerShell as Administrator

> ⚠️ Must be run as Administrator or it will not work.

- Press `Windows key`
- Type `PowerShell`
- Right-click **Windows PowerShell**
- Click **Run as administrator**
- Click **Yes**

---

### Step 2 — Paste this command and press Enter

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

This is a one-time step that allows the script to run on your PC.

---

### Step 3 — Run a Preview First (Recommended)

See what will be cleaned before anything is deleted:

```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1" -DryRun
```

---

### Step 4 — Run the Actual Cleanup

```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1"
```

Done. The script will print a summary showing how many files were removed and how much space was freed.

---

## Optional — Clean Even More Space

**Also clear Windows Update cache:**
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1" -IncludeSoftwareDistribution
```

**Also empty the Recycle Bin:**
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1" -IncludeRecycleBin
```

**Maximum cleanup — everything at once:**
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1" -IncludeSoftwareDistribution -IncludeRecycleBin
```

---

## Where Is the Log File?

After every run a log file is saved to:

```
C:\WinTempCleaner\Logs\
```

Open it with Notepad to see a full list of everything that was cleaned.

---

## Troubleshooting

**"Execution of scripts is disabled"**
Run this in your Admin PowerShell window then try again:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

**"Access is denied"**
Make sure you opened PowerShell as **Administrator** (right-click → Run as administrator).

**Script ran but freed 0 bytes**
Your files may all be newer than 7 days. Try:
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\WinTempCleaner-main\WinTempCleaner.ps1" -MaxAgeDays 1
```

**"The system cannot find the path specified"**
You may have extracted the ZIP to a different location. Open File Explorer, find where `WinTempCleaner.ps1` is, and replace the path in the command with its actual location.

---

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 (already installed on all modern Windows PCs)
- Administrator access

---

## License

MIT — free to use, share, and modify.

---

**Made by [Sandesh Gurung](https://github.com/gurungsandex)**
[LinkedIn](https://linkedin.com/in/sandeshgrg) · [Portfolio](https://gurungsandex.com.np)
