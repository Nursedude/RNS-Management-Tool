# Reticulum on Windows 11: Quick Start (no management tool needed)

This page replaces the PowerShell half of RNS Management Tool, which is archived. Everything
the tool did on Windows can be done with upstream packages and a few PowerShell commands.
The Reticulum packages (`rns`, `lxmf`, `nomadnet`) are pure Python and run natively on
Windows. `rnsd`, `rnstatus`, `rnodeconf` and the other `rn*` utilities come with `rns`.

All commands below are for **PowerShell** (Windows Terminal).

---

## 1. Install Python (and avoid the Store trap)

```powershell
winget install -e --id Python.Python.3.12
```

Open a **new** terminal afterwards. Use the `py` launcher for everything below; it's
installed with python.org Python and always finds the real interpreter.

> **The Microsoft Store trap:** on a fresh Windows, typing `python` opens the Microsoft Store
> or prints "Python was not found". That is a placeholder alias, not Python. Either use `py`
> (recommended), or turn the aliases off under **Settings → Apps → Advanced app settings →
> App execution aliases** by switching off `python.exe` and `python3.exe`.

Check it:

```powershell
py --version        # 3.11+ if you also want MeshChatX
```

## 2. Install Reticulum, LXMF and NomadNet

```powershell
py -m pip install --upgrade rns lxmf nomadnet
```

### Put the commands on PATH

pip puts `rnsd.exe`, `rnstatus.exe`, `rnodeconf.exe` and the rest into a `Scripts` folder
that often isn't on PATH, so you get `rnsd : The term 'rnsd' is not recognized`. Find the
folder:

```powershell
py -c "import sysconfig; print(sysconfig.get_path('scripts'))"             # normal install
py -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))"  # if pip said "Defaulting to user installation"
```

Add it to **your user** PATH, then open a new terminal:

```powershell
$dir = 'C:\...\Scripts'     # paste the folder printed above
$u = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', "$u;$dir", 'User')
```

## 3. First run

```powershell
rnsd          # first run creates %USERPROFILE%\.reticulum\config. Press Ctrl+C once it's up.
```

- Config: `%USERPROFILE%\.reticulum\config`
- Your identity and keys: `%USERPROFILE%\.reticulum\storage\`. **This is private; keep it out
  of shares and public backups.**
- Log (when run with `-s`): `%USERPROFILE%\.reticulum\logfile`

> **There is no `rnsd --daemon` flag.** rnsd rejects it with `unrecognized arguments`. Its
> real options are `-s/--service` (log to file), `-v`, `-q`, `--config DIR`, `-i`,
> `--exampleconfig` and `--version`. The old management tool used `--daemon`, which is why
> its Start/Auto-start never worked.

Check that it's running (in a second terminal while `rnsd` runs):

```powershell
rnstatus
```

## 4. Start rnsd automatically at logon

This runs rnsd through `pythonw` (no console window) as a Scheduled Task for your user:

```powershell
$pyw = py -c "import sys, os; print(os.path.join(os.path.dirname(sys.executable), 'pythonw.exe'))"
$action   = New-ScheduledTaskAction -Execute $pyw -Argument '-m RNS.Utilities.rnsd -s'
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
Register-ScheduledTask -TaskName 'Reticulum rnsd' -Action $action -Trigger $trigger -Settings $settings
Start-ScheduledTask   -TaskName 'Reticulum rnsd'
```

- `-ExecutionTimeLimit (New-TimeSpan -Seconds 0)` matters. Without it, Windows kills the
  task after 72 hours.
- If `Register-ScheduledTask` says *Access is denied*, re-run it in an elevated PowerShell.
- To stop it: `Stop-ScheduledTask 'Reticulum rnsd'`. To remove it:
  `Unregister-ScheduledTask 'Reticulum rnsd' -Confirm:$false`.

While rnsd runs, it is the **shared instance**: NomadNet, MeshChatX, Sideband and the `rn*`
tools connect to it automatically, so start rnsd first.

### Remove the old tool's tasks

If you ever enabled auto-start in RNS Management Tool, delete its tasks. The rnsd one never
worked because of the `--daemon` flag.

```powershell
Unregister-ScheduledTask -TaskName 'RNS_rnsd_autostart'      -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'RNS_meshchatx_autostart' -Confirm:$false -ErrorAction SilentlyContinue
```

## 5. RNode (LoRa) on a COM port

1. Plug the RNode in. If no COM port appears, install the USB-serial driver for the board
   (usually Silicon Labs CP210x or WCH CH34x).
2. Find the port:
   ```powershell
   [System.IO.Ports.SerialPort]::GetPortNames()
   ```
3. Flash or update firmware. Both are interactive and ask for the port:
   ```powershell
   rnodeconf --autoinstall        # new board
   rnodeconf COM5 --update        # already-flashed RNode
   rnodeconf COM5 --info          # check it
   ```
   Don't use `rnodeconf --rom` unless you mean it: it rewrites the device EEPROM.
   (The old tool's "Update bootloader" option ran exactly that.)
4. Add the interface to `%USERPROFILE%\.reticulum\config` under `[interfaces]`, then restart
   rnsd. The radio settings must **match the other RNodes you want to reach** and be legal
   in your region. The values below are only an example shape:
   ```ini
     [[RNode LoRa Interface]]
       type = RNodeInterface
       enabled = yes
       port = COM5
       frequency = 914875000
       bandwidth = 125000
       txpower = 7
       spreadingfactor = 8
       codingrate = 5
   ```
   Run `rnsd --exampleconfig` for every option, documented.

## 6. Apps

| App | Install | Run |
|---|---|---|
| NomadNet | included in step 2 | `nomadnet` (in Windows Terminal) |
| MeshChatX (Python 3.11+) | `py -m pip install --upgrade reticulum-meshchatx` | `meshchatx` (see `meshchatx --help`) |
| Sideband | desktop builds on [Sideband releases](https://github.com/markqvist/Sideband/releases), or `py -m pip install sbapp` | see the Sideband README |

## 7. Backup and restore

Stop rnsd first, so nothing is written mid-copy:

```powershell
Stop-ScheduledTask 'Reticulum rnsd'
$zip = "$HOME\reticulum-backup-$(Get-Date -Format yyyyMMdd-HHmm).zip"
Compress-Archive -Path "$HOME\.reticulum", "$HOME\.nomadnetwork" -DestinationPath $zip   # drop paths you don't have
Start-ScheduledTask 'Reticulum rnsd'
```

Restore. This puts the folders back under your home directory and overwrites what's there:

```powershell
Stop-ScheduledTask 'Reticulum rnsd'
Expand-Archive -Path 'C:\path\to\reticulum-backup-YYYYMMDD-HHMM.zip' -DestinationPath $HOME -Force
Start-ScheduledTask 'Reticulum rnsd'
```

The zip contains your private identity. Store it like a password.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `python` opens the Microsoft Store / "Python was not found" | Use `py`, or disable the App execution aliases (step 1) |
| `rnsd` / `rnstatus` "is not recognized" | The Scripts folder isn't on PATH (step 2); open a new terminal after changing PATH |
| `rnsd: error: unrecognized arguments: --daemon` | There is no `--daemon`; use `rnsd` or `rnsd -s` |
| `rnstatus` can't find a shared instance | rnsd isn't running. `Get-ScheduledTask 'Reticulum rnsd'`, check `%USERPROFILE%\.reticulum\logfile` |
| RNode port busy / access denied | Another program (a second rnsd, a serial monitor, Meshtastic app) holds the COM port |
| rnsd stops by itself after ~3 days | The task was created without `-ExecutionTimeLimit (New-TimeSpan -Seconds 0)`; re-create it (step 4) |

Upstream docs: <https://reticulum.network/manual/>
