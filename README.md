# Reticulum Ecosystem Update Installer

An interactive bash script for updating Reticulum Network Stack (RNS), LXMF, Nomad Network, and MeshChat on Raspberry Pi OS and other Debian-based systems.

## Features

- ✅ **Automatic Version Detection** - Detects currently installed versions
- ✅ **Interactive Updates** - Prompts for each component
- ✅ **Automatic Backup** - Creates backup of configuration files
- ✅ **Dependency Management** - Updates components in correct order
- ✅ **Service Management** - Stops/starts services as needed
- ✅ **Detailed Logging** - Creates comprehensive update logs
- ✅ **Fresh Installation** - Can perform clean install if nothing is installed
- ✅ **MeshChat Support** - Handles git-based MeshChat updates
- ✅ **Color-Coded Output** - Easy-to-read progress indicators

## What Gets Updated

1. **RNS (Reticulum Network Stack)** - Core networking layer
2. **LXMF** - Messaging protocol layer
3. **Nomad Network** - Terminal-based messaging client
4. **MeshChat** - GUI messaging client (if installed from source)

## Requirements

### Minimal Requirements
- Raspberry Pi OS (or any Debian-based Linux)
- Python 3.7 or higher
- pip (Python package manager)
- Internet connection

### Additional Requirements for MeshChat
- git
- Node.js
- npm

*The script will offer to install missing requirements automatically.*

## Installation

### Step 1: Download the Script

```bash
# Download the script
wget https://raw.githubusercontent.com/Nursedude/RNS-updater/main/reticulum_updater.sh

# Or if you have it locally, just navigate to the directory
cd /path/to/script
```

### Step 2: Make it Executable

```bash
chmod +x reticulum_updater.sh
```

### Step 3: Run the Script

```bash
./reticulum_updater.sh
```

## Usage

### Interactive Mode (Recommended)

Simply run the script and follow the prompts:

```bash
./reticulum_updater.sh
```

The script will:
1. Check your system for Python and pip
2. Detect installed Reticulum components
3. Display current versions
4. Offer to create a backup
5. Stop running services
6. Update each component
7. Restart services
8. Show a summary of changes

### What the Script Does

#### 1. System Check
- Verifies Python 3 is installed
- Verifies pip is installed
- Checks Raspberry Pi compatibility (warns if not on Pi)

#### 2. Component Detection
- Scans for installed RNS version
- Scans for installed LXMF version
- Scans for installed Nomad Network version
- Checks for MeshChat installation

#### 3. Backup Creation
- Creates timestamped backup directory
- Backs up `~/.reticulum/` configuration
- Backs up `~/.nomadnetwork/` configuration
- Backs up `~/.lxmf/` configuration

#### 4. Service Management
- Stops `rnsd` daemon if running
- Prompts to close Nomad Network if running
- Prompts to close MeshChat if running

#### 5. Updates
- Updates RNS first (dependency for others)
- Updates LXMF second (required by Nomad/MeshChat)
- Updates Nomad Network
- Updates MeshChat (pulls from git, rebuilds)

#### 6. Service Restart
- Offers to restart `rnsd` daemon
- Provides commands to launch applications

## Examples

### Example 1: Fresh Installation
```bash
./reticulum_updater.sh
# Script detects nothing installed
# Prompts: "Would you like to perform a fresh installation instead?"
# Choose: y
# Installs RNS, LXMF, Nomad Network
# Optionally installs MeshChat
```

### Example 2: Update Existing Installation
```bash
./reticulum_updater.sh
# Script shows:
#   ℹ RNS (Reticulum) is installed: version 1.0.4
#   ℹ LXMF is installed: version 0.3.8
#   ℹ Nomad Network is installed: version 0.4.5
#   ⚠ MeshChat is not installed
# Creates backup: /home/pi/.reticulum_backup_20250124_143022
# Updates all components
# Shows summary with new versions
```

### Example 3: Update with MeshChat
```bash
./reticulum_updater.sh
# Detects MeshChat at ~/reticulum-meshchat
# Updates via git pull
# Runs npm install and npm build
# Updates complete
```

## Output Files

### Backup Directory
Format: `~/.reticulum_backup_YYYYMMDD_HHMMSS/`

Contents:
- `.reticulum/` - RNS configuration and identity
- `.nomadnetwork/` - Nomad Network settings and data
- `.lxmf/` - LXMF identity and message store

### Update Log
Format: `~/reticulum_update_YYYYMMDD_HHMMSS.log`

Contains:
- Timestamp for each operation
- Version changes
- Command outputs
- Error messages (if any)

## Troubleshooting

### Script Won't Run
```bash
# Make sure it's executable
chmod +x reticulum_updater.sh

# Check for correct line endings (if copied from Windows)
dos2unix reticulum_updater.sh  # if dos2unix is installed
# or
sed -i 's/\r$//' reticulum_updater.sh
```

### Permission Errors
```bash
# If you get permission errors during pip install, the script
# automatically uses --break-system-packages flag

# If that doesn't work, you may need to update pip itself:
pip3 install --upgrade pip --break-system-packages
```

### MeshChat Build Fails
```bash
# Install build dependencies manually:
sudo apt update
sudo apt install -y git nodejs npm build-essential

# Then run the script again
./reticulum_updater.sh
```

### Services Won't Stop
```bash
# Manually stop services:
killall rnsd
killall nomadnet
killall meshchat

# Then run the script
./reticulum_updater.sh
```

### "Command not found" After Update
```bash
# Reboot your system
sudo reboot

# Or manually add pip install path to PATH:
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc
```

## What Gets Backed Up

| Directory | Content |
|-----------|---------|
| `~/.reticulum/` | Network config, identities, known destinations |
| `~/.nomadnetwork/` | User settings, pages, storage, LXMF message database |
| `~/.lxmf/` | LXMF identity files, message queues |

## Restoring from Backup

If something goes wrong, restore from backup:

```bash
# List backups
ls -la ~ | grep reticulum_backup

# Restore all configs (replace DATE with your backup date)
cp -r ~/.reticulum_backup_YYYYMMDD_HHMMSS/.reticulum ~/
cp -r ~/.reticulum_backup_YYYYMMDD_HHMMSS/.nomadnetwork ~/
cp -r ~/.reticulum_backup_YYYYMMDD_HHMMSS/.lxmf ~/

# Restart services
rnsd --daemon
```

## Post-Update Testing

After updating, verify everything works:

### Test RNS
```bash
# Check version
rnsd --version

# View network status
rnstatus

# Start daemon
rnsd --daemon
```

### Test Nomad Network
```bash
# Launch Nomad Network
nomadnet

# Should show updated version in interface
```

### Test MeshChat
```bash
# Navigate to MeshChat directory
cd ~/reticulum-meshchat

# Run in development mode
npm run dev

# Or build for production
npm run build
```

## Advanced Options

### Update Only Specific Components

Edit the script and comment out sections you don't want:

```bash
# Open in editor
nano reticulum_updater.sh

# Find and comment out unwanted updates:
# update_pip_package "nomadnet" "Nomad Network"  # Commented out
```

### Change MeshChat Install Location

Edit the `MESHCHAT_DIR` variable at the top of the script:

```bash
MESHCHAT_DIR="$HOME/custom/path/to/meshchat"
```

### Skip Backup

When prompted "Create backup?", answer `n`. (Not recommended!)

## Scheduling Automatic Updates

To run updates automatically (use with caution):

```bash
# Edit crontab
crontab -e

# Add line for weekly updates (Sundays at 2 AM)
0 2 * * 0 /home/pi/reticulum_updater.sh >> /home/pi/auto_update.log 2>&1

# Note: This runs non-interactively, so set script to auto-answer prompts
```

## Security Considerations

- The script uses `--break-system-packages` flag for pip on newer systems
- This is safe for Reticulum but be aware of what it means
- Always review update logs for any issues
- Keep backups of important configurations
- Test after updates before relying on system

## Contributing

Improvements and bug reports welcome! Please submit issues or pull requests.

## License

This script is provided as-is for the Reticulum community. Use at your own risk.

## Support

- Reticulum Documentation: https://reticulum.network/manual/
- Reticulum GitHub: https://github.com/markqvist/Reticulum
- Nomad Network: https://github.com/markqvist/nomadnet
- MeshChat: https://github.com/liamcottle/reticulum-meshchat
- Community Discussion: https://github.com/markqvist/Reticulum/discussions

## Changelog

### Version 1.0 (2025-01-24)
- Initial release
- Support for RNS, LXMF, Nomad Network, MeshChat
- Interactive installation and updates
- Automatic backup creation
- Service management
- Detailed logging
- Fresh installation support
- Desktop launcher creation for MeshChat

---

**Made with ❤️ for the Reticulum community**
