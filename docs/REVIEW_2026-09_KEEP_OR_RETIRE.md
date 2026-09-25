# RNS-Management-Tool — Keep or Retire? (2026-09-25)

> Review of GitHub `main` @ `3099cee` (2026-06-20, PR #88).
> Tooling actually run:
> - `scripts/lint.sh`
> - ShellCheck
> - bats: **498/498** pass
> - `smoke_test.sh`: 103 pass
> - Pester on pwsh 7.4.6: **359/359** pass
> - PSScriptAnalyzer
>
> The RNS CLI flags the tool relies on were run against real `rns` 1.5.4. Nothing ran on
> real Windows; the checklist in §5 covers that on the Win 11 box.

## TL;DR

**Recommendation: retire it.** Replace it with a one-page Windows how-to, *after*
a 20-minute confirm on the Win 11 box (§5).

The reason to keep it was "only ecosystem tool with a Windows version". The Windows
features that go beyond `pip install` don't work:

- **rnsd service:** rnsd can't start. The June keep-alive task launches a command that
  exits at once.
- **Restore:** restore doesn't restore.
- **RNode submenu:** mostly invalid flags, and one mislabeled option writes to the
  device's EEPROM.

Everything else is a thin wrapper over `pip` and the RNS command-line tools, which
run natively on Windows. On Linux/Pi, MeshForge already covers the tool's install,
service, config, diagnostics and backup work.

The test suites are all green because they mock `rnsd`/`rnodeconf` or grep source
text, so none of the problems below show up in CI.

## 1. Verified findings

| # | Sev | Finding | Where |
|---|-----|---------|-------|
| 1 | **High** | `rnsd --daemon` is not a valid flag. rnsd 1.5.4 prints `unrecognized arguments` and exits 2 (only `-s/--service` exists). Start/restart fails on **both** platforms. The #86 Windows keep-alive Scheduled Task runs the same bad command at every logon. Six help texts tell users to run it too. The flag was introduced 2026-03-06 (6e193d8). | `pwsh/services.ps1:71,294`; `lib/services.sh:18,72,859`; help text in `advanced.sh`, `utils.sh`, `config.sh`, `diagnostics.sh`, `ui.sh` |
| 2 | **High** | Windows restore/import copies each folder onto an existing one, producing `~\.reticulum\.reticulum`. The live config is unchanged, but the tool reports "restored successfully". An empty selection picks the oldest backup. | `pwsh/backup.ps1:72,84,298` |
| 3 | **High** | `retry_with_backoff` always returns 0 on "permanent" errors: `local rc=$?` is set after the `if` closes, the same bug #82 fixed elsewhere. Main-menu option 4 never calls `check_pip`, so the install runs `timeout ''` and still reports **success**. Every pip install through this helper can hide a failure. | `lib/utils.sh:149-165`; `rns_management_tool.sh:219-222` |
| 4 | Med–High | The RNode menu uses flags rnodeconf doesn't have: `--list` (unrecognized), `--eeprom` (ambiguous), `--console` (unrecognized, and reworked in #87). The option labeled "Update bootloader" runs `--rom`, which **bootstraps the device EEPROM**. The radio-parameter config omits `-T`, so it does nothing, and it asks for bandwidth in kHz when rnodeconf wants Hz. | `lib/rnode.sh:59,189,205,226`; `pwsh/rnode.ps1:104-163,186,225,250` |
| 5 | Med | The #85 doctor, when run under sudo, compares `~/.reticulum`'s owner against `root` and suggests `sudo chown -R root:root`. That creates the exact problem it's meant to catch. It should use `${SUDO_USER:-$(id -un)}`. | `lib/diagnostics.sh` (`diag_rns_doctor`) |
| 6 | Med | Windows Python detection never tries the `py` launcher and treats the Microsoft Store stub's "Python was not found" message as success. The doctor flags every WindowsApps Python as the stub, including a real Store Python, which is the install route the tool itself recommends. | `pwsh/environment.ps1:392`; `pwsh/install.ps1:11,57`; `pwsh/diagnostics.ps1:247` |
| 7 | Med | With a single WSL distro, `$distros[0]` is one *character*. `wsl --list` output is UTF-16. "RNode via WSL" is labeled recommended, but WSL2 can't see USB devices without usbipd. | `pwsh/install.ps1:128`; `pwsh/rnode.ps1:304` |
| 8 | Low | PowerShell `switch` is case-insensitive, so `m` also matches the `M` clause (MeshChatX installs twice), and `l` has the same problem (the Log menu reopens after exit). `Get-EventLog` doesn't exist on PS 7. Update checks compare versions as strings. | `rns_management_tool.ps1:107-114`; `pwsh/advanced.ps1:163,323` |
| 9 | Low | The `run_with_timeout` fallback leaves orphans on Ctrl+C. `pgrep -f meshchatx` over-matches. The Windows and Linux MeshChatX storage dirs differ. "Start now" can launch a second rnsd. `RNS_MIN_VERSION=1.2.5` is stale; MeshChatX 4.9.1 needs rns ≥ 1.5.4. | `lib/utils.sh:28-44`; `lib/core.sh:90` |

**No problems found in:** #82 (EOF handling), #88 (curl|sudo bash removal) and the
`setup_autostart` linger change.

## 2. Windows reality check

| Area | Verdict |
|---|---|
| Install RNS/LXMF/NomadNet | Works **if** a real `python` is on PATH. It's a `pip install` wrapper. |
| MeshChatX install | Works (pip, Python 3.11 gate) |
| Network tools (rnstatus/rnpath/rnprobe/…) | Work (pass-through) |
| Backup / list / export / factory reset | Work |
| COM port detection | Works |
| **Start/restart rnsd, keep-alive task** | **Broken** (#1) |
| **Restore / import** | **Broken** (#2) |
| **RNode config / EEPROM / console / "bootloader"** | **Broken, one option risky** (#4) |
| Python detection on a fresh Win 11 | Likely broken (#6) |
| Sideband | Opens the GitHub releases page in a browser |
| README feature matrix | Overclaims: the spinner, selective updates and port health checks aren't implemented |

What upstream already gives Windows users:
- `rns` 1.5.4, `lxmf`, `nomadnet` and `sbapp` are pure-Python and "OS Independent".
- `py -m pip install rns lxmf nomadnet` installs `rnsd`, `rnodeconf` (firmware flashing
  included), `rnstatus` and the rest natively.

The one piece of Windows-specific knowledge in the tool is the doctor's warnings about
the Store stub and PATH problems. That fits in a short doc.

## 3. Versus MeshForge / MeshAnchor

- **Linux/Pi:** MeshForge covers RNS/LXMF install (`scripts/install_noc.sh`), NomadNet
  (`install_nomadnet.sh`), MeshChatX (`install_meshchatx.sh`), rnsd service management,
  `~/.reticulum` templates (`src/commands/rns_templates.py`), a deeper RNS doctor/repair,
  and fleet backup of `~/.reticulum`.
- **Only this tool has:**
  - RNode firmware flashing via `rnodeconf --autoinstall`, a one-command wrapper.
  - A Sideband pip install.
  - Plain upstream-PyPI installs for non-fleet users. MeshForge pins Nursedude forks.
- **Windows:** neither MeshForge nor MeshAnchor supports it, and adding it would be a
  real port: `fcntl`/`pwd`/`grp` imports, ~95 `systemctl` call sites each, tmux, and
  systemd user units.
- **Code flow:** one-way. This tool adapted about 15 MeshForge patterns; nothing went
  back.
- **Stale docs:** MeshForge's `.claude/foundations/meshforge_ecosystem.md` lists this
  tool as "dormant (2026-06-20) — NOT deployed". Its boundary rules still assign
  "RNS/NomadNet install scripts" and "RNODE firmware flashing" to this tool, although
  MeshForge now ships its own installers. MeshAnchor's ecosystem doc repeats this.

## 4. Options

### A. Retire — recommended (chosen 2026-09-25)

1. Windows: [`docs/WINDOWS_QUICKSTART.md`](WINDOWS_QUICKSTART.md) replaces the PowerShell
   tool. It covers `py -m pip`, PATH for the Scripts folder, the Store alias, a
   Scheduled Task for `rnsd -s`, RNode on COM ports, apps, and backup/restore.
2. Linux/Pi: use [MeshForge](https://github.com/Nursedude/meshforge), or install the
   upstream packages directly.
3. README archive banner, then archive the GitHub repo.
4. Follow-up outside this repo: MeshForge's and MeshAnchor's ecosystem docs still assign
   installers and RNode flashing to this tool.

### B. Keep, minimal fix — about half a day, only if the Win 11 box shows real value

In priority order:

1. `--daemon` → `-s` in both service scripts and the keep-alive task. Fix the help
   text too.
2. Restore/import: copy the *contents* (`Copy-Item "$src\*" $dest -Recurse -Force`).
   Reject an empty selection.
3. `retry_with_backoff`: capture `rc` inside the `if`. Call `check_pip` before
   option 4.
4. RNode menu: delete the EEPROM, console and "bootloader" entries. Add `-T` and
   Hz to the radio config.
5. Python detection: try `py -3` first, and reject the Store stub message.
6. Doctor: use `SUDO_USER`. `switch -CaseSensitive`. Fix the WSL distro indexing.
7. Add a real CI smoke test that runs `rnsd -s` / `rnodeconf --help` from the real
   package, not mocks, so this class of bug can't hide again.

Even after B, the honest pitch is "a menu around pip + rnodeconf + one Scheduled Task".

## 5. Win 11 field-test checklist (≈20 min) — decides A vs B

On the Win 11 box, from a fresh PowerShell:

```powershell
git clone https://github.com/Nursedude/RNS-Management-Tool; cd RNS-Management-Tool
Set-ExecutionPolicy -Scope Process Bypass; .\rns_management_tool.ps1
```

| Step | Expected if the audit is right |
|---|---|
| Menu → install RNS on a fresh box (no Python yet) | Reports "Python detected" even though only the Store stub exists (#6) |
| After a real Python install: Services → Start rnsd | Fails; `rnsd` exits with `unrecognized arguments: --daemon` (#1) |
| Services → enable auto-start, then log off and back on | No `rnsd` process (`Get-Process rnsd`) (#1) |
| Backup, then edit `~\.reticulum\config`, then Restore | Edit still there; new `~\.reticulum\.reticulum` folder (#2) |
| Type `m` at the main menu | MeshChatX install runs twice (#8) |
| With an RNode on COM: RNode → EEPROM / Console | rnodeconf argument errors. **Don't run "Update bootloader".** (#4) |
| Compare: `py -m pip install rns` then `rnsd -s` in a terminal | Works natively, no tool needed |

If the rows behave as predicted, the retire decision stands.
