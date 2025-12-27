# Quick Start Guide - Reticulum Update Installer

## TL;DR - Get Started in 30 Seconds

```bash
# Download and run
wget https://raw.githubusercontent.com/Nursedude/RNS-updater/main/reticulum_updater.sh
chmod +x reticulum_updater.sh
./reticulum_updater.sh
```

Then follow the on-screen prompts!

---

## What You'll See

### 1. Welcome Screen
```
============================================
  Reticulum Ecosystem Update Installer
============================================

>>> Checking Python Installation

✓ Python3 found: 3.11.2
```

### 2. Version Check
```
>>> Checking Installed Components

ℹ RNS (Reticulum) is installed: version 1.0.4
ℹ LXMF is installed: version 0.3.8
ℹ Nomad Network is installed: version 0.4.5
⚠ MeshChat is not installed
```

### 3. Backup Prompt
```
>>> Creating Backup

Do you want to create a backup before updating? (recommended)
Backup will include configuration files from:
  - ~/.reticulum/
  - ~/.nomadnetwork/
  - ~/.lxmf/
Create backup? (Y/n):
```

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
./reticulum_updater.sh
# Press Enter for backup (recommended): [Enter]
# Press Enter to continue: [Enter]
# Wait for updates...
# Start rnsd? (Y/n): [Enter]
# Done!
```

### Scenario 2: "I only have RNS, want to add Nomad Network"
```bash
./reticulum_updater.sh
# Script detects only RNS installed
# Updates RNS
# Offers to install LXMF and Nomad Network
# Say yes to both
# Done!
```

### Scenario 3: "Nothing is installed yet"
```bash
./reticulum_updater.sh
# Script detects nothing installed
# "Would you like to perform a fresh installation instead?"
# Type: y [Enter]
# "Install MeshChat as well?"
# Type: y [Enter]
# Everything gets installed
# Done!
```

### Scenario 4: "I don't want MeshChat, just the Python stuff"
```bash
./reticulum_updater.sh
# Follow prompts normally
# When asked "Install MeshChat?" 
# Type: n [Enter]
# Only RNS/LXMF/Nomad get updated
```

---

## Quick Troubleshooting

### Problem: "Permission denied"
**Solution:**
```bash
chmod +x reticulum_updater.sh
./reticulum_updater.sh
```

### Problem: "pip: command not found"
**Solution:**
```bash
sudo apt update
sudo apt install python3-pip
./reticulum_updater.sh
```

### Problem: "Git not found" (for MeshChat)
**Solution:**
```bash
sudo apt update
sudo apt install git nodejs npm
./reticulum_updater.sh
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
# Download, make executable, and run
wget https://raw.githubusercontent.com/Nursedude/RNS-updater/main/reticulum_updater.sh && chmod +x reticulum_updater.sh && ./reticulum_updater.sh

# Or if you already have it
chmod +x reticulum_updater.sh && ./reticulum_updater.sh
```

---

## Questions?

- Check the full README.md for detailed documentation
- See update logs at `~/reticulum_update_[DATE]_[TIME].log`
- Visit https://reticulum.network for official documentation
- Join the discussion at https://github.com/markqvist/Reticulum/discussions

---

**Happy updating! 🚀**
