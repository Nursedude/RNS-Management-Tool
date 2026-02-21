# RNS Management Tool - Quick Start Guide

Get up and running with Reticulum in under 5 minutes!

## Installation

### Raspberry Pi / Linux

```bash
# Clone and run
git clone https://github.com/Nursedude/RNS-Management-Tool.git
cd RNS-Management-Tool
chmod +x rns_management_tool.sh
./rns_management_tool.sh
```

### Windows 11 (PowerShell)

```powershell
# Clone and run
git clone https://github.com/Nursedude/RNS-Management-Tool.git
cd RNS-Management-Tool

# Allow execution and run
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\rns_management_tool.ps1
```

## First-Time Setup

1. **Run the tool** — the startup health check validates your environment automatically
2. **Select Option 1** — Install/Update Reticulum Ecosystem
3. **Follow the prompts:**
   - Update system packages? **Y** (recommended)
   - Create backup? **Y** (if you have existing config)
   - Install NomadNet? **Y** (for terminal client)
4. **Wait for installation** (2-5 minutes depending on your system)
5. **Start the daemon** when prompted: **Y**
6. **Done!** You now have a working Reticulum node

---

## Common Scenarios

### "I have everything installed, just want to update"
```bash
./rns_management_tool.sh
# Select Option 1: Install/Update Reticulum Ecosystem
# Accept backup prompt, wait for updates, start rnsd
```

### "Nothing is installed yet"
```bash
./rns_management_tool.sh
# First-run wizard auto-detects fresh setup
# Select Option 1: Everything gets installed
```

### "I only want the Python stack, no MeshChat"
```bash
./rns_management_tool.sh
# Select Option 1 for RNS/LXMF/NomadNet
# Skip Option 4 (MeshChat)
```

### "Quick field check"
```bash
./rns_management_tool.sh
# Press 'q' for Quick Mode — start/stop rnsd, rnstatus, rnpath, rnprobe, rncp
```

---

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Permission denied | `chmod +x rns_management_tool.sh` |
| pip not found | `sudo apt install python3-pip` |
| RNODE not detected | `sudo usermod -aG dialout $USER` then logout/login |
| MeshChat build fails | Script auto-upgrades Node.js; ensure 18+ with `node --version` |
| Command not found after update | Log out and back in, or `sudo reboot` |

---

## After Setup - Quick Tests

```bash
# Check RNS is installed
rnsd --version

# Check network status
rnstatus

# Launch NomadNet (Ctrl+Q to quit)
nomadnet

# Launch MeshChat (if installed)
cd ~/reticulum-meshchat && npm run dev
```

---

## Important Notes

- **Backups are automatic** — stored at `~/.reticulum_backup_[DATE]_[TIME]/`
- **Update order is handled for you** — RNS first, then LXMF, then NomadNet, then MeshChat
- **Your data is preserved** — identities, messages, and configs are maintained
- **Services stop temporarily** during updates and restart automatically after
- **Logs** are at `~/rns_management.log` (auto-rotates at 1MB)

---

## Questions?

- Full docs: [README.md](README.md)
- Development guide: [CLAUDE.md](CLAUDE.md)
- Official Reticulum docs: https://reticulum.network
- Community: https://github.com/markqvist/Reticulum/discussions
- Issues: https://github.com/Nursedude/RNS-Management-Tool/issues
