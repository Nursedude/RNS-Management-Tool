# RNS Management Tool - Quick Start Guide

Get up and running with Reticulum in under 5 minutes!

## 🚀 Installation

### Raspberry Pi / Linux (One-Line Install)

```bash
wget -O - https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh | bash
```

**Or step-by-step:**

```bash
# Download
wget https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.sh

# Make executable
chmod +x rns_management_tool.sh

# Run
./rns_management_tool.sh
```

### Windows 11 (PowerShell)

```powershell
# Open PowerShell as Administrator
# Download and run
iwr -useb https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.ps1 | iex
```

**Or step-by-step:**

```powershell
# Download
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Nursedude/RNS-Management-Tool/main/rns_management_tool.ps1" -OutFile "rns_management_tool.ps1"

# Allow execution
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Run
.\rns_management_tool.ps1
```

## 📖 First-Time Setup

### Option 1: Complete Installation (Recommended)

1. **Run the tool**
   ```bash
   ./rns_management_tool.sh    # Linux/Pi
   .\rns_management_tool.ps1   # Windows
   ```

2. **Select Option 1** - Install/Update Reticulum Ecosystem

3. **Follow the prompts:**
   - ✅ Update system packages? **Y** (recommended)
   - ✅ Create backup? **Y** (if you have existing config)
   - ✅ Install NomadNet? **Y** (for terminal client)

4. **Wait for installation** (2-5 minutes depending on your system)

5. **Start the daemon** when prompted: **Y**

6. **Done!** You now have a working Reticulum node

**Recommendation:** Press Enter (defaults to Yes)

### 4. Service Management
```
>>> Stopping Running Services

ℹ Stopping rnsd daemon...
✓ rnsd stopped

Press Enter to continue...
```

### 5. Updates in Progress
```
>>> Updating RNS (Reticulum)

ℹ Current version: 1.0.4
ℹ Updating to latest version...
[pip output here...]
✓ RNS (Reticulum) updated: 1.0.4 → 1.0.5

>>> Updating LXMF

ℹ Current version: 0.3.8
ℹ Updating to latest version...
[pip output here...]
✓ LXMF updated: 0.3.8 → 0.4.0
```

### 6. Final Summary
```
>>> Update Summary

Updated Components:
  ✓ RNS (Reticulum): 1.0.5
  ✓ LXMF: 0.4.0
  ✓ Nomad Network: 0.4.6
  ✓ MeshChat: 0.2.1

ℹ Update log saved to: /home/pi/reticulum_update_20250124_143521.log
ℹ Backup saved to: /home/pi/.reticulum_backup_20250124_143022

Next Steps:
  1. Test your installation by running: rnstatus
  2. Launch Nomad Network: nomadnet
  3. Launch MeshChat: cd /home/pi/reticulum-meshchat && npm run dev
```

---

## Common Scenarios

### Scenario 1: "I have everything installed, just want to update"
```bash
./rns_management_tool.sh
# Select Option 1: Install/Update Reticulum Ecosystem
# Press Enter for backup (recommended): [Enter]
# Wait for updates...
# Start rnsd? (Y/n): [Enter]
# Done!
```

### Scenario 2: "I only have RNS, want to add Nomad Network"
```bash
./rns_management_tool.sh
# Select Option 3: Install NomadNet
# Follow the prompts
# Done!
```

### Scenario 3: "Nothing is installed yet"
```bash
./rns_management_tool.sh
# First-run wizard auto-detects fresh setup
# Select Option 1: Install/Update Reticulum Ecosystem
# Everything gets installed
# Done!
```

### Scenario 4: "I don't want MeshChat, just the Python stuff"
```bash
./rns_management_tool.sh
# Select Option 1: Install/Update Reticulum Ecosystem
# Only RNS/LXMF/Nomad get installed
# Skip Option 4 (MeshChat)
```

---

## Quick Troubleshooting

### Problem: "Permission denied"
**Solution:**
```bash
chmod +x rns_management_tool.sh
./rns_management_tool.sh
```

### Problem: "pip: command not found"
**Solution:**
```bash
sudo apt update
sudo apt install python3-pip
./rns_management_tool.sh
```

### Problem: "Git not found" (for MeshChat)
**Solution:**
```bash
sudo apt update
sudo apt install git nodejs npm
./rns_management_tool.sh
```

### Problem: Updates completed but "command not found" when running programs
**Solution:**
```bash
sudo reboot
# Or just log out and log back in
```

---

## After Update - Quick Test

### Test 1: Check RNS
```bash
rnsd --version
# Should show latest version
```

### Test 2: Check Network Status
```bash
rnstatus
# Should show your Reticulum interfaces
```

### Test 3: Start Nomad Network
```bash
nomadnet
# Terminal interface should appear
# Press Ctrl+Q to quit
```

### Test 4: Launch MeshChat (if installed)
```bash
cd ~/reticulum-meshchat
npm run dev
# GUI should open in default browser
```

---

## Important Notes

✅ **Backup is created automatically** (if you choose yes)
   - Located at: `~/.reticulum_backup_[DATE]_[TIME]/`
   - Keeps your identities, configs, and messages safe

✅ **Update order matters** (script handles this automatically)
   - RNS first (everything depends on it)
   - LXMF second (Nomad and MeshChat need it)
   - Nomad Network third
   - MeshChat last

✅ **Your data is preserved**
   - Identities stay the same
   - Messages are not deleted
   - Network connections preserved
   - Configurations maintained

⚠️ **Services are temporarily stopped**
   - The script stops `rnsd` during update
   - You may need to close Nomad Network manually
   - You may need to close MeshChat manually
   - Everything restarts after update completes

---

## One-Liner Cheat Sheet

```bash
# Clone and run
git clone https://github.com/Nursedude/RNS-Management-Tool.git && cd RNS-Management-Tool && chmod +x rns_management_tool.sh && ./rns_management_tool.sh

# Or if you already have it
chmod +x rns_management_tool.sh && ./rns_management_tool.sh
```

---

## Questions?

- Check the full README.md for detailed documentation
- See update logs at `~/reticulum_update_[DATE]_[TIME].log`
- Visit https://reticulum.network for official documentation
- Join the discussion at https://github.com/markqvist/Reticulum/discussions

---

**Happy updating! 🚀**
