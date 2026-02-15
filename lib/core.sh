# shellcheck disable=SC2034  # Color vars and log level constants are part of the UI API
#########################################################
# lib/core.sh — Terminal, colors, home resolution, globals
# Sourced by rns_management_tool.sh
#########################################################

# Terminal capability detection (adapted from meshforge emoji.py/install.sh)
# Detects dumb terminals, piped output, and missing color support
detect_terminal_capabilities() {
    local term="${TERM:-}"
    HAS_COLOR=false

    # Check if stdout is a terminal (not piped)
    if [ -t 1 ]; then
        # Check for dumb/limited terminals
        case "$term" in
            dumb|vt100|vt220|"")
                HAS_COLOR=false
                ;;
            *)
                # Check tput for color count if available
                if command -v tput &> /dev/null; then
                    local colors
                    colors=$(tput colors 2>/dev/null || echo 0)
                    [ "$colors" -ge 8 ] && HAS_COLOR=true
                else
                    # Assume color support for known modern terminals
                    HAS_COLOR=true
                fi
                ;;
        esac
    fi
}
detect_terminal_capabilities

# Color codes for output - gracefully degrade on dumb terminals
if [ "$HAS_COLOR" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    NC='\033[0m'
    BOLD='\033[1m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    NC=''
    BOLD=''
fi

# Sudo-aware home directory resolution (adapted from meshforge paths.py)
# When running with sudo, $HOME resolves to /root - we want the real user's home
resolve_real_home() {
    local sudo_user="${SUDO_USER:-}"
    # Validate SUDO_USER (path traversal prevention from meshforge)
    if [ -n "$sudo_user" ] && [ "$sudo_user" != "root" ] && \
       [[ "$sudo_user" != */* ]] && [[ "$sudo_user" != *..* ]]; then
        # Resolve via getent (works even if /home is non-standard)
        local home_dir
        home_dir=$(getent passwd "$sudo_user" 2>/dev/null | cut -d: -f6)
        if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
            echo "$home_dir"
            return
        fi
    fi
    echo "$HOME"
}
REAL_HOME="$(resolve_real_home)"

# Global variables
SCRIPT_VERSION="0.3.5-beta"
BACKUP_DIR="$REAL_HOME/.reticulum_backup_$(date +%Y%m%d_%H%M%S)"
UPDATE_LOG="$REAL_HOME/rns_management.log"
LOG_MAX_BYTES=1048576   # 1MB rotation threshold (meshforge pattern)
LOG_MAX_ROTATIONS=3     # Keep .log.1, .log.2, .log.3
MESHCHAT_DIR="$REAL_HOME/reticulum-meshchat"
SIDEBAND_DIR="$REAL_HOME/Sideband"
NEEDS_REBOOT=false
IS_WSL=false
IS_RASPBERRY_PI=false
IS_SSH=false
IS_INTERACTIVE=false
PEP668_DETECTED=false
OS_TYPE=""
OS_VERSION=""
ARCHITECTURE=""

# Log rotation (adapted from meshforge 1MB rotation pattern)
# Rotates UPDATE_LOG when it exceeds LOG_MAX_BYTES, keeping LOG_MAX_ROTATIONS copies.
# Called once at startup before any logging occurs.
rotate_log() {
    [ ! -f "$UPDATE_LOG" ] && return 0

    local log_size
    log_size=$(stat -c%s "$UPDATE_LOG" 2>/dev/null || stat -f%z "$UPDATE_LOG" 2>/dev/null || echo 0)

    if [ "$log_size" -ge "$LOG_MAX_BYTES" ]; then
        # Rotate: .log.3 → delete, .log.2 → .log.3, .log.1 → .log.2, .log → .log.1
        local i=$LOG_MAX_ROTATIONS
        while [ "$i" -gt 1 ]; do
            local prev=$((i - 1))
            [ -f "${UPDATE_LOG}.${prev}" ] && mv -f "${UPDATE_LOG}.${prev}" "${UPDATE_LOG}.${i}"
            i=$((i - 1))
        done
        mv -f "$UPDATE_LOG" "${UPDATE_LOG}.1"
    fi

    # Clean up legacy per-session timestamped log files (pre-rotation era)
    # Keep only the 3 most recent, remove older ones
    local old_logs
    old_logs=$(find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | sort -r)
    local count=0
    while IFS= read -r logfile; do
        [ -z "$logfile" ] && continue
        count=$((count + 1))
        if [ "$count" -gt 3 ]; then
            rm -f "$logfile" 2>/dev/null
        fi
    done <<< "$old_logs"
}
rotate_log

# Tool availability flags (set once at startup by detect_available_tools)
HAS_RNSD=false
HAS_RNSTATUS=false
HAS_RNPATH=false
HAS_RNPROBE=false
HAS_RNCP=false
HAS_RNX=false
HAS_RNID=false
HAS_RNODECONF=false
HAS_NOMADNET=false
HAS_MESHCHAT=false
HAS_PYTHON3=false
HAS_PIP=false
HAS_NODE=false
HAS_GIT=false

# UI Constants
BOX_WIDTH=58
MENU_BREADCRUMB=""
SESSION_START_TIME=$(date +%s)

# Status cache (adapted from meshforge status_bar.py)
# Avoids hammering pip3/pgrep on every menu redraw
STATUS_CACHE_TTL=10  # seconds
_CACHE_RNSD_STATUS=""
_CACHE_RNSD_TIME=0
_CACHE_RNSD_PID=""
_CACHE_RNS_VER=""
_CACHE_RNS_TIME=0
_CACHE_LXMF_VER=""
_CACHE_LXMF_TIME=0

# Log levels (adapted from meshforge logging_config.py)
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# Network Timeout Constants (RNS006: Subprocess timeout protection)
NETWORK_TIMEOUT=300      # 5 minutes for network operations
APT_TIMEOUT=600          # 10 minutes for apt operations (can be slow)
GIT_TIMEOUT=300          # 5 minutes for git operations
PIP_TIMEOUT=300          # 5 minutes for pip operations
