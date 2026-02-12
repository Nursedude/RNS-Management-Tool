#!/bin/bash
# shellcheck disable=SC2317  # Functions called via TUI menus/traps appear unreachable to static analysis
# shellcheck disable=SC2034  # Color vars and log level constants are part of the UI API

#########################################################
# RNS Management Tool
# Complete Reticulum Network Stack Management Solution
# For Raspberry Pi OS, Debian, Ubuntu, and WSL
#
# Features:
# - Full Reticulum ecosystem installation
# - Interactive RNODE installer and configuration
# - Automated updates and backups
# - Enhanced error handling and recovery
# - Cross-platform support
#########################################################

set -o pipefail  # Exit on pipe failures

# Resolve script directory reliably (meshforge pattern)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
SCRIPT_VERSION="0.3.4-beta"
BACKUP_DIR="$REAL_HOME/.reticulum_backup_$(date +%Y%m%d_%H%M%S)"
UPDATE_LOG="$REAL_HOME/rns_management_$(date +%Y%m%d_%H%M%S).log"
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

# Timeout wrapper for network operations
run_with_timeout() {
    local timeout_val="$1"
    shift
    if command -v timeout &> /dev/null; then
        timeout "$timeout_val" "$@"
    else
        # Fallback if timeout command not available
        "$@"
    fi
}

# Retry with exponential backoff (adapted from meshforge install_reliability_triage.md)
# Usage: retry_with_backoff <max_retries> <command...>
# Retries with 2s, 4s, 8s... delays between attempts
retry_with_backoff() {
    local max_retries="$1"
    shift
    local attempt=1
    local delay=2

    while [ $attempt -le "$max_retries" ]; do
        if "$@"; then
            return 0
        fi

        if [ $attempt -lt "$max_retries" ]; then
            print_warning "Attempt $attempt/$max_retries failed, retrying in ${delay}s..."
            log_warn "Retry $attempt/$max_retries for: $*"
            sleep "$delay"
            delay=$((delay * 2))
        fi
        ((attempt++))
    done

    log_error "All $max_retries attempts failed for: $*"
    return 1
}

#########################################################
# Utility Functions
#########################################################

detect_environment() {
    # Detect WSL
    if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
        IS_WSL=true
        OS_TYPE="WSL"
    fi

    # Detect Raspberry Pi - comprehensive check for all models
    if [ -f /proc/cpuinfo ]; then
        if grep -qiE "Raspberry Pi|BCM2|BCM27|BCM28" /proc/cpuinfo; then
            IS_RASPBERRY_PI=true
            # Get specific Pi model
            if [ -f /proc/device-tree/model ]; then
                PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
            else
                PI_MODEL=$(grep "^Model" /proc/cpuinfo | cut -d: -f2 | xargs)
            fi
        fi
    fi

    # Detect OS
    if [ -f /etc/os-release ]; then
        # shellcheck source=/etc/os-release
        . /etc/os-release
        OS_TYPE="${NAME:-Unknown}"
        OS_VERSION="${VERSION_ID:-Unknown}"
    fi

    # Detect architecture
    ARCHITECTURE=$(uname -m)

    # Detect SSH session (adapted from meshforge launcher.py detect_environment)
    if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ] || [ -n "${SSH_CONNECTION:-}" ]; then
        IS_SSH=true
    fi

    # Detect interactive mode (adapted from meshforge install.sh TTY check)
    if [ -t 0 ] && [ -c /dev/tty ]; then
        IS_INTERACTIVE=true
    fi

    # Detect PEP 668 externally-managed Python (adapted from meshforge install.sh)
    # Debian 12+ / RPi OS Bookworm restricts system-wide pip installs
    if command -v python3 &> /dev/null; then
        if python3 -c "
import sys, pathlib
sys.exit(0 if any('EXTERNALLY-MANAGED' in str(p) for p in pathlib.Path(sys.prefix).glob('**/EXTERNALLY-MANAGED')) else 1)
" 2>/dev/null; then
            PEP668_DETECTED=true
        fi
    fi

    log_message "Environment detected: OS=$OS_TYPE, WSL=$IS_WSL, RaspberryPi=$IS_RASPBERRY_PI, Arch=$ARCHITECTURE, SSH=$IS_SSH, Interactive=$IS_INTERACTIVE, PEP668=$PEP668_DETECTED"
}

# Startup capability detection - scan available tools once, set global flags
# Prevents repeated command -v checks and enables graceful menu disabling
detect_available_tools() {
    command -v rnsd &>/dev/null && HAS_RNSD=true
    command -v rnstatus &>/dev/null && HAS_RNSTATUS=true
    command -v rnpath &>/dev/null && HAS_RNPATH=true
    command -v rnprobe &>/dev/null && HAS_RNPROBE=true
    command -v rncp &>/dev/null && HAS_RNCP=true
    command -v rnx &>/dev/null && HAS_RNX=true
    command -v rnid &>/dev/null && HAS_RNID=true
    command -v rnodeconf &>/dev/null && HAS_RNODECONF=true
    command -v nomadnet &>/dev/null && HAS_NOMADNET=true
    command -v python3 &>/dev/null && HAS_PYTHON3=true
    command -v git &>/dev/null && HAS_GIT=true

    # pip detection (multiple possible names)
    if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
        HAS_PIP=true
    fi

    # Node.js detection
    if command -v node &>/dev/null || command -v nodejs &>/dev/null; then
        HAS_NODE=true
    fi

    # MeshChat detection (installed via npm/git)
    if command -v meshchat &>/dev/null || [ -d "$MESHCHAT_DIR" ]; then
        HAS_MESHCHAT=true
    fi

    # Count available RNS tools
    local rns_tool_count=0
    [ "$HAS_RNSD" = true ] && ((rns_tool_count++))
    [ "$HAS_RNSTATUS" = true ] && ((rns_tool_count++))
    [ "$HAS_RNPATH" = true ] && ((rns_tool_count++))
    [ "$HAS_RNPROBE" = true ] && ((rns_tool_count++))
    [ "$HAS_RNCP" = true ] && ((rns_tool_count++))
    [ "$HAS_RNX" = true ] && ((rns_tool_count++))
    [ "$HAS_RNID" = true ] && ((rns_tool_count++))
    [ "$HAS_RNODECONF" = true ] && ((rns_tool_count++))

    log_message "Tools detected: RNS=$rns_tool_count/8 (rnsd=$HAS_RNSD rnstatus=$HAS_RNSTATUS rnpath=$HAS_RNPATH rnprobe=$HAS_RNPROBE rncp=$HAS_RNCP rnx=$HAS_RNX rnid=$HAS_RNID rnodeconf=$HAS_RNODECONF)"
    log_message "Dependencies: python3=$HAS_PYTHON3 pip=$HAS_PIP node=$HAS_NODE git=$HAS_GIT"
}

# Format a menu item - dimmed if tool is unavailable
# Usage: menu_item "label" "available_flag"
menu_item() {
    local label="$1"
    local available="$2"
    if [ "$available" = true ]; then
        echo "$label"
    else
        echo -e "${YELLOW}$label (not installed)${NC}"
    fi
}

clear_screen() {
    # ANSI escape sequence clear (adapted from meshforge PR #800)
    # Eliminates visible flash caused by subprocess clear command
    printf '\033[H\033[2J'
}

print_header() {
    clear_screen
    echo -e "\n${CYAN}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}║          RNS MANAGEMENT TOOL v${SCRIPT_VERSION}                 ║${NC}"
    echo -e "${CYAN}${BOLD}║     Complete Reticulum Network Stack Manager           ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════╝${NC}\n"

    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo -e "${GREEN}Platform:${NC} Raspberry Pi ($PI_MODEL)"
    elif [ "$IS_WSL" = true ]; then
        echo -e "${GREEN}Platform:${NC} Windows Subsystem for Linux"
    else
        echo -e "${GREEN}Platform:${NC} $OS_TYPE $OS_VERSION ($ARCHITECTURE)"
    fi

    # Compact status line (meshforge status_bar.py pattern)
    echo -e "  $(get_status_line)"
    echo ""
}

print_section() {
    echo -e "\n${BLUE}${BOLD}▶ $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf '\r%sProgress:%s [' "${CYAN}" "${NC}"
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf '] %3d%% - %s' "$percent" "$message"
}

# Step-based progress display for multi-step operations
declare -a OPERATION_STEPS=()
CURRENT_STEP=0

init_operation() {
    local title="$1"
    shift
    OPERATION_STEPS=("$@")
    CURRENT_STEP=0

    echo ""
    print_box_top
    print_box_line "${CYAN}${BOLD}$title${NC}"
    print_box_divider

    local total=${#OPERATION_STEPS[@]}
    for ((i=0; i<total; i++)); do
        print_box_line "  ${YELLOW}○${NC} ${OPERATION_STEPS[$i]}"
    done

    print_box_bottom
    echo ""
}

next_step() {
    local status="${1:-success}"
    local total=${#OPERATION_STEPS[@]}

    if [ "$CURRENT_STEP" -lt "$total" ]; then
        if [ "$status" = "success" ]; then
            echo -e "  ${GREEN}✓${NC} ${OPERATION_STEPS[$CURRENT_STEP]}"
        elif [ "$status" = "skip" ]; then
            echo -e "  ${YELLOW}⊘${NC} ${OPERATION_STEPS[$CURRENT_STEP]} ${YELLOW}(skipped)${NC}"
        else
            echo -e "  ${RED}✗${NC} ${OPERATION_STEPS[$CURRENT_STEP]} ${RED}(failed)${NC}"
        fi
        ((CURRENT_STEP++))
    fi
}

complete_operation() {
    local status="${1:-success}"
    echo ""

    if [ "$status" = "success" ]; then
        print_success "Operation completed successfully"
    else
        print_error "Operation completed with errors"
    fi
}

# Leveled logging (adapted from meshforge logging_config.py)
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$UPDATE_LOG"
}

log_debug() {
    [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ] && \
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$UPDATE_LOG"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$UPDATE_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$UPDATE_LOG"
}

# Cleanup handler (adapted from meshforge set -e pattern)
# Ensures temp files are cleaned and log is flushed on exit/interrupt
cleanup_on_exit() {
    local exit_code=$?
    # Remove any temp files created during session
    rm -f /tmp/rns_mgmt_*.tmp 2>/dev/null
    if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 130 ]; then
        log_error "Script exited with code $exit_code"
    fi
    # Ensure log is written
    if [ -f "$UPDATE_LOG" ]; then
        log_message "=== RNS Management Tool Session Ended (exit=$exit_code) ==="
    fi
}
trap cleanup_on_exit EXIT
trap 'echo ""; print_warning "Interrupted by user"; exit 130' INT TERM

# Enhanced error display with troubleshooting suggestions
show_error_help() {
    local error_type="$1"
    local context="$2"

    echo ""
    echo -e "${RED}${BOLD}Error: $error_type${NC}"
    echo ""

    case "$error_type" in
        "network")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check your internet connection"
            echo "  2) Try: ping -c 3 google.com"
            echo "  3) Check DNS settings"
            echo "  4) If behind proxy, configure git and pip accordingly"
            ;;
        "permission")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check file/directory permissions"
            echo "  2) Try running with sudo if appropriate"
            echo "  3) Verify you own the files: ls -la $context"
            ;;
        "python")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install Python 3.7+: sudo apt install python3 python3-pip"
            echo "  2) Check version: python3 --version"
            echo "  3) Verify pip: pip3 --version"
            ;;
        "nodejs")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install Node.js: select option 1 to install automatically"
            echo "  2) Check version: node --version (requires 18+)"
            echo "  3) Manual install: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
            ;;
        "pip")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Upgrade pip: pip3 install --upgrade pip"
            echo "  2) Try with --user flag: pip3 install --user <package>"
            echo "  3) Clear cache: pip3 cache purge"
            echo "  4) Check for conflicts: pip3 check"
            ;;
        "git")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Install git: sudo apt install git"
            echo "  2) Check SSH keys for private repos"
            echo "  3) Try HTTPS URL instead of SSH"
            ;;
        "device")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check device is connected: ls /dev/ttyUSB* /dev/ttyACM*"
            echo "  2) Add user to dialout group: sudo usermod -aG dialout \$USER"
            echo "  3) Reconnect device and try again"
            echo "  4) Check permissions: sudo chmod 666 $context"
            ;;
        "service")
            echo -e "${YELLOW}Troubleshooting suggestions:${NC}"
            echo "  1) Check service status: systemctl --user status rnsd"
            echo "  2) View logs: journalctl --user -u rnsd -n 50"
            echo "  3) Try manual start: rnsd --daemon"
            echo "  4) Check config: cat ~/.reticulum/config"
            ;;
        *)
            echo -e "${YELLOW}General troubleshooting:${NC}"
            echo "  1) Check log file: $UPDATE_LOG"
            echo "  2) Run diagnostics: select option 6 from main menu"
            echo "  3) Visit: https://github.com/markqvist/Reticulum/issues"
            ;;
    esac
    echo ""
}

# Validate input is numeric
validate_numeric() {
    local input="$1"
    local min="${2:-0}"
    local max="${3:-999999}"

    if [[ ! "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
        return 1
    fi

    return 0
}

# Validate device port format
validate_device_port() {
    local port="$1"

    if [[ ! "$port" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
        print_error "Invalid device port format"
        echo "Expected format: /dev/ttyUSB0 or /dev/ttyACM0"
        return 1
    fi

    if [ ! -e "$port" ]; then
        print_error "Device not found: $port"
        show_error_help "device" "$port"
        return 1
    fi

    return 0
}

# Centralized service status check (adapted from meshforge service_check.py)
# Single source of truth for all service detection - avoids scattered pgrep calls
# Usage: check_service_status <service_name>
# Returns: 0 if running, 1 if stopped
check_service_status() {
    local service="$1"
    case "$service" in
        rnsd)
            # rnsd is typically user-space; check process with exact match first,
            # fall back to anchored patterns to avoid false positives
            pgrep -x "rnsd" > /dev/null 2>&1 || \
                pgrep -f "^rnsd\b" > /dev/null 2>&1 || \
                pgrep -f "[r]nsd --daemon" > /dev/null 2>&1
            ;;
        meshtasticd)
            # meshtasticd may be systemd-managed
            if command -v systemctl &>/dev/null && systemctl is-active --quiet meshtasticd 2>/dev/null; then
                return 0
            fi
            pgrep -x "meshtasticd" > /dev/null 2>&1
            ;;
        nomadnet)
            pgrep -x "nomadnet" > /dev/null 2>&1 || \
                pgrep -f "^nomadnet\b" > /dev/null 2>&1
            ;;
        meshchat)
            pgrep -f "reticulum-meshchat" > /dev/null 2>&1
            ;;
        *)
            # Generic: try exact match
            pgrep -x "$service" > /dev/null 2>&1
            ;;
    esac
}

# Convenience wrapper (backward-compatible)
is_rnsd_running() {
    check_service_status "rnsd"
}

# meshtasticd HTTP API health check (ported from meshforge meshtastic_http.py)
# Probes meshtasticd's HTTP API on common ports to verify web server is reachable.
# Primary probe: /json/report (accepts any valid JSON object)
# Secondary probe: /api/v1/fromradio (protobuf endpoint, always present on webserver)
# Sets MESHTASTICD_HTTP_URL on success for use by other functions.
# Returns: 0 if reachable, 1 if not
MESHTASTICD_HTTP_URL=""
check_meshtasticd_http_api() {
    MESHTASTICD_HTTP_URL=""

    if ! command -v curl &>/dev/null; then
        return 1
    fi

    # Port list mirrors meshforge probe order: HTTPS first, then HTTP, then legacy TCP
    local ports=(443 9443 80 4403)
    local schemes

    for port in "${ports[@]}"; do
        # Determine scheme(s) to try based on port
        if [ "$port" -eq 80 ]; then
            schemes=("http")
        else
            schemes=("https" "http")
        fi

        for scheme in "${schemes[@]}"; do
            local base_url="${scheme}://127.0.0.1:${port}"

            # Primary probe: /json/report — accept any valid JSON object
            local response
            response=$(curl -sk --connect-timeout 3 --max-time 5 \
                -H "Accept: application/json" \
                "${base_url}/json/report" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$response" ]; then
                # Verify it's a JSON object (starts with {)
                local trimmed
                trimmed=$(echo "$response" | sed 's/^[[:space:]]*//')
                if [[ "$trimmed" == "{"* ]]; then
                    MESHTASTICD_HTTP_URL="$base_url"
                    return 0
                fi
            fi

            # Secondary probe: /api/v1/fromradio (protobuf endpoint)
            # 200 = data available, 204 = no data but server alive
            # 400/404/405 = server running but endpoint error (still counts)
            local http_code
            http_code=$(curl -sk --connect-timeout 3 --max-time 5 \
                -o /dev/null -w "%{http_code}" \
                -H "Accept: application/x-protobuf" \
                "${base_url}/api/v1/fromradio" 2>/dev/null)
            case "$http_code" in
                200|204|400|404|405)
                    MESHTASTICD_HTTP_URL="$base_url"
                    return 0
                    ;;
            esac
        done
    done

    return 1
}

# meshtasticd config validation (ported from meshforge dashboard_mixin._check_webserver_config)
# Checks if /etc/meshtasticd/config.yaml has the Webserver section enabled.
# Returns a diagnostic hint string via stdout.
check_meshtasticd_webserver_config() {
    local config_path="/etc/meshtasticd/config.yaml"

    if [ ! -f "$config_path" ]; then
        echo "Fix: $config_path not found"
        return 1
    fi

    if ! [ -r "$config_path" ]; then
        echo "Cannot read config (try running with sudo)"
        return 1
    fi

    # Check if Webserver section exists at all
    if ! grep -q "Webserver:" "$config_path" 2>/dev/null; then
        echo "Fix: Add 'Webserver:' section with 'Port: 443' to $config_path"
        return 1
    fi

    # Check if it's commented out (all Webserver lines start with #)
    local uncommented
    uncommented=$(grep "Webserver:" "$config_path" 2>/dev/null | grep -v "^[[:space:]]*#" | head -1)
    if [ -z "$uncommented" ]; then
        echo "Fix: Webserver section is commented out in $config_path"
        return 1
    fi

    echo "Config has Webserver section — check meshtasticd logs if API unreachable"
    return 0
}

# Safe call wrapper (adapted from meshforge _safe_call pattern)
# Wraps menu actions so a function failure doesn't crash the whole script
# Provides MeshForge-style error categorization with targeted recovery hints
# Usage: safe_call "Label" function_name [args...]
safe_call() {
    local label="$1"
    shift

    # Run command directly (not captured) to preserve interactivity
    if "$@"; then
        return 0
    fi

    local rc=$?
    log_error "safe_call: '$label' failed with exit code $rc"

    # MeshForge-style error categorization (adapted from _safe_call)
    # Analyze exit code for targeted recovery hints
    case $rc in
        126)
            print_error "$label: Permission denied - check file permissions (chmod +x)"
            ;;
        127)
            print_error "$label: Command not found - install required tools first"
            ;;
        124)
            print_error "$label: Operation timed out - check network connectivity"
            ;;
        130)
            # Ctrl+C — not an error, just user interrupt
            print_info "$label: Interrupted by user"
            ;;
        *)
            print_error "$label failed (exit code: $rc)"
            ;;
    esac

    return $rc
}

# Cached status queries (adapted from meshforge status_bar.py)
# Returns cached value if within TTL, otherwise refreshes
get_cached_rnsd_status() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_RNSD_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_RNSD_STATUS" ]; then
        if is_rnsd_running; then
            _CACHE_RNSD_STATUS="running"
            _CACHE_RNSD_PID=$(pgrep -x "rnsd" 2>/dev/null | head -1)
        else
            _CACHE_RNSD_STATUS="stopped"
            _CACHE_RNSD_PID=""
        fi
        _CACHE_RNSD_TIME=$now
    fi
    echo "$_CACHE_RNSD_STATUS"
}

# Get rnsd process uptime as human-readable string
# Returns empty string if not running (MeshForge single-source-of-truth pattern)
get_rnsd_uptime() {
    local pid="${_CACHE_RNSD_PID:-}"
    [ -z "$pid" ] && echo "" && return

    # Read process start time from /proc (avoids extra subprocess)
    if [ -d "/proc/$pid" ]; then
        local elapsed
        elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$elapsed" ] && [ "$elapsed" -gt 0 ]; then
            local days hours mins
            days=$((elapsed / 86400))
            hours=$(( (elapsed % 86400) / 3600 ))
            mins=$(( (elapsed % 3600) / 60 ))
            if [ "$days" -gt 0 ]; then
                echo "${days}d ${hours}h"
            elif [ "$hours" -gt 0 ]; then
                echo "${hours}h ${mins}m"
            else
                echo "${mins}m"
            fi
            return
        fi
    fi
    echo ""
}

get_cached_rns_version() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_RNS_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_RNS_VER" ]; then
        _CACHE_RNS_VER=$(pip3 show rns 2>/dev/null | grep "^Version:" | awk '{print $2}')
        [ -z "$_CACHE_RNS_VER" ] && _CACHE_RNS_VER=""
        _CACHE_RNS_TIME=$now
    fi
    echo "$_CACHE_RNS_VER"
}

get_cached_lxmf_version() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_LXMF_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_LXMF_VER" ]; then
        _CACHE_LXMF_VER=$(pip3 show lxmf 2>/dev/null | grep "^Version:" | awk '{print $2}')
        [ -z "$_CACHE_LXMF_VER" ] && _CACHE_LXMF_VER=""
        _CACHE_LXMF_TIME=$now
    fi
    echo "$_CACHE_LXMF_VER"
}

# Invalidate all status caches (call after install/service changes)
# Also re-detects tools so menus update after installs
invalidate_status_cache() {
    _CACHE_RNSD_STATUS=""
    _CACHE_RNSD_TIME=0
    _CACHE_RNSD_PID=""
    _CACHE_RNS_VER=""
    _CACHE_RNS_TIME=0
    _CACHE_LXMF_VER=""
    _CACHE_LXMF_TIME=0
    detect_available_tools
}

# Compact status line (adapted from meshforge status_bar.py get_enhanced_status_line)
# Returns: "v0.3.3 | rnsd:● | rns:0.8.x | tools:8/8 | 5m"
get_status_line() {
    local parts=()
    parts+=("v${SCRIPT_VERSION}")

    # rnsd indicator (single char, cached)
    local rnsd_state
    rnsd_state=$(get_cached_rnsd_status)
    if [ "$rnsd_state" = "running" ]; then
        parts+=("rnsd:${GREEN}*${NC}")
    else
        parts+=("rnsd:${RED}-${NC}")
    fi

    # RNS version (cached)
    local rns_ver
    rns_ver=$(get_cached_rns_version)
    if [ -n "$rns_ver" ]; then
        parts+=("rns:${rns_ver}")
    else
        parts+=("rns:${YELLOW}--${NC}")
    fi

    # Tool count
    local tc=0
    [ "$HAS_RNSD" = true ] && ((tc++))
    [ "$HAS_RNSTATUS" = true ] && ((tc++))
    [ "$HAS_RNPATH" = true ] && ((tc++))
    [ "$HAS_RNPROBE" = true ] && ((tc++))
    [ "$HAS_RNCP" = true ] && ((tc++))
    [ "$HAS_RNX" = true ] && ((tc++))
    [ "$HAS_RNID" = true ] && ((tc++))
    [ "$HAS_RNODECONF" = true ] && ((tc++))
    parts+=("tools:${tc}/8")

    # SSH indicator (meshforge hardware detection pattern)
    if [ "$IS_SSH" = true ]; then
        parts+=("SSH")
    fi

    # Session uptime
    local now elapsed_min
    now=$(date +%s)
    elapsed_min=$(( (now - SESSION_START_TIME) / 60 ))
    if [ "$elapsed_min" -lt 1 ]; then
        parts+=("<1m")
    else
        parts+=("${elapsed_min}m")
    fi

    # Join with separator
    local IFS=' | '
    echo -e "${parts[*]}"
}

pause_for_input() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Strip ANSI escape codes for accurate string length measurement
# (adapted from meshforge console.py visible_length)
strip_ansi() {
    local text="$1"
    # Remove all ANSI escape sequences: CSI sequences, OSC, and simple escapes
    echo -e "$text" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b[()][AB012]//g'
}

# Enhanced UI Functions
print_box_line() {
    local content="$1"
    # Use stripped length to avoid ANSI codes inflating padding calculation
    local visible_len=${#content}
    if [ "$HAS_COLOR" = true ]; then
        local stripped
        stripped=$(strip_ansi "$content")
        visible_len=${#stripped}
    fi
    local padding=$((BOX_WIDTH - visible_len - 4))
    [ "$padding" -lt 0 ] && padding=0
    printf '%s│%s %s%*s %s│%s\n' "${BOLD}" "${NC}" "$content" "$padding" "" "${BOLD}" "${NC}"
}

print_box_top() {
    printf '%s┌' "${BOLD}"
    printf '─%.0s' $(seq 1 "$BOX_WIDTH")
    printf '┐%s\n' "${NC}"
}

print_box_bottom() {
    printf '%s└' "${BOLD}"
    printf '─%.0s' $(seq 1 "$BOX_WIDTH")
    printf '┘%s\n' "${NC}"
}

print_box_divider() {
    printf '%s├' "${BOLD}"
    printf '─%.0s' $(seq 1 "$BOX_WIDTH")
    printf '┤%s\n' "${NC}"
}

print_breadcrumb() {
    if [ -n "$MENU_BREADCRUMB" ]; then
        echo -e "${CYAN}Location:${NC} $MENU_BREADCRUMB"
        echo ""
    fi
}

show_help() {
    print_header
    echo -e "${BOLD}Help & Quick Reference${NC}\n"
    echo -e "${CYAN}Navigation:${NC}"
    echo "  • Enter the number of your choice and press Enter"
    echo "  • Press 0 to go back or exit"
    echo "  • Press h or ? for help in most menus"
    echo ""
    echo -e "${CYAN}Key Components:${NC}"
    echo "  • ${BOLD}RNS${NC} - Reticulum Network Stack (core networking)"
    echo "  • ${BOLD}LXMF${NC} - Lightweight Extensible Message Format"
    echo "  • ${BOLD}NomadNet${NC} - Terminal-based messaging client"
    echo "  • ${BOLD}MeshChat${NC} - Web-based LXMF messaging interface"
    echo "  • ${BOLD}Sideband${NC} - Mobile/Desktop LXMF client"
    echo "  • ${BOLD}RNODE${NC} - LoRa radio hardware for long-range links"
    echo ""
    echo -e "${CYAN}Common Tasks:${NC}"
    echo "  • Start daemon:    ${GREEN}rnsd --daemon${NC}"
    echo "  • Check status:    ${GREEN}rnstatus${NC}"
    echo "  • Launch NomadNet: ${GREEN}nomadnet${NC}"
    echo "  • Configure RNODE: ${GREEN}rnodeconf --autoinstall${NC}"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo "  • ~/.reticulum/config   - Main RNS configuration"
    echo "  • ~/.nomadnetwork/      - NomadNet settings"
    echo "  • ~/.lxmf/              - LXMF message store"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  • https://reticulum.network/"
    echo "  • https://github.com/markqvist/Reticulum"
    echo ""
    pause_for_input
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"  # Default to 'n' if not specified

    if [ "$default" = "y" ]; then
        echo -n "$message (Y/n): "
        read -r response
        [[ ! "$response" =~ ^[Nn]$ ]]
    else
        echo -n "$message (y/N): "
        read -r response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

show_operation_summary() {
    local title="$1"
    shift
    local items=("$@")

    echo ""
    print_box_top
    print_box_line "${CYAN}${BOLD}$title${NC}"
    print_box_divider

    for item in "${items[@]}"; do
        print_box_line "  $item"
    done

    print_box_bottom
    echo ""
}

#########################################################
# Main Menu System
#########################################################

show_main_menu() {
    print_header
    MENU_BREADCRUMB=""

    # Quick status dashboard with cached queries (meshforge status_bar.py pattern)
    print_box_top
    print_box_line "${CYAN}${BOLD}Quick Status${NC}"
    print_box_divider

    # Check rnsd status (cached, avoids pgrep on every redraw)
    local rnsd_state rnsd_uptime
    rnsd_state=$(get_cached_rnsd_status)
    if [ "$rnsd_state" = "running" ]; then
        rnsd_uptime=$(get_rnsd_uptime)
        if [ -n "$rnsd_uptime" ]; then
            print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC} (up ${rnsd_uptime})"
        else
            print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}"
        fi
    else
        print_box_line "${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}"
    fi

    # Check RNS installed (cached version query)
    local rns_ver
    rns_ver=$(get_cached_rns_version)
    if [ -n "$rns_ver" ]; then
        print_box_line "${GREEN}●${NC} RNS: v${rns_ver}"
    else
        print_box_line "${YELLOW}○${NC} RNS: ${YELLOW}Not installed${NC}"
    fi

    # Check LXMF installed (cached version query)
    local lxmf_ver
    lxmf_ver=$(get_cached_lxmf_version)
    if [ -n "$lxmf_ver" ]; then
        print_box_line "${GREEN}●${NC} LXMF: v${lxmf_ver}"
    else
        print_box_line "${YELLOW}○${NC} LXMF: Not installed"
    fi

    # Tool availability summary
    local tool_count=0
    [ "$HAS_RNSD" = true ] && ((tool_count++))
    [ "$HAS_RNSTATUS" = true ] && ((tool_count++))
    [ "$HAS_RNPATH" = true ] && ((tool_count++))
    [ "$HAS_RNPROBE" = true ] && ((tool_count++))
    [ "$HAS_RNCP" = true ] && ((tool_count++))
    [ "$HAS_RNX" = true ] && ((tool_count++))
    [ "$HAS_RNID" = true ] && ((tool_count++))
    [ "$HAS_RNODECONF" = true ] && ((tool_count++))
    if [ "$tool_count" -eq 8 ]; then
        print_box_line "${GREEN}●${NC} RNS tools: ${tool_count}/8 available"
    elif [ "$tool_count" -gt 0 ]; then
        print_box_line "${YELLOW}●${NC} RNS tools: ${tool_count}/8 available"
    else
        print_box_line "${RED}○${NC} RNS tools: none detected"
    fi

    print_box_bottom
    echo ""

    echo -e "${BOLD}Main Menu:${NC}"
    echo ""
    echo -e "  ${CYAN}─── Installation ───${NC}"
    echo "   1) Install/Update Reticulum Ecosystem"
    echo "   2) Install/Configure RNODE Device"
    echo "   3) Install NomadNet"
    echo "   4) Install MeshChat"
    echo "   5) Install Sideband"
    echo ""
    echo -e "  ${CYAN}─── Management ───${NC}"
    echo "   6) System Status & Diagnostics"
    echo "   7) Manage Services"
    echo "   8) Backup/Restore Configuration"
    echo "   9) Advanced Options"
    echo ""
    echo -e "  ${CYAN}─── Quick & Help ───${NC}"
    echo "   q) Quick Mode (field operations)"
    echo "   h) Help & Quick Reference"
    echo "   0) Exit"
    echo ""
    echo -n "Select an option: "
    read -r MENU_CHOICE
}

#########################################################
# System Detection and Prerequisites
#########################################################

# Disk space pre-check (adapted from meshforge diagnostics)
# Returns 0 if sufficient, 1 if low, 2 if critical
check_disk_space() {
    local min_mb="${1:-500}"  # Default: 500MB minimum
    local target_path="${2:-$REAL_HOME}"

    if ! command -v df &> /dev/null; then
        log_warn "df command not available, skipping disk check"
        return 0
    fi

    local available_mb
    available_mb=$(df -m "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available_mb" ]; then
        log_warn "Could not determine disk space for $target_path"
        return 0
    fi

    log_debug "Disk space available: ${available_mb}MB at $target_path (minimum: ${min_mb}MB)"

    if [ "$available_mb" -lt 100 ]; then
        print_error "Critical: Only ${available_mb}MB disk space available (need ${min_mb}MB)"
        log_error "Critical disk space: ${available_mb}MB at $target_path"
        return 2
    elif [ "$available_mb" -lt "$min_mb" ]; then
        print_warning "Low disk space: ${available_mb}MB available (recommend ${min_mb}MB)"
        log_warn "Low disk space: ${available_mb}MB at $target_path"
        return 1
    fi

    return 0
}

# Memory pre-check (adapted from meshforge system.py check_memory)
check_available_memory() {
    if [ ! -f /proc/meminfo ]; then
        log_debug "No /proc/meminfo, skipping memory check"
        return 0
    fi

    local total_kb available_kb percent_free
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)

    if [ -z "$total_kb" ] || [ -z "$available_kb" ] || [ "$total_kb" -eq 0 ]; then
        log_warn "Could not parse memory info"
        return 0
    fi

    local total_mb=$((total_kb / 1024))
    local available_mb=$((available_kb / 1024))
    percent_free=$((available_kb * 100 / total_kb))

    log_debug "Memory: ${available_mb}MB free of ${total_mb}MB (${percent_free}%)"

    if [ "$percent_free" -lt 10 ]; then
        print_warning "Low memory: ${available_mb}MB free (${percent_free}%)"
        print_info "Hint: Free up memory or add swap space"
        log_warn "Low memory: ${available_mb}MB free (${percent_free}%)"
        return 1
    fi

    return 0
}

# Git safe.directory guard (adapted from meshforge install.sh)
# Prevents "dubious ownership" errors when running as root
ensure_git_safe_directory() {
    local dir="$1"
    if [ -d "$dir/.git" ] && [ "$(id -u)" -eq 0 ]; then
        git config --global --add safe.directory "$dir" 2>/dev/null || true
        log_debug "Added git safe.directory: $dir"
    fi
}

check_python() {
    print_section "Checking Python Installation"

    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 7 ]; then
            print_success "Python $PYTHON_VERSION detected"
            log_message "Python version: $PYTHON_VERSION"
            return 0
        else
            print_error "Python $PYTHON_VERSION is too old (requires 3.7+)"
            return 1
        fi
    else
        print_error "Python3 not found"
        return 1
    fi
}

check_pip() {
    print_section "Checking pip Installation"

    if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
        if command -v pip3 &> /dev/null; then
            PIP_CMD="pip3"
        else
            PIP_CMD="pip"
        fi
        PIP_VERSION=$($PIP_CMD --version 2>&1 | awk '{print $2}')
        print_success "pip $PIP_VERSION detected"
        log_message "pip version: $PIP_VERSION"
        return 0
    else
        print_error "pip not found"
        return 1
    fi
}

install_prerequisites() {
    print_section "Installing Prerequisites"

    local packages=("python3" "python3-pip" "git" "curl" "wget" "build-essential")

    if [ "$IS_RASPBERRY_PI" = true ]; then
        packages+=("python3-dev" "libffi-dev" "libssl-dev")
    fi

    echo -e "${YELLOW}The following packages will be installed:${NC}"
    printf '  - %s\n' "${packages[@]}"
    echo ""
    if ! confirm_action "Proceed with installation?" "y"; then
        print_warning "Skipping prerequisites installation"
        return 1
    fi

    print_info "Updating package lists..."
    if retry_with_backoff 3 run_with_timeout "$APT_TIMEOUT" sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Installing prerequisites..."
        if retry_with_backoff 2 run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Prerequisites installed successfully"
            log_message "Prerequisites installed: ${packages[*]}"
            return 0
        else
            print_error "Failed to install some prerequisites"
            return 1
        fi
    else
        print_error "Failed to update package lists (timeout after ${APT_TIMEOUT}s)"
        return 1
    fi
}

#########################################################
# Node.js Installation (Modern Method)
#########################################################

install_nodejs_modern() {
    print_section "Installing Modern Node.js"

    # Check if nodejs is already installed and up to date
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        if [ "$NODE_MAJOR" -ge 18 ]; then
            print_success "Node.js $NODE_VERSION is already installed"

            # Update npm if needed
            NPM_VERSION=$(npm --version 2>/dev/null | cut -d. -f1)
            if [ -n "$NPM_VERSION" ] && [ "$NPM_VERSION" -lt 10 ]; then
                print_info "Updating npm to latest version..."
                sudo npm install -g npm@latest 2>&1 | tee -a "$UPDATE_LOG"
            fi
            return 0
        else
            print_warning "Node.js $NODE_VERSION is outdated, upgrading..."
        fi
    fi

    print_info "Installing Node.js 22.x LTS from NodeSource..."
    log_message "Installing Node.js from NodeSource"

    # Install curl if not present
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y curl 2>&1 | tee -a "$UPDATE_LOG"
    fi

    # Install NodeSource repository for Node.js 22.x (LTS) - with retry
    if retry_with_backoff 3 run_with_timeout "$NETWORK_TIMEOUT" curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "NodeSource repository configured"

        # Install Node.js (includes npm)
        if run_with_timeout "$APT_TIMEOUT" sudo apt install -y nodejs 2>&1 | tee -a "$UPDATE_LOG"; then
            NODE_VERSION=$(node --version)
            NPM_VERSION=$(npm --version)
            print_success "Node.js $NODE_VERSION and npm $NPM_VERSION installed"
            log_message "Installed Node.js $NODE_VERSION and npm $NPM_VERSION"
            return 0
        else
            print_error "Failed to install Node.js"
            log_message "Node.js installation failed"
            return 1
        fi
    else
        print_error "Failed to add NodeSource repository"
        print_warning "Falling back to system Node.js (may be outdated)"
        log_message "NodeSource setup failed, using system nodejs"

        # Fallback to system packages
        run_with_timeout "$APT_TIMEOUT" sudo apt update
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y nodejs npm 2>&1 | tee -a "$UPDATE_LOG"

        print_warning "System Node.js installed - may be outdated"
        return 0
    fi
}

check_nodejs_version() {
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        print_info "Node.js version: $NODE_VERSION"

        if [ "$NODE_MAJOR" -lt 18 ]; then
            print_error "Node.js version $NODE_VERSION is too old (requires 18+)"
            if confirm_action "Upgrade Node.js now?" "y"; then
                install_nodejs_modern
                return $?
            else
                return 1
            fi
        else
            print_success "Node.js version $NODE_VERSION is compatible"
            log_message "Node.js version check passed: $NODE_VERSION"
            return 0
        fi
    else
        print_warning "Node.js not found"
        return 1
    fi
}

#########################################################
# RNODE Installation and Configuration
#########################################################

install_rnode_tools() {
    print_section "Installing RNODE Tools"

    echo -e "${CYAN}${BOLD}RNODE Installation Guide${NC}\n"
    echo "This will install the RNode configuration utility (rnodeconf)"
    echo "which allows you to:"
    echo "  • Flash RNode firmware to supported devices"
    echo "  • Configure radio parameters"
    echo "  • Test and diagnose RNODE devices"
    echo ""

    # rnodeconf is part of the rns package
    print_info "Installing/Updating RNS (includes rnodeconf)..."

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "RNS and rnodeconf installed successfully"

        # Verify rnodeconf is available
        if command -v rnodeconf &> /dev/null; then
            RNODECONF_VERSION=$(rnodeconf --version 2>&1 | head -1 || echo "unknown")
            print_success "rnodeconf is ready: $RNODECONF_VERSION"
            log_message "rnodeconf installed: $RNODECONF_VERSION"
            return 0
        else
            print_warning "rnodeconf installed but not in PATH"
            print_info "You may need to restart your shell or run: hash -r"
            return 0
        fi
    else
        print_error "Failed to install RNS/rnodeconf"
        log_message "RNS installation failed"
        return 1
    fi
}

#########################################################
# RNODE Helper Functions (Decomposed for maintainability)
#########################################################

# Helper: Prompt and validate device port
rnode_get_device_port() {
    echo "Enter the device port (e.g., /dev/ttyUSB0, /dev/ttyACM0):"
    echo -n "Device port: "
    read -r DEVICE_PORT

    # RNS002: Device port validation
    if [[ ! "$DEVICE_PORT" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
        print_error "Invalid device port format. Expected: /dev/ttyUSB0 or /dev/ttyACM0"
        return 1
    fi

    if [ ! -e "$DEVICE_PORT" ]; then
        print_error "Device not found: $DEVICE_PORT"
        return 1
    fi

    echo "$DEVICE_PORT"
    return 0
}

# RNODE: Auto-install firmware
rnode_autoinstall() {
    print_section "Auto-Installing RNODE Firmware"
    echo -e "${YELLOW}This will automatically detect and flash your RNODE device.${NC}"
    echo -e "${YELLOW}Make sure your device is connected via USB.${NC}"
    echo ""

    if confirm_action "Continue?" "y"; then
        print_info "Running rnodeconf --autoinstall..."
        echo ""
        rnodeconf --autoinstall 2>&1 | tee -a "$UPDATE_LOG"

        if [ "${PIPESTATUS[0]}" -eq 0 ]; then
            print_success "RNODE firmware installed successfully!"
            log_message "RNODE autoinstall completed"
        else
            print_error "RNODE installation failed"
            print_info "Check the output above for errors"
            log_message "RNODE autoinstall failed"
        fi
    fi
}

# RNODE: List supported devices
rnode_list_devices() {
    print_section "Supported RNODE Devices"
    echo -e "${CYAN}Listing supported devices...${NC}\n"
    rnodeconf --list 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Flash specific device
rnode_flash_device() {
    print_section "Flash Specific Device"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Flashing device at $device_port..."
    rnodeconf "$device_port" 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Update existing device
rnode_update_device() {
    print_section "Update Existing RNODE"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Updating device at $device_port..."
    rnodeconf "$device_port" --update 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Get device information
rnode_get_info() {
    print_section "Get Device Information"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Getting device information..."
    rnodeconf "$device_port" --info 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Configure radio parameters
rnode_configure_radio() {
    print_section "Configure Radio Parameters"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    echo ""
    echo -e "${CYAN}Radio Parameter Configuration${NC}"
    echo "Leave blank to keep current value"
    echo ""

    # Build command with optional parameters using arrays (safer than eval)
    declare -a CMD_ARGS=("$device_port")

    # RNS003: Numeric range validation for all parameters
    # Frequency (validate numeric input)
    echo -n "Frequency in Hz (e.g., 915000000 for 915MHz): "
    read -r FREQ
    if [ -n "$FREQ" ]; then
        if [[ "$FREQ" =~ ^[0-9]+$ ]]; then
            CMD_ARGS+=("--freq" "$FREQ")
        else
            print_warning "Invalid frequency - must be numeric. Skipping."
        fi
    fi

    # Bandwidth (validate numeric input)
    echo -n "Bandwidth in kHz (e.g., 125, 250, 500): "
    read -r BW
    if [ -n "$BW" ]; then
        if [[ "$BW" =~ ^[0-9]+$ ]]; then
            CMD_ARGS+=("--bw" "$BW")
        else
            print_warning "Invalid bandwidth - must be numeric. Skipping."
        fi
    fi

    # Spreading Factor (validate range 7-12)
    echo -n "Spreading Factor (7-12): "
    read -r SF
    if [ -n "$SF" ]; then
        if [[ "$SF" =~ ^[0-9]+$ ]] && [ "$SF" -ge 7 ] && [ "$SF" -le 12 ]; then
            CMD_ARGS+=("--sf" "$SF")
        else
            print_warning "Invalid spreading factor - must be 7-12. Skipping."
        fi
    fi

    # Coding Rate (validate range 5-8)
    echo -n "Coding Rate (5-8): "
    read -r CR
    if [ -n "$CR" ]; then
        if [[ "$CR" =~ ^[0-9]+$ ]] && [ "$CR" -ge 5 ] && [ "$CR" -le 8 ]; then
            CMD_ARGS+=("--cr" "$CR")
        else
            print_warning "Invalid coding rate - must be 5-8. Skipping."
        fi
    fi

    # TX Power (validate reasonable dBm range)
    echo -n "TX Power in dBm (e.g., 17): "
    read -r TXP
    if [ -n "$TXP" ]; then
        if [[ "$TXP" =~ ^-?[0-9]+$ ]] && [ "$TXP" -ge -10 ] && [ "$TXP" -le 30 ]; then
            CMD_ARGS+=("--txp" "$TXP")
        else
            print_warning "Invalid TX power - must be between -10 and 30 dBm. Skipping."
        fi
    fi

    echo ""
    print_info "Executing: rnodeconf ${CMD_ARGS[*]}"
    rnodeconf "${CMD_ARGS[@]}" 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Set device model and platform
rnode_set_model() {
    print_section "Set Device Model and Platform"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    echo ""
    echo -e "${CYAN}Device Model/Platform Configuration${NC}"
    echo ""
    print_info "Run 'rnodeconf --list' to see supported models"
    echo ""

    echo -n "Model (e.g., t3s3, lora32_v2_1): "
    read -r MODEL

    echo -n "Platform (e.g., esp32, rp2040): "
    read -r PLATFORM

    # Build command with array (safer than eval)
    declare -a CMD_ARGS=("$device_port")

    # Validate model (alphanumeric and underscores only)
    if [ -n "$MODEL" ]; then
        if [[ "$MODEL" =~ ^[a-zA-Z0-9_]+$ ]]; then
            CMD_ARGS+=("--model" "$MODEL")
        else
            print_warning "Invalid model name. Skipping."
        fi
    fi

    # Validate platform (alphanumeric only)
    if [ -n "$PLATFORM" ]; then
        if [[ "$PLATFORM" =~ ^[a-zA-Z0-9]+$ ]]; then
            CMD_ARGS+=("--platform" "$PLATFORM")
        else
            print_warning "Invalid platform name. Skipping."
        fi
    fi

    echo ""
    print_info "Executing: rnodeconf ${CMD_ARGS[*]}"
    rnodeconf "${CMD_ARGS[@]}" 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: View/edit EEPROM
rnode_eeprom() {
    print_section "View/Edit Device EEPROM"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Reading device EEPROM..."
    rnodeconf "$device_port" --eeprom 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Update bootloader
rnode_bootloader() {
    print_section "Update Bootloader (ROM)"
    echo -e "${YELLOW}WARNING: This will update the device bootloader.${NC}"
    echo -e "${YELLOW}Only proceed if you know what you're doing!${NC}"
    echo ""

    local device_port
    device_port=$(rnode_get_device_port) || return 1

    # RNS005: Confirmation for destructive actions
    if confirm_action "Are you sure you want to update the bootloader?"; then
        print_info "Updating bootloader..."
        rnodeconf "$device_port" --rom 2>&1 | tee -a "$UPDATE_LOG"
    else
        print_info "Bootloader update cancelled"
    fi
}

# RNODE: Open serial console
rnode_serial_console() {
    print_section "Open Serial Console"
    local device_port
    device_port=$(rnode_get_device_port) || return 1

    print_info "Opening serial console for $device_port..."
    print_info "Press Ctrl+C to exit"
    echo ""
    rnodeconf "$device_port" --console 2>&1 | tee -a "$UPDATE_LOG"
}

# RNODE: Show help
rnode_show_help() {
    print_section "All RNODE Configuration Options"
    echo -e "${CYAN}Displaying full rnodeconf help...${NC}\n"
    rnodeconf --help 2>&1 | less
}

#########################################################
# RNODE Interactive Menu (Dispatcher)
#########################################################

configure_rnode_interactive() {
    print_header
    MENU_BREADCRUMB="Main Menu > RNODE Configuration"
    print_breadcrumb

    # Check if rnodeconf is available
    if ! command -v rnodeconf &> /dev/null; then
        print_error "rnodeconf not found"
        echo ""
        if confirm_action "Install rnodeconf now?" "y"; then
            install_rnode_tools || return 1
        else
            return 1
        fi
    fi

    echo -e "${BOLD}RNODE Configuration Wizard${NC}\n"

    # Show detected devices
    local devices
    devices=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null)
    if [ -n "$devices" ]; then
        echo -e "${GREEN}Detected USB devices:${NC}"
        echo "$devices" | while read -r dev; do
            echo "  • $dev"
        done
        echo ""
    fi

    echo -e "  ${CYAN}─── Basic Operations ───${NC}"
    echo "    1) Auto-install firmware (recommended)"
    echo "    2) List supported devices"
    echo "    3) Flash specific device"
    echo "    4) Update existing RNODE"
    echo "    5) Get device information"
    echo ""
    echo -e "  ${CYAN}─── Hardware Configuration ───${NC}"
    echo "    6) Configure radio parameters"
    echo "    7) Set device model and platform"
    echo "    8) View/edit device EEPROM"
    echo "    9) Update bootloader (ROM)"
    echo ""
    echo "  ${BOLD}Advanced Tools:${NC}"
    echo "   10) Open serial console"
    echo "   11) Show all rnodeconf options"
    echo "    0) Back to main menu"
    echo ""
    echo -n "Select an option: "
    read -r RNODE_CHOICE

    case $RNODE_CHOICE in
        1)  rnode_autoinstall ;;
        2)  rnode_list_devices ;;
        3)  rnode_flash_device ;;
        4)  rnode_update_device ;;
        5)  rnode_get_info ;;
        6)  rnode_configure_radio ;;
        7)  rnode_set_model ;;
        8)  rnode_eeprom ;;
        9)  rnode_bootloader ;;
        10) rnode_serial_console ;;
        11) rnode_show_help ;;
        0)  return 0 ;;
        *)  print_error "Invalid option" ;;
    esac

    pause_for_input
    configure_rnode_interactive
}

#########################################################
# Component Installation Functions
#########################################################

get_installed_version() {
    local package=$1
    "$PIP_CMD" show "$package" 2>/dev/null | grep "^Version:" | awk '{print $2}'
}

check_package_installed() {
    local package=$1
    local display_name=$2

    VERSION=$(get_installed_version "$package")

    if [ -n "$VERSION" ]; then
        print_info "$display_name: v$VERSION (installed)"
        log_message "$display_name installed: $VERSION"
        echo "$VERSION"
        return 0
    else
        print_warning "$display_name: not installed"
        log_message "$display_name not installed"
        echo ""
        return 1
    fi
}

update_pip_package() {
    local package=$1
    local display_name=$2

    print_section "Installing/Updating $display_name"

    OLD_VERSION=$(get_installed_version "$package")

    if [ -z "$OLD_VERSION" ]; then
        print_info "Installing $display_name..."
        log_message "Installing $display_name"
    else
        print_info "Current version: $OLD_VERSION"
        print_info "Checking for updates..."
        log_message "Updating $display_name from $OLD_VERSION"
    fi

    # Try update with --break-system-packages flag (needed on newer systems) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install "$package" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        NEW_VERSION=$(get_installed_version "$package")

        if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
            print_success "$display_name updated: $OLD_VERSION → $NEW_VERSION"
            log_message "$display_name updated to $NEW_VERSION"
        else
            print_success "$display_name is up to date: $NEW_VERSION"
            log_message "$display_name already latest: $NEW_VERSION"
        fi
        return 0
    else
        print_error "Failed to install/update $display_name"
        log_message "Failed to update $display_name"

        # Offer troubleshooting
        echo -e "\n${YELLOW}Troubleshooting options:${NC}"
        echo "  1) Check internet connection"
        echo "  2) Try updating pip: pip3 install --upgrade pip"
        echo "  3) Check system requirements"

        return 1
    fi
}

install_reticulum_ecosystem() {
    print_section "Installing Reticulum Ecosystem"

    echo -e "${CYAN}This will install/update the complete Reticulum stack:${NC}"
    echo "  • RNS (Reticulum Network Stack) - Core networking"
    echo "  • LXMF - Messaging protocol layer"
    echo "  • NomadNet - Terminal messaging client (optional)"
    echo ""

    # Ask about NomadNet upfront so progress steps are accurate
    local install_nomad=false
    if confirm_action "Include NomadNet (terminal client)?" "y"; then
        install_nomad=true
    fi

    # Step-based progress display (wire up dead code from meshforge pattern)
    if [ "$install_nomad" = true ]; then
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation" \
            "Install/update NomadNet" \
            "Verify NomadNet installation"
    else
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation"
    fi

    local success=true

    # RNS first (core dependency) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
        # Verify RNS installation (meshforge post-install verify pattern)
        if python3 -c "import RNS; print(f'RNS {RNS.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "RNS installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # LXMF (depends on RNS) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install lxmf --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
        # Verify LXMF installation
        if python3 -c "import LXMF; print(f'LXMF {LXMF.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "LXMF installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # NomadNet (optional)
    if [ "$install_nomad" = true ]; then
        if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install nomadnet --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
            next_step "success"
            if python3 -c "import nomadnet" 2>/dev/null; then
                next_step "success"
            else
                next_step "fail"
                print_warning "NomadNet installed but import verification failed"
            fi
        else
            next_step "fail"
            next_step "skip"
            success=false
        fi
    fi

    # Invalidate version cache so dashboard refreshes
    invalidate_status_cache

    if [ "$success" = true ]; then
        complete_operation "success"
        return 0
    else
        complete_operation "fail"
        show_error_help "pip" ""
        return 1
    fi
}

check_meshchat_installed() {
    if [ -d "$MESHCHAT_DIR" ] && [ -f "$MESHCHAT_DIR/package.json" ]; then
        MESHCHAT_VERSION=$(grep '"version"' "$MESHCHAT_DIR/package.json" | head -1 | awk -F'"' '{print $4}')
        print_info "MeshChat: v$MESHCHAT_VERSION (installed)"
        log_message "MeshChat installed: $MESHCHAT_VERSION"
        return 0
    else
        print_warning "MeshChat: not installed"
        log_message "MeshChat not installed"
        return 1
    fi
}

install_meshchat() {
    print_section "Installing MeshChat"

    # Disk space pre-check (MeshChat clone + npm install needs ~500MB)
    if ! check_disk_space 500 "$REAL_HOME"; then
        print_error "Insufficient disk space for MeshChat installation"
        return 1
    fi

    # Check for Node.js
    if ! command -v npm &> /dev/null; then
        print_warning "Node.js/npm not found"
        echo -e "${YELLOW}MeshChat requires Node.js 18+${NC}"
        if confirm_action "Install Node.js now?" "y"; then
            install_nodejs_modern || return 1
        else
            return 1
        fi
    else
        check_nodejs_version || return 1
    fi

    # Check for git
    if ! command -v git &> /dev/null; then
        print_info "Installing git..."
        run_with_timeout "$APT_TIMEOUT" sudo apt update && run_with_timeout "$APT_TIMEOUT" sudo apt install -y git
    fi

    log_message "Installing MeshChat"
    local is_update=false

    if [ -d "$MESHCHAT_DIR" ]; then
        print_warning "MeshChat directory already exists"
        if confirm_action "Update existing installation?" "y"; then
            is_update=true
        else
            return 1
        fi
    fi

    # Step-based progress (wiring up init_operation from meshforge pattern)
    init_operation "Installing MeshChat" \
        "Clone/update repository" \
        "Install npm dependencies" \
        "Security audit" \
        "Build application" \
        "Verify installation"

    # Step 1: Clone or update
    if [ "$is_update" = true ]; then
        pushd "$MESHCHAT_DIR" > /dev/null || return 1
        ensure_git_safe_directory "$MESHCHAT_DIR"
        if retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git pull origin main 2>&1 | tee -a "$UPDATE_LOG"; then
            next_step "success"
        else
            next_step "fail"
            popd > /dev/null || true
            complete_operation "fail"
            return 1
        fi
    else
        if retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git clone https://github.com/liamcottle/reticulum-meshchat.git "$MESHCHAT_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$MESHCHAT_DIR" > /dev/null || return 1
            next_step "success"
        else
            next_step "fail"
            print_error "Failed to clone MeshChat repository"
            complete_operation "fail"
            show_error_help "git" ""
            return 1
        fi
    fi

    # Step 2: npm install (with retry)
    if retry_with_backoff 2 run_with_timeout "$NETWORK_TIMEOUT" npm install 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
    else
        next_step "fail"
        popd > /dev/null || true
        complete_operation "fail"
        show_error_help "nodejs" ""
        return 1
    fi

    # Step 3: Security audit (non-fatal)
    npm audit fix --audit-level=moderate 2>&1 | tee -a "$UPDATE_LOG" || true
    next_step "success"

    # Step 4: Build
    if npm run build 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
    else
        next_step "fail"
        popd > /dev/null || true
        complete_operation "fail"
        return 1
    fi

    # Step 5: Verify installation
    if [ -f "package.json" ]; then
        MESHCHAT_VERSION=$(grep '"version"' package.json | head -1 | awk -F'"' '{print $4}')
        print_success "MeshChat v$MESHCHAT_VERSION installed successfully"
        log_message "MeshChat installed: $MESHCHAT_VERSION"
        create_meshchat_launcher
        next_step "success"
    else
        next_step "fail"
    fi

    popd > /dev/null || true
    complete_operation "success"
    return 0
}

create_meshchat_launcher() {
    if [ -n "$DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_info "Creating desktop launcher..."

        DESKTOP_FILE="$REAL_HOME/.local/share/applications/meshchat.desktop"
        mkdir -p "$REAL_HOME/.local/share/applications"

        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Reticulum MeshChat
Comment=LXMF messaging client for Reticulum
Exec=bash -c 'cd $MESHCHAT_DIR && npm run dev'
Icon=$MESHCHAT_DIR/icon.png
Terminal=false
Categories=Network;Communication;
EOF

        chmod +x "$DESKTOP_FILE"
        print_success "Desktop launcher created"
        log_message "Created desktop launcher"
    fi
}

#########################################################
# Sideband Installation
#########################################################

install_sideband() {
    print_section "Installing Sideband"

    echo -e "${CYAN}${BOLD}About Sideband${NC}\n"
    echo "Sideband is a graphical LXMF messaging application that provides:"
    echo "  • Secure end-to-end encrypted messaging"
    echo "  • Works over any medium Reticulum supports"
    echo "  • Available for Linux, macOS, Windows, and Android"
    echo ""

    # Check Python first
    if ! check_python || ! check_pip; then
        print_error "Python 3.7+ and pip are required"
        return 1
    fi

    # Check for display (Sideband is a GUI app)
    if [ -z "$DISPLAY" ] && [ -z "$XDG_CURRENT_DESKTOP" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        print_warning "No graphical display detected"
        echo ""
        echo "Sideband requires a graphical environment to run."
        echo "On headless systems, consider using NomadNet (terminal client) instead."
        echo ""
        if ! confirm_action "Continue anyway?"; then
            return 1
        fi
    fi

    # Installation method menu
    echo -e "${BOLD}Installation Options:${NC}\n"
    echo "   1) Install via pip (recommended for Linux)"
    echo "   2) Install from source (latest development version)"
    echo "   3) Download AppImage (portable, no installation)"
    echo "   4) Show platform-specific instructions"
    echo "   0) Cancel"
    echo ""
    echo -n "Select installation method: "
    read -r INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            install_sideband_pip
            ;;
        2)
            install_sideband_source
            ;;
        3)
            download_sideband_appimage
            ;;
        4)
            show_sideband_platform_instructions
            ;;
        0|"")
            print_info "Installation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

install_sideband_pip() {
    print_section "Installing Sideband via pip"

    # Check for required system dependencies
    print_info "Checking system dependencies..."

    local missing_deps=()

    # Check for required packages for GUI
    if ! dpkg -l | grep -q "python3-tk"; then
        missing_deps+=("python3-tk")
    fi
    if ! dpkg -l | grep -q "python3-pil"; then
        missing_deps+=("python3-pil" "python3-pil.imagetk")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Installing required dependencies..."
        run_with_timeout "$APT_TIMEOUT" sudo apt update
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${missing_deps[@]}" 2>&1 | tee -a "$UPDATE_LOG"
    fi

    print_info "Installing Sideband..."

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install sbapp --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed successfully"

        # Verify installation
        if command -v sideband &> /dev/null || "$PIP_CMD" show sbapp &>/dev/null; then
            local sb_version
            sb_version=$($PIP_CMD show sbapp 2>/dev/null | grep "^Version:" | awk '{print $2}')
            print_success "Sideband v$sb_version is ready"
            log_message "Installed Sideband v$sb_version"

            # Create desktop launcher
            create_sideband_launcher

            echo ""
            print_info "To launch Sideband, run: ${GREEN}sideband${NC}"
        else
            print_warning "Installation completed but sideband command not found"
            print_info "Try: python3 -m sbapp"
        fi
        return 0
    else
        print_error "Failed to install Sideband"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1) Ensure you have Python 3.7 or newer"
        echo "  2) Try: pip3 install --user sbapp"
        echo "  3) Check internet connection"
        log_message "Sideband installation failed"
        return 1
    fi
}

install_sideband_source() {
    print_section "Installing Sideband from Source"

    if [ -d "$SIDEBAND_DIR" ]; then
        print_warning "Sideband directory already exists"
        if confirm_action "Update existing installation?" "y"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
            print_info "Updating from git..."
            git pull origin main 2>&1 | tee -a "$UPDATE_LOG"
        else
            return 1
        fi
    else
        print_info "Cloning Sideband repository..."
        if run_with_timeout "$GIT_TIMEOUT" git clone https://github.com/markqvist/Sideband.git "$SIDEBAND_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
        else
            print_error "Failed to clone Sideband repository"
            return 1
        fi
    fi

    print_info "Installing from source..."
    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install . --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed from source"
        create_sideband_launcher
        popd > /dev/null || true
        return 0
    else
        print_error "Failed to install Sideband from source"
        popd > /dev/null || true
        return 1
    fi
}

download_sideband_appimage() {
    print_section "Downloading Sideband AppImage"

    local appimage_url="https://github.com/markqvist/Sideband/releases/latest"

    echo -e "${YELLOW}AppImage is a portable format that runs without installation.${NC}"
    echo ""
    echo "Please visit the releases page to download the latest AppImage:"
    echo -e "  ${CYAN}$appimage_url${NC}"
    echo ""
    echo "After downloading:"
    echo "  1) Make it executable: chmod +x Sideband*.AppImage"
    echo "  2) Run it: ./Sideband*.AppImage"
    echo ""

    # Try to open browser if available
    if command -v xdg-open &> /dev/null && [ -n "$DISPLAY" ]; then
        if confirm_action "Open releases page in browser?" "y"; then
            xdg-open "$appimage_url" 2>/dev/null &
            print_success "Opened browser"
        fi
    fi
}

show_sideband_platform_instructions() {
    print_section "Platform-Specific Instructions"

    echo -e "${BOLD}Linux (Debian/Ubuntu):${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the AppImage from GitHub releases"
    echo ""

    echo -e "${BOLD}Raspberry Pi:${NC}"
    echo "  pip3 install sbapp --break-system-packages"
    echo "  Note: May require extra time to build on older Pi models"
    echo ""

    echo -e "${BOLD}macOS:${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the .dmg from GitHub releases"
    echo ""

    echo -e "${BOLD}Windows:${NC}"
    echo "  pip install sbapp"
    echo "  or download the .exe installer from GitHub releases"
    echo ""

    echo -e "${BOLD}Android:${NC}"
    echo "  Download from F-Droid or GitHub releases (.apk)"
    echo "  Note: Sideband is also available on Google Play"
    echo ""

    echo -e "${CYAN}GitHub Releases:${NC}"
    echo "  https://github.com/markqvist/Sideband/releases"
}

create_sideband_launcher() {
    if [ -n "$DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_info "Creating desktop launcher..."

        DESKTOP_FILE="$REAL_HOME/.local/share/applications/sideband.desktop"
        mkdir -p "$REAL_HOME/.local/share/applications"

        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Sideband
Comment=LXMF Messaging Client for Reticulum
Exec=sideband
Icon=sideband
Terminal=false
Categories=Network;Communication;
Keywords=lxmf;reticulum;mesh;messaging;
EOF

        chmod +x "$DESKTOP_FILE"
        print_success "Desktop launcher created"
        log_message "Created Sideband desktop launcher"
    fi
}

#########################################################
# Service Management
#########################################################

stop_services() {
    print_section "Stopping Services"

    # Stop rnsd if running (improved detection from meshforge service_menu_mixin.py)
    if is_rnsd_running; then
        print_info "Stopping rnsd daemon..."
        rnsd --daemon stop 2>/dev/null || pkill -x rnsd 2>/dev/null

        # Poll with timeout instead of hardcoded sleep (meshforge pattern)
        local wait_count=0
        local max_wait=10
        while is_rnsd_running && [ $wait_count -lt $max_wait ]; do
            sleep 1
            ((wait_count++))
        done

        if ! is_rnsd_running; then
            print_success "rnsd stopped"
            log_message "Stopped rnsd daemon"
        else
            print_warning "rnsd may still be running after ${max_wait}s"
            log_warn "rnsd did not stop within ${max_wait}s"
        fi
    else
        print_info "rnsd is not running"
    fi

    # Check for nomadnet processes (centralized service check)
    if check_service_status "nomadnet"; then
        print_warning "NomadNet is running - please close it manually"
        echo -n "Press Enter when NomadNet is closed..."
        read -r
        log_message "User closed NomadNet manually"
    fi

    # Check for MeshChat processes (centralized service check)
    if check_service_status "meshchat"; then
        print_warning "MeshChat appears to be running - please close it manually"
        echo -n "Press Enter when MeshChat is closed..."
        read -r
        log_message "User closed MeshChat manually"
    fi

    # Invalidate status cache after service changes
    invalidate_status_cache
    print_success "Services stopped"
}

start_services() {
    print_section "Starting Services"

    if confirm_action "Start the rnsd daemon?" "y"; then
        print_info "Starting rnsd daemon..."
        if rnsd --daemon 2>&1 | tee -a "$UPDATE_LOG"; then
            # Poll with timeout instead of hardcoded sleep (meshforge pattern)
            local wait_count=0
            local max_wait=10
            while ! is_rnsd_running && [ $wait_count -lt $max_wait ]; do
                sleep 1
                ((wait_count++))
            done

            # Verify it's running
            if is_rnsd_running; then
                print_success "rnsd daemon started"
                log_message "Started rnsd daemon successfully"

                # Show status
                print_info "Network status:"
                rnstatus 2>&1 | head -n 15
            else
                print_error "rnsd failed to start after ${max_wait}s"
                show_error_help "service" ""
            fi
        else
            print_error "Failed to start rnsd"
            show_error_help "service" ""
        fi
    fi

    # Invalidate status cache after service changes
    invalidate_status_cache
}

show_service_status() {
    print_section "Service Status"

    echo -e "${BOLD}Reticulum Network Status:${NC}\n"

    # Check rnsd (using improved detection)
    if is_rnsd_running; then
        print_success "rnsd daemon: Running"
        if command -v rnstatus &> /dev/null; then
            echo ""
            rnstatus 2>&1 | head -n 20
        fi
    else
        print_warning "rnsd daemon: Not running"
        echo -e "  ${CYAN}Start with:${NC} rnsd --daemon"
    fi

    # meshtasticd status with HTTP API check (ported from meshforge)
    if command -v meshtasticd &>/dev/null; then
        echo ""
        echo -e "${BOLD}meshtasticd:${NC}"
        if check_service_status "meshtasticd"; then
            local mtd_ver
            mtd_ver=$(meshtasticd --version 2>&1 | head -1 || echo "unknown")
            print_success "meshtasticd: Running ($mtd_ver)"

            if check_meshtasticd_http_api; then
                print_success "HTTP API: $MESHTASTICD_HTTP_URL"
            else
                print_warning "HTTP API: Not reachable"
                local hint
                hint=$(check_meshtasticd_webserver_config)
                echo -e "  ${YELLOW}${hint}${NC}"
            fi
        else
            print_warning "meshtasticd: Installed but not running"
            echo -e "  ${CYAN}Start with:${NC} sudo systemctl start meshtasticd"
        fi
    fi

    echo ""
    echo -e "${BOLD}Installed Components:${NC}\n"

    # Check RNS
    RNS_VER=$(get_installed_version "rns")
    if [ -n "$RNS_VER" ]; then
        print_success "RNS: v$RNS_VER"
    else
        print_warning "RNS: Not installed"
    fi

    # Check LXMF
    LXMF_VER=$(get_installed_version "lxmf")
    if [ -n "$LXMF_VER" ]; then
        print_success "LXMF: v$LXMF_VER"
    else
        print_warning "LXMF: Not installed"
    fi

    # Check NomadNet
    NOMAD_VER=$(get_installed_version "nomadnet")
    if [ -n "$NOMAD_VER" ]; then
        print_success "NomadNet: v$NOMAD_VER"
    else
        print_info "NomadNet: Not installed"
    fi

    # Check MeshChat
    if check_meshchat_installed; then
        print_success "MeshChat: v$MESHCHAT_VERSION"
    else
        print_info "MeshChat: Not installed"
    fi

    # Check rnodeconf
    if command -v rnodeconf &> /dev/null; then
        RNODE_VER=$(rnodeconf --version 2>&1 | head -1 | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' || echo "installed")
        [ -z "$RNODE_VER" ] && RNODE_VER="installed"
        print_success "rnodeconf: $RNODE_VER"
    else
        print_info "rnodeconf: Not installed"
    fi
}

#########################################################
# Service Management Menu
#########################################################

services_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Services"
        print_breadcrumb

        # Show current status at top (using cached + improved detection)
        print_box_top
        print_box_line "${CYAN}${BOLD}Service Status${NC}"
        print_box_divider

        local svc_rnsd_state svc_uptime
        svc_rnsd_state=$(get_cached_rnsd_status)
        if [ "$svc_rnsd_state" = "running" ]; then
            svc_uptime=$(get_rnsd_uptime)
            if [ -n "$svc_uptime" ]; then
                print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC} (up ${svc_uptime})"
            else
                print_box_line "${GREEN}●${NC} rnsd daemon: ${GREEN}Running${NC}"
            fi
            # Boot persistence warning (meshforge pattern)
            if command -v systemctl &>/dev/null; then
                if ! systemctl --user is-enabled rnsd.service &>/dev/null 2>&1; then
                    print_box_line "  ${YELLOW}! not enabled at boot${NC}"
                fi
            fi
        else
            print_box_line "${RED}○${NC} rnsd daemon: ${YELLOW}Stopped${NC}"
        fi

        # Check for meshtasticd with HTTP API status (ported from meshforge)
        if command -v meshtasticd &>/dev/null; then
            if check_service_status "meshtasticd"; then
                print_box_line "${GREEN}●${NC} meshtasticd: ${GREEN}Running${NC}"
                # Probe HTTP API inline (fast curl check)
                if check_meshtasticd_http_api; then
                    print_box_line "  ${GREEN}●${NC} HTTP API: ${GREEN}${MESHTASTICD_HTTP_URL}${NC}"
                else
                    print_box_line "  ${YELLOW}!${NC} HTTP API: ${YELLOW}Not reachable${NC}"
                fi
            else
                print_box_line "${YELLOW}○${NC} meshtasticd: Stopped"
            fi
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Service Management:${NC}"
        echo ""
        echo -e "  ${CYAN}─── rnsd Daemon Control ───${NC}"
        echo "   1) Start rnsd daemon"
        echo "   2) Stop rnsd daemon"
        echo "   3) Restart rnsd daemon"
        echo "   4) View detailed status"
        echo ""
        if command -v meshtasticd &>/dev/null; then
            echo -e "  ${CYAN}─── meshtasticd Control ───${NC}"
            echo "  m1) Start meshtasticd"
            echo "  m2) Stop meshtasticd"
            echo "  m3) Restart meshtasticd"
            echo "  m4) Check HTTP API & config"
            echo ""
        fi
        echo -e "  ${CYAN}─── Network Tools ───${NC}"
        echo -e "   5) $(menu_item "View network statistics (rnstatus)" "$HAS_RNSTATUS")"
        echo -e "   6) $(menu_item "View path table (rnpath)" "$HAS_RNPATH")"
        echo -e "   7) $(menu_item "Probe destination (rnprobe)" "$HAS_RNPROBE")"
        echo -e "   8) $(menu_item "Transfer file (rncp)" "$HAS_RNCP")"
        echo -e "   9) $(menu_item "Remote command (rnx)" "$HAS_RNX")"
        echo ""
        echo -e "  ${CYAN}─── Identity & Boot ───${NC}"
        echo -e "  10) $(menu_item "Identity management (rnid)" "$HAS_RNID")"
        echo "  11) Enable auto-start on boot"
        echo "  12) Disable auto-start on boot"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r SVC_CHOICE

        case $SVC_CHOICE in
            1)
                start_services
                pause_for_input
                ;;
            2)
                stop_services
                pause_for_input
                ;;
            3)
                print_info "Restarting rnsd daemon..."
                stop_services
                start_services
                pause_for_input
                ;;
            4)
                show_service_status
                pause_for_input
                ;;
            5)
                print_section "Network Statistics"
                if [ "$HAS_RNSTATUS" = true ]; then
                    rnstatus -a 2>&1 | head -n 50
                else
                    print_warning "rnstatus not available - install RNS first"
                fi
                pause_for_input
                ;;
            6)
                print_section "Path Table"
                if [ "$HAS_RNPATH" = true ]; then
                    print_info "Known paths in the Reticulum network:"
                    echo ""
                    rnpath -t 2>&1
                else
                    print_warning "rnpath not available - install RNS first"
                fi
                pause_for_input
                ;;
            7)
                print_section "Probe Destination"
                if [ "$HAS_RNPROBE" = true ]; then
                    echo -n "Enter destination hash to probe: "
                    read -r PROBE_DEST
                    if [ -n "$PROBE_DEST" ]; then
                        print_info "Probing $PROBE_DEST..."
                        rnprobe "$PROBE_DEST" 2>&1
                    else
                        print_info "Cancelled"
                    fi
                else
                    print_warning "rnprobe not available - install RNS first"
                fi
                pause_for_input
                ;;
            8)
                print_section "File Transfer (rncp)"
                if [ "$HAS_RNCP" = true ]; then
                    echo -e "${BOLD}RNS File Transfer:${NC}"
                    echo ""
                    echo "  ${CYAN}Send a file:${NC}"
                    echo "    rncp /path/to/file <destination_hash>"
                    echo ""
                    echo "  ${CYAN}Receive files (listen mode):${NC}"
                    echo "    rncp -l [-s /save/path]"
                    echo ""
                    echo "  ${CYAN}Fetch a file from remote:${NC}"
                    echo "    rncp -f <filename> <destination_hash>"
                    echo ""
                    echo -e "${BOLD}Actions:${NC}"
                    echo "   s) Send a file now"
                    echo "   l) Start listening for incoming files"
                    echo "   0) Cancel"
                    echo ""
                    echo -n "Select action: "
                    read -r RNCP_ACTION
                    case $RNCP_ACTION in
                        s|S)
                            echo -n "File path to send: "
                            read -r RNCP_FILE
                            if [ -z "$RNCP_FILE" ]; then
                                print_info "Cancelled"
                            elif [ ! -f "$RNCP_FILE" ]; then
                                print_error "File not found: $RNCP_FILE"
                            else
                                echo -n "Destination hash: "
                                read -r RNCP_DEST
                                if [ -n "$RNCP_DEST" ]; then
                                    print_info "Sending $RNCP_FILE to $RNCP_DEST..."
                                    rncp "$RNCP_FILE" "$RNCP_DEST" 2>&1
                                else
                                    print_info "Cancelled"
                                fi
                            fi
                            ;;
                        l|L)
                            print_info "Listening for incoming file transfers..."
                            print_info "Press Ctrl+C to stop listening"
                            rncp -l -s "$REAL_HOME/Downloads" 2>&1 || true
                            ;;
                        *)
                            print_info "Cancelled"
                            ;;
                    esac
                else
                    print_warning "rncp not available - install RNS first"
                fi
                pause_for_input
                ;;
            9)
                print_section "Remote Command (rnx)"
                if [ "$HAS_RNX" = true ]; then
                    echo -e "${BOLD}RNS Remote Execution:${NC}"
                    echo ""
                    echo "  ${CYAN}Run a remote command:${NC}"
                    echo "    rnx <destination_hash> \"command\""
                    echo ""
                    echo "  ${CYAN}Listen for commands:${NC}"
                    echo "    rnx -l [-i identity_file]"
                    echo ""
                    echo -e "${YELLOW}Note: Remote must be running rnx in listen mode${NC}"
                    echo ""
                    echo -n "Destination hash (or 0 to cancel): "
                    read -r RNX_DEST
                    if [ -n "$RNX_DEST" ] && [ "$RNX_DEST" != "0" ]; then
                        echo -n "Command to execute: "
                        read -r RNX_CMD
                        if [ -n "$RNX_CMD" ]; then
                            print_info "Executing on $RNX_DEST: $RNX_CMD"
                            rnx "$RNX_DEST" "$RNX_CMD" 2>&1
                        else
                            print_info "Cancelled"
                        fi
                    else
                        print_info "Cancelled"
                    fi
                else
                    print_warning "rnx not available - install RNS first"
                fi
                pause_for_input
                ;;
            10)
                print_section "Identity Management (rnid)"
                if [ "$HAS_RNID" = true ]; then
                    echo -e "${BOLD}RNS Identity Management:${NC}"
                    echo ""
                    echo "   1) Show my identity hash"
                    echo "   2) Generate new identity"
                    echo "   3) View identity file info"
                    echo "   0) Cancel"
                    echo ""
                    echo -n "Select action: "
                    read -r RNID_ACTION
                    case $RNID_ACTION in
                        1)
                            print_info "Default identity hash:"
                            rnid 2>&1
                            ;;
                        2)
                            echo -n "Output path (default: ~/.reticulum/identities/new): "
                            read -r RNID_PATH
                            if [ -z "$RNID_PATH" ]; then
                                if ! mkdir -p "$REAL_HOME/.reticulum/identities" 2>/dev/null; then
                                    print_error "Cannot create identities directory"
                                    break
                                fi
                                RNID_PATH="$REAL_HOME/.reticulum/identities/new_$(date +%Y%m%d_%H%M%S)"
                            fi
                            print_info "Generating new identity..."
                            rnid -g "$RNID_PATH" 2>&1
                            if [ -f "$RNID_PATH" ]; then
                                print_success "Identity generated: $RNID_PATH"
                            fi
                            ;;
                        3)
                            echo -n "Identity file path: "
                            read -r RNID_FILE
                            if [ -n "$RNID_FILE" ] && [ -f "$RNID_FILE" ]; then
                                rnid -i "$RNID_FILE" 2>&1
                            elif [ -n "$RNID_FILE" ]; then
                                print_error "File not found: $RNID_FILE"
                            else
                                print_info "Cancelled"
                            fi
                            ;;
                        *)
                            print_info "Cancelled"
                            ;;
                    esac
                else
                    print_warning "rnid not available - install RNS first"
                fi
                pause_for_input
                ;;
            11)
                setup_autostart
                pause_for_input
                ;;
            12)
                disable_autostart
                pause_for_input
                ;;
            m1|M1)
                # meshtasticd start (ported from meshforge/reticulum_updater.sh)
                print_section "Starting meshtasticd"
                if ! command -v meshtasticd &>/dev/null; then
                    print_error "meshtasticd is not installed"
                elif check_service_status "meshtasticd"; then
                    print_info "meshtasticd is already running"
                else
                    print_info "Starting meshtasticd service..."
                    if sudo systemctl start meshtasticd 2>&1; then
                        sleep 3
                        if check_service_status "meshtasticd"; then
                            print_success "meshtasticd service started"
                            log_message "Started meshtasticd service"
                            # Check HTTP API availability after start
                            if check_meshtasticd_http_api; then
                                print_success "HTTP API available at $MESHTASTICD_HTTP_URL"
                            else
                                print_info "HTTP API not yet available (may need a few seconds)"
                            fi
                        else
                            print_error "meshtasticd failed to start"
                            echo -e "  ${CYAN}Check logs:${NC} sudo journalctl -u meshtasticd --no-pager -n 20"
                        fi
                    else
                        print_error "Failed to start meshtasticd"
                        echo -e "  ${CYAN}Check status:${NC} sudo systemctl status meshtasticd"
                    fi
                fi
                invalidate_status_cache
                pause_for_input
                ;;
            m2|M2)
                # meshtasticd stop
                print_section "Stopping meshtasticd"
                if ! command -v meshtasticd &>/dev/null; then
                    print_error "meshtasticd is not installed"
                elif ! check_service_status "meshtasticd"; then
                    print_info "meshtasticd is not running"
                else
                    print_info "Stopping meshtasticd service..."
                    if sudo systemctl stop meshtasticd 2>&1; then
                        sleep 2
                        if ! check_service_status "meshtasticd"; then
                            print_success "meshtasticd stopped"
                            log_message "Stopped meshtasticd service"
                        else
                            print_warning "meshtasticd may still be stopping..."
                        fi
                    else
                        print_error "Failed to stop meshtasticd"
                    fi
                fi
                invalidate_status_cache
                pause_for_input
                ;;
            m3|M3)
                # meshtasticd restart
                print_section "Restarting meshtasticd"
                if ! command -v meshtasticd &>/dev/null; then
                    print_error "meshtasticd is not installed"
                else
                    print_info "Restarting meshtasticd service..."
                    if sudo systemctl restart meshtasticd 2>&1; then
                        sleep 3
                        if check_service_status "meshtasticd"; then
                            print_success "meshtasticd restarted"
                            log_message "Restarted meshtasticd service"
                            if check_meshtasticd_http_api; then
                                print_success "HTTP API available at $MESHTASTICD_HTTP_URL"
                            else
                                print_info "HTTP API not yet available (may need a few seconds)"
                            fi
                        else
                            print_error "meshtasticd failed to restart"
                            echo -e "  ${CYAN}Check logs:${NC} sudo journalctl -u meshtasticd --no-pager -n 20"
                        fi
                    else
                        print_error "Failed to restart meshtasticd"
                    fi
                fi
                invalidate_status_cache
                pause_for_input
                ;;
            m4|M4)
                # meshtasticd HTTP API & config check (ported from meshforge diagnostics)
                print_section "meshtasticd HTTP API & Configuration"
                if ! command -v meshtasticd &>/dev/null; then
                    print_error "meshtasticd is not installed"
                else
                    # Version info
                    local mtd_ver
                    mtd_ver=$(meshtasticd --version 2>&1 | head -1 || echo "unknown")
                    echo -e "  Version: ${BOLD}${mtd_ver}${NC}"
                    echo ""

                    # Service status
                    echo -e "${BOLD}Service Status:${NC}"
                    if check_service_status "meshtasticd"; then
                        print_success "meshtasticd service is running"
                    else
                        print_warning "meshtasticd service is not running"
                        echo -e "  ${YELLOW}Start with: sudo systemctl start meshtasticd${NC}"
                    fi
                    echo ""

                    # Config validation
                    echo -e "${BOLD}Configuration:${NC}"
                    local config_hint
                    config_hint=$(check_meshtasticd_webserver_config)
                    local config_rc=$?
                    if [ $config_rc -eq 0 ]; then
                        print_success "$config_hint"
                    else
                        print_warning "$config_hint"
                    fi
                    echo ""

                    # HTTP API probe
                    echo -e "${BOLD}HTTP API Probe:${NC}"
                    echo "  Testing ports 443, 9443, 80, 4403..."
                    if check_meshtasticd_http_api; then
                        print_success "HTTP API reachable at $MESHTASTICD_HTTP_URL"

                        # Try to fetch node count from /json/nodes
                        local nodes_response
                        nodes_response=$(curl -sk --connect-timeout 3 --max-time 5 \
                            "${MESHTASTICD_HTTP_URL}/json/nodes" 2>/dev/null)
                        if [ -n "$nodes_response" ]; then
                            # Count node entries (rough heuristic: count "num" keys)
                            local node_count
                            node_count=$(echo "$nodes_response" | grep -o '"num"' | wc -l)
                            if [ "$node_count" -gt 0 ]; then
                                print_success "$node_count node(s) visible via HTTP API"
                            fi
                        fi
                    else
                        print_error "HTTP API not reachable on any port"
                        echo ""
                        echo -e "  ${BOLD}Troubleshooting:${NC}"
                        echo "  1. Verify meshtasticd is running: sudo systemctl status meshtasticd"
                        echo "  2. Check config has Webserver section: /etc/meshtasticd/config.yaml"
                        echo "  3. Example config entry:"
                        echo -e "     ${CYAN}Webserver:${NC}"
                        echo -e "     ${CYAN}  Port: 443${NC}"
                        echo -e "     ${CYAN}  RootPath: /usr/share/meshtasticd/web${NC}"
                        echo "  4. Check logs: sudo journalctl -u meshtasticd --no-pager -n 30"
                    fi
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

setup_autostart() {
    print_section "Setup Auto-Start"

    if [ ! -d "$REAL_HOME/.config/systemd/user" ]; then
        mkdir -p "$REAL_HOME/.config/systemd/user"
    fi

    local service_file="$REAL_HOME/.config/systemd/user/rnsd.service"

    cat > "$service_file" << 'EOF'
[Unit]
Description=Reticulum Network Stack Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rnsd
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

    print_info "Enabling rnsd service..."
    systemctl --user daemon-reload
    systemctl --user enable rnsd.service

    print_success "Auto-start enabled for rnsd"
    print_info "Service will start automatically on login"
    log_message "Enabled rnsd auto-start"
}

disable_autostart() {
    print_section "Disable Auto-Start"

    if systemctl --user is-enabled rnsd.service &>/dev/null; then
        systemctl --user disable rnsd.service
        print_success "Auto-start disabled for rnsd"
        log_message "Disabled rnsd auto-start"
    else
        print_info "Auto-start was not enabled"
    fi
}

#########################################################
# Backup and Restore Menu
#########################################################

backup_restore_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Backup/Restore"
        print_breadcrumb

        # Show backup status
        local backup_count
        backup_count=$(find "$REAL_HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" 2>/dev/null | wc -l)

        print_box_top
        print_box_line "${CYAN}${BOLD}Backup Status${NC}"
        print_box_divider
        print_box_line "Available backups: $backup_count"

        if [ -d "$REAL_HOME/.reticulum" ]; then
            local config_size
            config_size=$(du -sh "$REAL_HOME/.reticulum" 2>/dev/null | cut -f1)
            print_box_line "Config size: $config_size"
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Backup & Restore:${NC}"
        echo ""
        echo "   1) Create backup"
        echo "   2) Restore from backup"
        echo "   3) List all backups"
        echo "   4) Delete old backups"
        echo "   5) Export configuration (portable)"
        echo "   6) Import configuration"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r BACKUP_CHOICE

        case $BACKUP_CHOICE in
            1)
                create_backup
                pause_for_input
                ;;
            2)
                restore_backup
                pause_for_input
                ;;
            3)
                list_all_backups
                pause_for_input
                ;;
            4)
                delete_old_backups
                pause_for_input
                ;;
            5)
                export_configuration
                pause_for_input
                ;;
            6)
                import_configuration
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

list_all_backups() {
    print_section "All Backups"

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$REAL_HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return
    fi

    echo -e "${BOLD}Found ${#backups[@]} backup(s):${NC}\n"

    for backup in "${backups[@]}"; do
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date
        backup_date=$(echo "$backup_name" | sed -n 's/.*\([0-9]\{8\}_[0-9]\{6\}\).*/\1/p')
        local backup_size
        backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1)

        # Format date nicely (capture groups require sed, not parameter expansion)
        local formatted_date
        # shellcheck disable=SC2001
        formatted_date=$(echo "$backup_date" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

        echo -e "  ${GREEN}●${NC} $formatted_date (Size: $backup_size)"
    done
}

delete_old_backups() {
    print_section "Delete Old Backups"

    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$REAL_HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found to delete"
        return
    fi

    if [ ${#backups[@]} -le 3 ]; then
        print_info "Only ${#backups[@]} backup(s) exist. Keeping all."
        return
    fi

    echo -e "${YELLOW}This will keep the 3 most recent backups and delete older ones.${NC}"
    echo ""

    local to_delete=$((${#backups[@]} - 3))
    echo "Backups to delete: $to_delete"
    echo ""

    if confirm_action "Delete $to_delete old backup(s)?"; then
        local count=0
        for ((i=0; i<to_delete; i++)); do
            rm -rf "${backups[$i]}"
            ((count++))
        done
        print_success "Deleted $count old backup(s)"
        log_message "Deleted $count old backups"
    else
        print_info "Cancelled"
    fi
}

export_configuration() {
    print_section "Export Configuration"
    EXPORT_FILE="$REAL_HOME/reticulum_config_export_$(date +%Y%m%d_%H%M%S).tar.gz"

    echo -e "${YELLOW}This will create a portable backup of your configuration.${NC}"
    echo ""

    if [ -d "$REAL_HOME/.reticulum" ] || [ -d "$REAL_HOME/.nomadnetwork" ] || [ -d "$REAL_HOME/.lxmf" ]; then
        print_info "Creating export archive..."

        # Create temporary directory for export
        TEMP_EXPORT=$(mktemp -d)

        [ -d "$REAL_HOME/.reticulum" ] && cp -r "$REAL_HOME/.reticulum" "$TEMP_EXPORT/"
        [ -d "$REAL_HOME/.nomadnetwork" ] && cp -r "$REAL_HOME/.nomadnetwork" "$TEMP_EXPORT/"
        [ -d "$REAL_HOME/.lxmf" ] && cp -r "$REAL_HOME/.lxmf" "$TEMP_EXPORT/"

        if tar -czf "$EXPORT_FILE" -C "$TEMP_EXPORT" . 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Configuration exported to:"
            echo -e "  ${GREEN}$EXPORT_FILE${NC}"
            log_message "Exported configuration to: $EXPORT_FILE"
        else
            print_error "Failed to create export archive"
        fi

        rm -rf "$TEMP_EXPORT"
    else
        print_warning "No configuration files found to export"
    fi
}

import_configuration() {
    print_section "Import Configuration"
    echo "Enter the path to the export archive (.tar.gz):"
    echo -n "Archive path: "
    read -r IMPORT_FILE

    if [ ! -f "$IMPORT_FILE" ]; then
        print_error "File not found: $IMPORT_FILE"
    elif [[ ! "$IMPORT_FILE" =~ \.tar\.gz$ ]]; then
        print_error "Invalid file format. Expected .tar.gz archive"
    else
        # RNS004: Archive validation before extraction
        print_info "Validating archive structure..."

        # Check for path traversal attempts (../) and absolute paths
        if tar -tzf "$IMPORT_FILE" 2>/dev/null | grep -qE '(^/|\.\./)'; then
            print_error "Security: Archive contains invalid paths (absolute or traversal)"
            log_message "SECURITY: Rejected archive with invalid paths: $IMPORT_FILE"
            return 1
        fi

        # Verify archive contains expected Reticulum config files
        local archive_contents
        archive_contents=$(tar -tzf "$IMPORT_FILE" 2>/dev/null)

        if ! echo "$archive_contents" | grep -qE '^\.(reticulum|nomadnetwork|lxmf)/'; then
            print_warning "Archive does not appear to contain Reticulum configuration"
            echo "Expected directories: .reticulum/, .nomadnetwork/, .lxmf/"
            if ! confirm_action "Continue anyway?"; then
                print_info "Import cancelled"
                return 0
            fi
        fi

        print_success "Archive validation passed"
        echo -e "${RED}${BOLD}WARNING:${NC} This will overwrite your current configuration!"

        if confirm_action "Continue?"; then
            print_info "Creating backup of current configuration..."
            create_backup

            print_info "Importing configuration..."
            if tar -xzf "$IMPORT_FILE" -C "$REAL_HOME" 2>&1 | tee -a "$UPDATE_LOG"; then
                print_success "Configuration imported successfully"
                log_message "Imported configuration from: $IMPORT_FILE"
            else
                print_error "Failed to import configuration"
            fi
        else
            print_info "Import cancelled"
        fi
    fi
}

#########################################################
# Backup and Restore
#########################################################

create_backup() {
    print_section "Creating Backup"

    echo -e "${YELLOW}Create backup of Reticulum configuration?${NC}"
    echo "  • ~/.reticulum/"
    echo "  • ~/.nomadnetwork/"
    echo "  • ~/.lxmf/"
    echo ""
    if ! confirm_action "Create backup?" "y"; then
        print_warning "Skipping backup"
        log_message "User skipped backup"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local backed_up=false

    # Backup RNS config
    if [ -d "$REAL_HOME/.reticulum" ]; then
        if cp -r "$REAL_HOME/.reticulum" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up Reticulum config"
            log_message "Backed up ~/.reticulum"
            backed_up=true
        else
            print_error "Failed to backup Reticulum config"
        fi
    fi

    # Backup NomadNet config
    if [ -d "$REAL_HOME/.nomadnetwork" ]; then
        if cp -r "$REAL_HOME/.nomadnetwork" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up NomadNet config"
            log_message "Backed up ~/.nomadnetwork"
            backed_up=true
        else
            print_error "Failed to backup NomadNet config"
        fi
    fi

    # Backup LXMF config
    if [ -d "$REAL_HOME/.lxmf" ]; then
        if cp -r "$REAL_HOME/.lxmf" "$BACKUP_DIR/" 2>/dev/null; then
            print_success "Backed up LXMF config"
            log_message "Backed up ~/.lxmf"
            backed_up=true
        else
            print_error "Failed to backup LXMF config"
        fi
    fi

    if [ "$backed_up" = true ]; then
        print_success "Backup saved to: $BACKUP_DIR"
        log_message "Backup created at: $BACKUP_DIR"
        return 0
    else
        print_warning "No configuration files found to backup"
        return 1
    fi
}

restore_backup() {
    print_section "Restore Backup"

    echo -e "${YELLOW}Available backups in your home directory:${NC}\n"

    # List available backups
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$REAL_HOME" -maxdepth 1 -type d -name ".reticulum_backup_*" -print0 2>/dev/null | sort -z)

    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return 1
    fi

    local i=1
    for backup in "${backups[@]}"; do
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date
        backup_date=$(echo "$backup_name" | sed -n 's/.*\([0-9]\{8\}_[0-9]\{6\}\).*/\1/p')
        echo "  $i) $backup_date"
        ((i++))
    done

    echo ""
    echo -n "Select backup to restore (0 to cancel): "
    read -r BACKUP_CHOICE

    if [ "$BACKUP_CHOICE" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    if [ "$BACKUP_CHOICE" -ge 1 ] && [ "$BACKUP_CHOICE" -le ${#backups[@]} ] 2>/dev/null; then
        local selected_backup="${backups[$((BACKUP_CHOICE-1))]}"

        echo -e "${RED}${BOLD}WARNING:${NC} This will overwrite your current configuration!"
        if confirm_action "Continue?"; then
            print_info "Restoring from: $selected_backup"

            # Restore configs
            [ -d "$selected_backup/.reticulum" ] && cp -r "$selected_backup/.reticulum" "$REAL_HOME/"
            [ -d "$selected_backup/.nomadnetwork" ] && cp -r "$selected_backup/.nomadnetwork" "$REAL_HOME/"
            [ -d "$selected_backup/.lxmf" ] && cp -r "$selected_backup/.lxmf" "$REAL_HOME/"

            print_success "Backup restored successfully"
            log_message "Restored backup from: $selected_backup"
        fi
    else
        print_error "Invalid selection"
    fi
}

#########################################################
# Diagnostics
#########################################################

run_diagnostics() {
    print_section "System Diagnostics"

    local issues=0
    local warnings=0

    echo -e "${BOLD}Running 6-step diagnostic...${NC}\n"

    # ── Step 1: Environment & Prerequisites ──
    echo -e "${BLUE}▶ Step 1/6: Environment & Prerequisites${NC}"

    echo "  Platform: $OS_TYPE ($ARCHITECTURE)"
    [ "$IS_RASPBERRY_PI" = true ] && echo "  Raspberry Pi: $PI_MODEL"
    [ "$IS_WSL" = true ] && echo "  Running in WSL"
    [ "$IS_SSH" = true ] && echo "  Connected via SSH"

    if [ "$HAS_PYTHON3" = true ]; then
        local pyver
        pyver=$(python3 --version 2>&1)
        print_success "$pyver"
    else
        print_error "Python 3 not found"
        echo -e "  ${YELLOW}Fix: sudo apt install python3 python3-pip${NC}"
        ((issues++))
    fi

    if [ "$HAS_PIP" = true ]; then
        print_success "pip available"
    else
        print_error "pip not found"
        echo -e "  ${YELLOW}Fix: sudo apt install python3-pip${NC}"
        ((issues++))
    fi

    if [ "$PEP668_DETECTED" = true ]; then
        echo -e "  ${CYAN}[i] PEP 668: Python externally managed (Debian 12+)${NC}"
    fi
    echo ""

    # ── Step 2: RNS Tool Availability ──
    echo -e "${BLUE}▶ Step 2/6: RNS Tool Availability${NC}"

    local tool_list=(
        "rnsd:$HAS_RNSD:daemon"
        "rnstatus:$HAS_RNSTATUS:network status"
        "rnpath:$HAS_RNPATH:path table"
        "rnprobe:$HAS_RNPROBE:connectivity probe"
        "rncp:$HAS_RNCP:file transfer"
        "rnx:$HAS_RNX:remote execution"
        "rnid:$HAS_RNID:identity management"
        "rnodeconf:$HAS_RNODECONF:RNODE configuration"
    )

    local tool_present=0
    local tool_missing=0
    for entry in "${tool_list[@]}"; do
        local tname tstate tdesc
        tname="${entry%%:*}"
        local rest="${entry#*:}"
        tstate="${rest%%:*}"
        tdesc="${rest#*:}"
        if [ "$tstate" = "true" ]; then
            print_success "$tname ($tdesc)"
            ((tool_present++))
        else
            echo -e "  ${YELLOW}○${NC} $tname ($tdesc) - not installed"
            ((tool_missing++))
        fi
    done

    if [ "$tool_missing" -gt 0 ]; then
        echo ""
        echo -e "  ${CYAN}[i] Install missing tools: pip3 install rns${NC}"
        ((warnings++))
    fi
    echo ""

    # ── Step 3: Configuration Validation ──
    echo -e "${BLUE}▶ Step 3/6: Configuration Validation${NC}"

    local config_file="$REAL_HOME/.reticulum/config"
    if [ -f "$config_file" ]; then
        print_success "Config file exists: ~/.reticulum/config"

        # Check config file size (empty = problem)
        local config_size
        config_size=$(wc -c < "$config_file" 2>/dev/null || echo 0)
        if [ "$config_size" -lt 10 ]; then
            print_error "Config file appears empty ($config_size bytes)"
            echo -e "  ${YELLOW}Fix: Apply a config template from Advanced > Apply Configuration Template${NC}"
            ((issues++))
        fi

        # Check for common config issues
        if grep -q "interface_enabled = false" "$config_file" 2>/dev/null; then
            print_warning "Some interfaces are disabled in config"
            ((warnings++))
        fi

        # Check identity directory
        if [ -d "$REAL_HOME/.reticulum/storage/identities" ]; then
            local id_count
            id_count=$(find "$REAL_HOME/.reticulum/storage/identities" -type f 2>/dev/null | wc -l)
            echo "  Known identities: $id_count"
        fi
    else
        print_warning "No configuration found"
        echo -e "  ${YELLOW}Fix: Run first-time setup or start rnsd to create default config${NC}"
        ((warnings++))
    fi
    echo ""

    # ── Step 4: Service Health ──
    echo -e "${BLUE}▶ Step 4/6: Service Health${NC}"

    if check_service_status "rnsd"; then
        print_success "rnsd daemon is running"

        # Check uptime via /proc if possible
        local rnsd_pid
        rnsd_pid=$(pgrep -x "rnsd" 2>/dev/null | head -1)
        if [ -n "$rnsd_pid" ] && [ -d "/proc/$rnsd_pid" ]; then
            local start_time
            start_time=$(stat -c %Y "/proc/$rnsd_pid" 2>/dev/null)
            if [ -n "$start_time" ]; then
                local now_time uptime_secs
                now_time=$(date +%s)
                uptime_secs=$((now_time - start_time))
                if [ "$uptime_secs" -lt 60 ]; then
                    echo "  Uptime: ${uptime_secs}s"
                elif [ "$uptime_secs" -lt 3600 ]; then
                    echo "  Uptime: $((uptime_secs / 60))m"
                else
                    echo "  Uptime: $((uptime_secs / 3600))h $((uptime_secs % 3600 / 60))m"
                fi
            fi
        fi
    else
        print_warning "rnsd daemon is not running"
        echo -e "  ${YELLOW}Fix: Start from Services menu or run: rnsd --daemon${NC}"
        ((warnings++))
    fi

    # Check autostart
    if command -v systemctl &>/dev/null; then
        if systemctl --user is-enabled rnsd.service &>/dev/null 2>&1; then
            print_success "Auto-start enabled at boot"
        else
            echo -e "  ${CYAN}[i] Auto-start not enabled (enable from Services menu)${NC}"
        fi
    fi

    # meshtasticd health check (ported from meshforge dashboard_mixin.py)
    if command -v meshtasticd &>/dev/null; then
        echo ""
        echo -e "  ${CYAN}meshtasticd Integration:${NC}"

        if check_service_status "meshtasticd"; then
            print_success "meshtasticd service is running"

            # Probe HTTP API (meshforge meshtastic_http.py pattern)
            if check_meshtasticd_http_api; then
                print_success "meshtasticd HTTP API reachable at $MESHTASTICD_HTTP_URL"
            else
                print_warning "meshtasticd HTTP API not reachable (tried ports 443, 9443, 80, 4403)"
                local config_hint
                config_hint=$(check_meshtasticd_webserver_config)
                echo -e "  ${YELLOW}${config_hint}${NC}"
                ((warnings++))
            fi
        else
            print_warning "meshtasticd installed but not running"
            echo -e "  ${YELLOW}Fix: sudo systemctl start meshtasticd${NC}"
            ((warnings++))
        fi
    fi
    echo ""

    # ── Step 5: Network & Interfaces ──
    echo -e "${BLUE}▶ Step 5/6: Network & Interfaces${NC}"

    if command -v ip &> /dev/null; then
        local net_ifaces
        net_ifaces=$(ip -br addr 2>/dev/null | grep -v "^lo" | grep -c "UP" || echo 0)
        if [ "$net_ifaces" -gt 0 ]; then
            print_success "$net_ifaces network interface(s) up"
            ip -br addr 2>/dev/null | grep -v "^lo" | while read -r line; do
                echo "  $line"
            done
        else
            print_warning "No active network interfaces found"
            ((warnings++))
        fi
    fi

    # USB serial devices (RNODE)
    local usb_devices
    usb_devices=$(find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | wc -l)
    if [ "$usb_devices" -gt 0 ]; then
        print_success "$usb_devices USB serial device(s) detected"
        find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | while read -r dev; do
            echo "  $dev"
        done

        # Check dialout group membership
        if ! groups 2>/dev/null | grep -q "dialout"; then
            print_warning "User not in dialout group"
            echo -e "  ${YELLOW}Fix: sudo usermod -aG dialout \$USER && logout${NC}"
            ((warnings++))
        fi
    else
        echo -e "  ${CYAN}[i] No USB serial devices (RNODE) detected${NC}"
    fi

    # RNS interface status (if rnstatus available and rnsd running)
    if [ "$HAS_RNSTATUS" = true ] && check_service_status "rnsd"; then
        echo ""
        echo -e "  ${CYAN}Reticulum Interface Status:${NC}"
        rnstatus 2>&1 | head -n 25 | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""

    # ── Step 6: Summary & Recommendations ──
    echo -e "${BLUE}▶ Step 6/6: Summary & Recommendations${NC}"
    echo ""

    if [ "$issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        print_success "All checks passed - system looks healthy"
    else
        [ "$issues" -gt 0 ] && print_error "$issues issue(s) found requiring attention"
        [ "$warnings" -gt 0 ] && print_warning "$warnings warning(s) found"
        echo ""
        echo -e "${BOLD}Recommended actions:${NC}"

        if [ "$HAS_RNSD" = false ]; then
            echo "  1. Install Reticulum: select option 1 from main menu"
        elif ! check_service_status "rnsd"; then
            echo "  1. Start rnsd: select option 7 > 1 from main menu"
        fi

        if [ ! -f "$config_file" ]; then
            echo "  2. Create configuration: use first-run wizard or Advanced > Templates"
        fi

        if [ "$usb_devices" -gt 0 ] && ! groups 2>/dev/null | grep -q "dialout"; then
            echo "  3. Add user to dialout group for RNODE access"
        fi
    fi

    echo ""
    log_message "Diagnostics complete: $issues issues, $warnings warnings"
}

#########################################################
# Configuration Templates
#########################################################

# Apply a config template with mandatory backup (MeshForge safety principle)
# NEVER overwrites without backing up first
apply_config_template() {
    print_section "Configuration Templates"

    local template_dir="$SCRIPT_DIR/config_templates"
    if [ ! -d "$template_dir" ]; then
        print_error "Template directory not found: $template_dir"
        return 1
    fi

    echo -e "${BOLD}Available configuration templates:${NC}\n"
    echo "   1) Minimal       - Local network only (AutoInterface)"
    echo "   2) LoRa RNODE    - RNODE LoRa radio + local network"
    echo "   3) TCP Client    - Connect to remote transport nodes"
    echo "   4) Transport Node - Full routing node (advanced)"
    echo ""
    echo "   v) View template before applying"
    echo "   0) Cancel"
    echo ""

    echo -e "${YELLOW}WARNING: Applying a template replaces your current config.${NC}"
    echo -e "${GREEN}Your existing config will be backed up first.${NC}"
    echo ""
    echo -n "Select template: "
    read -r TMPL_CHOICE

    local template_file=""
    local template_name=""
    case $TMPL_CHOICE in
        1) template_file="$template_dir/minimal.conf"; template_name="Minimal" ;;
        2) template_file="$template_dir/lora_rnode.conf"; template_name="LoRa RNODE" ;;
        3) template_file="$template_dir/tcp_client.conf"; template_name="TCP Client" ;;
        4) template_file="$template_dir/transport_node.conf"; template_name="Transport Node" ;;
        v|V)
            # View a template without applying
            echo ""
            echo -n "Which template to view (1-4)? "
            read -r VIEW_CHOICE
            case $VIEW_CHOICE in
                1) template_file="$template_dir/minimal.conf" ;;
                2) template_file="$template_dir/lora_rnode.conf" ;;
                3) template_file="$template_dir/tcp_client.conf" ;;
                4) template_file="$template_dir/transport_node.conf" ;;
                *) print_error "Invalid choice"; return 1 ;;
            esac
            if [ -f "$template_file" ]; then
                echo ""
                head -n 80 "$template_file"
                local total_lines
                total_lines=$(wc -l < "$template_file")
                if [ "$total_lines" -gt 80 ]; then
                    echo ""
                    print_info "Showing first 80 of $total_lines lines"
                fi
            fi
            return 0
            ;;
        0|"") return 0 ;;
        *) print_error "Invalid option"; return 1 ;;
    esac

    if [ ! -f "$template_file" ]; then
        print_error "Template file not found: $template_file"
        return 1
    fi

    local config_dir="$REAL_HOME/.reticulum"
    local config_file="$config_dir/config"

    # MANDATORY BACKUP before any config change (MeshForge safety principle)
    if [ -f "$config_file" ]; then
        local backup_name
        backup_name="config.backup.$(date +%Y%m%d_%H%M%S)"
        local backup_path="$config_dir/$backup_name"

        print_info "Backing up current config to: ~/.reticulum/$backup_name"
        if ! cp "$config_file" "$backup_path"; then
            print_error "Failed to create backup - aborting (your config is unchanged)"
            return 1
        fi
        print_success "Backup created: $backup_path"
        log_message "Config backup created: $backup_path"
    fi

    # Confirm before applying
    echo ""
    if ! confirm_action "Apply '$template_name' template to ~/.reticulum/config?"; then
        print_info "Cancelled - no changes made"
        return 0
    fi

    # Create .reticulum directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi

    # Apply the template
    if cp "$template_file" "$config_file"; then
        print_success "Template '$template_name' applied to ~/.reticulum/config"
        log_message "Applied config template: $template_name ($template_file)"
        echo ""
        print_info "Review and edit the config before starting rnsd:"
        echo -e "  ${CYAN}nano ~/.reticulum/config${NC}"
        echo ""
        if [ -n "${backup_name:-}" ]; then
            print_info "To restore your previous config:"
            echo -e "  ${CYAN}cp ~/.reticulum/$backup_name ~/.reticulum/config${NC}"
        fi
        # Invalidate cache since config changed
        invalidate_status_cache
    else
        print_error "Failed to apply template"
        return 1
    fi
}

#########################################################
# Configuration Editor
#########################################################

# Edit a config file with the user's preferred editor
# Creates backup before editing (MeshForge safety principle)
edit_config_file() {
    print_section "Edit Configuration"

    local editor="${EDITOR:-${VISUAL:-nano}}"

    # Verify editor is available
    if ! command -v "$editor" &>/dev/null; then
        editor="nano"
        if ! command -v "$editor" &>/dev/null; then
            editor="vi"
        fi
    fi

    echo -e "${BOLD}Select file to edit (using $editor):${NC}\n"

    local options=()
    local paths=()
    local idx=1

    if [ -f "$REAL_HOME/.reticulum/config" ]; then
        echo "   $idx) Reticulum config (~/.reticulum/config)"
        options+=("$idx")
        paths+=("$REAL_HOME/.reticulum/config")
        ((idx++))
    fi

    if [ -f "$REAL_HOME/.nomadnetwork/config" ]; then
        echo "   $idx) NomadNet config (~/.nomadnetwork/config)"
        options+=("$idx")
        paths+=("$REAL_HOME/.nomadnetwork/config")
        ((idx++))
    fi

    if [ -f "$REAL_HOME/.lxmf/config" ]; then
        echo "   $idx) LXMF config (~/.lxmf/config)"
        options+=("$idx")
        paths+=("$REAL_HOME/.lxmf/config")
        ((idx++))
    fi

    if [ ${#options[@]} -eq 0 ]; then
        print_warning "No configuration files found"
        print_info "Run 'rnsd --daemon' to create initial Reticulum config"
        pause_for_input
        return
    fi

    echo ""
    echo "   0) Cancel"
    echo ""
    echo -n "Select file: "
    read -r EDIT_CHOICE

    if [ "$EDIT_CHOICE" = "0" ] || [ -z "$EDIT_CHOICE" ]; then
        return
    fi

    # Find the matching path
    local target_path=""
    for i in "${!options[@]}"; do
        if [ "${options[$i]}" = "$EDIT_CHOICE" ]; then
            target_path="${paths[$i]}"
            break
        fi
    done

    if [ -z "$target_path" ]; then
        print_error "Invalid choice"
        pause_for_input
        return
    fi

    # MANDATORY BACKUP before editing (MeshForge safety principle)
    local config_dir
    config_dir=$(dirname "$target_path")
    local backup_name
    backup_name="$(basename "$target_path").backup.$(date +%Y%m%d_%H%M%S)"
    local backup_path="$config_dir/$backup_name"

    if cp "$target_path" "$backup_path"; then
        print_info "Backup: $backup_path"
        log_message "Config backup before edit: $backup_path"
    else
        print_warning "Could not create backup"
    fi

    # Launch editor
    "$editor" "$target_path"

    print_success "Editor closed"
    log_message "Edited config file: $target_path"
    invalidate_status_cache
    pause_for_input
}

#########################################################
# Advanced Options
#########################################################

view_config_files() {
    print_section "Configuration Files"

    echo -e "${BOLD}Available configuration files:${NC}\n"

    local configs_found=false

    if [ -f "$REAL_HOME/.reticulum/config" ]; then
        echo "   1) Reticulum config (~/.reticulum/config)"
        configs_found=true
    fi

    if [ -f "$REAL_HOME/.nomadnetwork/config" ]; then
        echo "   2) NomadNet config (~/.nomadnetwork/config)"
        configs_found=true
    fi

    if [ -f "$REAL_HOME/.lxmf/config" ]; then
        echo "   3) LXMF config (~/.lxmf/config)"
        configs_found=true
    fi

    if [ "$configs_found" = false ]; then
        print_warning "No configuration files found"
        print_info "Run rnsd --daemon to create initial Reticulum config"
        return
    fi

    echo ""
    echo "   0) Cancel"
    echo ""
    echo -n "Select file to view: "
    read -r CONFIG_CHOICE

    case $CONFIG_CHOICE in
        1)
            if [ -f "$REAL_HOME/.reticulum/config" ]; then
                print_section "Reticulum Configuration"
                echo -e "${CYAN}File: ~/.reticulum/config${NC}\n"
                head -n 100 "$REAL_HOME/.reticulum/config"
                if [ "$(wc -l < "$REAL_HOME/.reticulum/config")" -gt 100 ]; then
                    echo ""
                    print_info "Showing first 100 lines. Use 'cat ~/.reticulum/config' for full file."
                fi
            fi
            ;;
        2)
            if [ -f "$REAL_HOME/.nomadnetwork/config" ]; then
                print_section "NomadNet Configuration"
                echo -e "${CYAN}File: ~/.nomadnetwork/config${NC}\n"
                head -n 100 "$REAL_HOME/.nomadnetwork/config"
            fi
            ;;
        3)
            if [ -f "$REAL_HOME/.lxmf/config" ]; then
                print_section "LXMF Configuration"
                echo -e "${CYAN}File: ~/.lxmf/config${NC}\n"
                head -n 100 "$REAL_HOME/.lxmf/config"
            fi
            ;;
        0|"")
            return
            ;;
    esac
}

view_logs_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Advanced > Logs"
        print_breadcrumb

        echo -e "${BOLD}Log Viewer:${NC}\n"
        echo "   1) View recent management tool log"
        echo "   2) View rnsd daemon logs (systemd)"
        echo "   3) Search logs for keyword"
        echo "   4) List all management logs"
        echo ""
        echo "   0) Back"
        echo ""
        echo -n "Select option: "
        read -r LOG_CHOICE

        case $LOG_CHOICE in
            1)
                print_section "Recent Log Entries"
                if [ -f "$UPDATE_LOG" ]; then
                    echo -e "${CYAN}File: $UPDATE_LOG${NC}\n"
                    tail -n 50 "$UPDATE_LOG"
                else
                    # Find most recent log
                    local latest_log
                    latest_log=$(find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | sort -r | head -1)
                    if [ -n "$latest_log" ]; then
                        echo -e "${CYAN}File: $latest_log${NC}\n"
                        tail -n 50 "$latest_log"
                    else
                        print_warning "No log files found"
                    fi
                fi
                pause_for_input
                ;;
            2)
                print_section "Daemon Logs"
                if command -v journalctl &>/dev/null; then
                    print_info "Showing recent rnsd-related log entries..."
                    echo ""
                    journalctl --user -u rnsd --no-pager -n 30 2>/dev/null || \
                        journalctl -t rnsd --no-pager -n 30 2>/dev/null || \
                        print_warning "No systemd logs found for rnsd"
                else
                    print_warning "journalctl not available"
                    print_info "Try: ps aux | grep rnsd"
                fi
                pause_for_input
                ;;
            3)
                print_section "Search Logs"
                echo -n "Enter search term: "
                read -r SEARCH_TERM
                if [ -n "$SEARCH_TERM" ]; then
                    print_info "Searching for '$SEARCH_TERM' in log files..."
                    echo ""
                    grep -rF --color=always "$SEARCH_TERM" "$REAL_HOME"/rns_management_*.log 2>/dev/null || \
                        print_warning "No matches found"
                fi
                pause_for_input
                ;;
            4)
                print_section "All Management Logs"
                local log_count
                log_count=$(find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | wc -l)

                if [ "$log_count" -gt 0 ]; then
                    echo -e "${BOLD}Found $log_count log file(s):${NC}\n"
                    find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f -printf "  %f (%s bytes, %TY-%Tm-%Td)\n" 2>/dev/null | sort -r
                    echo ""
                    print_info "Logs are in: $REAL_HOME/"
                else
                    print_warning "No log files found"
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

#########################################################
# Emergency/Quick Mode - field operations
# Minimal interface for rapid deployment and status checks
#########################################################

emergency_quick_mode() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Quick Mode"
        print_breadcrumb

        # Compact status box
        print_box_top
        print_box_line "${CYAN}${BOLD}Quick Mode${NC} - Field Operations"
        print_box_divider

        if check_service_status "rnsd"; then
            print_box_line "${GREEN}●${NC} rnsd: ${GREEN}Running${NC}"
        else
            print_box_line "${RED}○${NC} rnsd: ${YELLOW}Stopped${NC}"
        fi

        if [ "$HAS_RNSTATUS" = true ] && check_service_status "rnsd"; then
            local iface_count
            iface_count=$(rnstatus 2>/dev/null | grep -c "interface" || echo "?")
            print_box_line "  Interfaces: $iface_count"
        fi

        print_box_bottom
        echo ""

        echo -e "${BOLD}Quick Actions:${NC}"
        echo ""
        echo "   1) Start rnsd daemon"
        echo "   2) Stop rnsd daemon"
        echo "   3) Network status (rnstatus)"
        echo "   4) Path table (rnpath -t)"
        echo "   5) Probe destination"
        echo "   6) Send file (rncp)"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Action: "
        read -r QM_CHOICE

        case $QM_CHOICE in
            1)
                if check_service_status "rnsd"; then
                    print_info "rnsd is already running"
                else
                    print_info "Starting rnsd..."
                    start_services
                fi
                pause_for_input
                ;;
            2)
                stop_services
                pause_for_input
                ;;
            3)
                if [ "$HAS_RNSTATUS" = true ]; then
                    rnstatus 2>&1
                else
                    print_warning "rnstatus not available"
                fi
                pause_for_input
                ;;
            4)
                if [ "$HAS_RNPATH" = true ]; then
                    rnpath -t 2>&1
                else
                    print_warning "rnpath not available"
                fi
                pause_for_input
                ;;
            5)
                if [ "$HAS_RNPROBE" = true ]; then
                    echo -n "Destination hash: "
                    read -r QM_DEST
                    if [ -n "$QM_DEST" ]; then
                        rnprobe "$QM_DEST" 2>&1
                    fi
                else
                    print_warning "rnprobe not available"
                fi
                pause_for_input
                ;;
            6)
                if [ "$HAS_RNCP" = true ]; then
                    echo -n "File to send: "
                    read -r QM_FILE
                    if [ -n "$QM_FILE" ] && [ -f "$QM_FILE" ]; then
                        echo -n "Destination hash: "
                        read -r QM_DEST
                        if [ -n "$QM_DEST" ]; then
                            rncp "$QM_FILE" "$QM_DEST" 2>&1
                        fi
                    elif [ -n "$QM_FILE" ]; then
                        print_error "File not found: $QM_FILE"
                    fi
                else
                    print_warning "rncp not available"
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

advanced_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Advanced Options"
        print_breadcrumb

        echo -e "${BOLD}Advanced Options:${NC}\n"
        echo -e "  ${CYAN}─── Configuration ───${NC}"
        echo "   1) View Configuration Files"
        echo "   2) Edit Configuration File"
        echo "   3) Apply Configuration Template"
        echo ""
        echo -e "  ${CYAN}─── Maintenance ───${NC}"
        echo "   4) Update System Packages"
        echo "   5) Reinstall All Components"
        echo "   6) Clean Cache and Temporary Files"
        echo "   7) View/Search Logs"
        echo "   8) Reset to Factory Defaults"
        echo ""
        echo "   0) Back to Main Menu"
        echo ""
        echo -n "Select an option: "
        read -r ADV_CHOICE

        case $ADV_CHOICE in
            1)
                view_config_files
                pause_for_input
                ;;
            2)
                edit_config_file
                ;;
            3)
                apply_config_template
                pause_for_input
                ;;
            4)
                update_system_packages
                pause_for_input
                ;;
            5)
                print_warning "This will reinstall all Reticulum components"
                if confirm_action "Continue?"; then
                    install_reticulum_ecosystem
                fi
                pause_for_input
                ;;
            6)
                print_section "Cleaning Cache"
                print_info "Cleaning pip cache..."
                "$PIP_CMD" cache purge 2>&1 | tee -a "$UPDATE_LOG"

                if command -v npm &>/dev/null; then
                    print_info "Cleaning npm cache..."
                    npm cache clean --force 2>&1 | tee -a "$UPDATE_LOG"
                fi

                print_success "Cache cleaned"
                pause_for_input
                ;;
            7)
                view_logs_menu
                ;;
            8)
                print_section "Reset to Factory Defaults"
                echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}${BOLD}║                      WARNING!                          ║${NC}"
                echo -e "${RED}${BOLD}║   This will DELETE all Reticulum configuration!        ║${NC}"
                echo -e "${RED}${BOLD}║   Your identities and messages will be LOST forever!   ║${NC}"
                echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo "This will remove:"
                echo "  • ~/.reticulum/     (identities, keys, config)"
                echo "  • ~/.nomadnetwork/  (NomadNet data)"
                echo "  • ~/.lxmf/          (messages)"
                echo ""
                echo -n "Type 'RESET' to confirm factory reset: "
                read -r CONFIRM

                if [ "$CONFIRM" = "RESET" ]; then
                    print_info "Creating final backup before reset..."
                    create_backup

                    print_info "Removing configuration directories..."
                    [ -d "$REAL_HOME/.reticulum" ] && rm -rf "$REAL_HOME/.reticulum" && print_success "Removed ~/.reticulum"
                    [ -d "$REAL_HOME/.nomadnetwork" ] && rm -rf "$REAL_HOME/.nomadnetwork" && print_success "Removed ~/.nomadnetwork"
                    [ -d "$REAL_HOME/.lxmf" ] && rm -rf "$REAL_HOME/.lxmf" && print_success "Removed ~/.lxmf"

                    print_success "Factory reset complete"
                    print_info "Run 'rnsd --daemon' to create fresh configuration"
                    log_message "Factory reset performed - all configurations removed"
                else
                    print_info "Reset cancelled - confirmation not received"
                fi
                pause_for_input
                ;;
            0|"")
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
    done
}

update_system_packages() {
    print_section "Updating System Packages"

    echo -e "${YELLOW}Update all system packages?${NC}"
    echo "This will run: sudo apt update && sudo apt upgrade -y"
    if ! confirm_action "Proceed?" "y"; then
        print_warning "Skipping system updates"
        return 0
    fi

    print_info "Updating package lists..."
    if retry_with_backoff 3 run_with_timeout "$APT_TIMEOUT" sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Upgrading packages (this may take several minutes)..."
        if retry_with_backoff 2 run_with_timeout "$APT_TIMEOUT" sudo apt upgrade -y 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "System packages updated"
            log_message "System packages upgraded successfully"
            NEEDS_REBOOT=true
            return 0
        else
            print_error "Failed to upgrade packages"
            return 1
        fi
    else
        print_error "Failed to update package lists"
        show_error_help "network" ""
        return 1
    fi
}

#########################################################
# Main Program Logic
#########################################################

# Startup health check (adapted from meshforge startup_health.py)
# Runs quick environment validation before entering main menu
run_startup_health_check() {
    local warnings=0

    log_message "Running startup health check..."

    # 1. Disk space check (need space for installs/backups)
    if ! check_disk_space 500 "$REAL_HOME"; then
        ((warnings++))
    fi

    # 2. Memory check
    if ! check_available_memory; then
        ((warnings++))
    fi

    # 3. PEP 668 notification (Debian 12+ restricts pip)
    if [ "$PEP668_DETECTED" = true ]; then
        log_message "PEP 668 detected: Python is externally managed (Debian 12+)"
        print_info "Python externally managed (PEP 668) - will use --break-system-packages where needed"
    fi

    # 4. SSH session notice
    if [ "$IS_SSH" = true ]; then
        log_debug "Running via SSH session"
    fi

    # 5. Git safe.directory for common paths
    ensure_git_safe_directory "$MESHCHAT_DIR"
    ensure_git_safe_directory "$SIDEBAND_DIR"

    # 6. Log directory writable
    if ! touch "$UPDATE_LOG" 2>/dev/null; then
        print_warning "Cannot write to log file: $UPDATE_LOG"
        UPDATE_LOG="/tmp/rns_management_$(date +%Y%m%d_%H%M%S).log"
        print_info "Falling back to: $UPDATE_LOG"
        ((warnings++))
    fi

    if [ $warnings -gt 0 ]; then
        log_warn "Startup health check completed with $warnings warning(s)"
    else
        log_message "Startup health check passed"
    fi

    return 0
}

# First-Run Wizard (adapted from meshforge first_run_mixin.py)
# Detects when Reticulum is not yet configured and guides the user
# through initial setup. Non-destructive - only runs when no config exists.
first_run_wizard() {
    # Only trigger if no Reticulum config exists
    if [ -f "$REAL_HOME/.reticulum/config" ]; then
        return 0
    fi

    # Check if RNS is installed at all
    local rns_installed=false
    if command -v rnsd &>/dev/null || pip3 show rns &>/dev/null 2>&1; then
        rns_installed=true
    fi

    print_header
    print_box_top
    print_box_line "${CYAN}${BOLD}Welcome to RNS Management Tool${NC}"
    print_box_line "First-time setup detected"
    print_box_bottom
    echo ""

    if [ "$rns_installed" = false ]; then
        print_info "Reticulum (RNS) is not installed yet."
        echo ""
        echo "  This wizard will help you:"
        echo "    1. Install the Reticulum network stack"
        echo "    2. Choose a configuration template"
        echo "    3. Start the rnsd daemon"
        echo ""

        if ! confirm_action "Run first-time setup?" "y"; then
            print_info "Skipping setup - you can install later from the main menu"
            return 0
        fi

        # Step 1: Prerequisites
        print_section "Step 1: Prerequisites"
        if ! check_python || ! check_pip; then
            print_info "Installing prerequisites..."
            install_prerequisites
        else
            print_success "Python and pip are available"
        fi

        # Step 2: Install RNS
        print_section "Step 2: Install Reticulum"
        install_reticulum_ecosystem
        invalidate_status_cache
    else
        print_info "Reticulum is installed but no configuration file exists."
        echo ""
        echo "  This wizard will help you:"
        echo "    1. Choose a configuration template"
        echo "    2. Start the rnsd daemon"
        echo ""

        if ! confirm_action "Run first-time setup?" "y"; then
            print_info "Skipping - rnsd will create a default config on first start"
            return 0
        fi
    fi

    # Step 3: Config template selection
    print_section "Step 3: Choose Configuration"
    echo ""
    echo "  How will you use Reticulum?"
    echo ""
    echo "   1) Local network only (simplest)"
    echo "      Discover peers on your LAN automatically"
    echo ""
    echo "   2) Connect to the wider network via internet"
    echo "      Join public transport nodes over TCP"
    echo ""
    echo "   3) LoRa radio with RNODE device"
    echo "      Off-grid communication via LoRa"
    echo ""
    echo "   4) Transport node (advanced)"
    echo "      Route traffic for other peers"
    echo ""
    echo "   5) Skip - use default config"
    echo "      rnsd will create a minimal config"
    echo ""
    echo -n "Select setup type (1-5): "
    read -r SETUP_CHOICE

    local template_dir="$SCRIPT_DIR/config_templates"
    local applied_template=false

    case $SETUP_CHOICE in
        1)
            if [ -f "$template_dir/minimal.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/minimal.conf" "$REAL_HOME/.reticulum/config"
                print_success "Minimal configuration applied"
                applied_template=true
            fi
            ;;
        2)
            if [ -f "$template_dir/tcp_client.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/tcp_client.conf" "$REAL_HOME/.reticulum/config"
                print_success "TCP client configuration applied"
                print_info "Connected to Dublin Hub by default"
                applied_template=true
            fi
            ;;
        3)
            if [ -f "$template_dir/lora_rnode.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/lora_rnode.conf" "$REAL_HOME/.reticulum/config"
                print_success "LoRa RNODE configuration applied"
                print_warning "Edit ~/.reticulum/config to set your device port and frequency"
                applied_template=true
            fi
            ;;
        4)
            if [ -f "$template_dir/transport_node.conf" ]; then
                mkdir -p "$REAL_HOME/.reticulum"
                cp "$template_dir/transport_node.conf" "$REAL_HOME/.reticulum/config"
                print_success "Transport node configuration applied"
                print_warning "Review ~/.reticulum/config before starting"
                applied_template=true
            fi
            ;;
        5|"")
            print_info "Skipping template - rnsd will create default config"
            ;;
        *)
            print_info "Skipping template - rnsd will create default config"
            ;;
    esac

    # Step 4: Start rnsd
    if [ "$applied_template" = true ] || command -v rnsd &>/dev/null; then
        echo ""
        if confirm_action "Start rnsd daemon now?" "y"; then
            start_services
        else
            print_info "Start later with: rnsd --daemon"
        fi
    fi

    echo ""
    print_success "First-time setup complete"
    log_message "First-run wizard completed (template: ${SETUP_CHOICE:-skipped})"
    pause_for_input
}

main() {
    # Initialize
    detect_environment
    detect_available_tools
    log_message "=== RNS Management Tool Started ==="
    log_message "Version: $SCRIPT_VERSION"
    log_message "REAL_HOME=$REAL_HOME, SCRIPT_DIR=$SCRIPT_DIR"

    # Run startup health check
    run_startup_health_check

    # First-run wizard (only triggers when no config exists)
    first_run_wizard

    # Main menu loop
    while true; do
        show_main_menu

        case $MENU_CHOICE in
            1)
                # Install/Update Reticulum
                if ! check_python || ! check_pip; then
                    echo -e "\n${YELLOW}Prerequisites missing.${NC}"
                    if confirm_action "Install prerequisites now?" "y"; then
                        install_prerequisites
                    else
                        pause_for_input
                        continue
                    fi
                fi

                create_backup
                stop_services
                install_reticulum_ecosystem
                start_services
                pause_for_input
                ;;
            2)
                # RNODE Installation
                safe_call "RNODE Configuration" configure_rnode_interactive
                ;;
            3)
                # Install NomadNet
                check_python && check_pip
                safe_call "NomadNet Install" update_pip_package "nomadnet" "NomadNet"
                pause_for_input
                ;;
            4)
                # Install MeshChat
                safe_call "MeshChat Install" install_meshchat
                pause_for_input
                ;;
            5)
                # Install Sideband
                safe_call "Sideband Install" install_sideband
                pause_for_input
                ;;
            6)
                # Status & Diagnostics
                safe_call "Diagnostics" run_diagnostics
                echo ""
                safe_call "Service Status" show_service_status
                pause_for_input
                ;;
            7)
                # Manage Services
                safe_call "Services Menu" services_menu
                ;;
            8)
                # Backup/Restore
                safe_call "Backup/Restore" backup_restore_menu
                ;;
            9)
                # Advanced Options
                safe_call "Advanced Options" advanced_menu
                ;;
            q|Q)
                # Quick Mode / Emergency
                safe_call "Quick Mode" emergency_quick_mode
                ;;
            h|H|\?)
                # Help
                show_help
                ;;
            0)
                # Exit
                print_section "Thank You"
                echo -e "${CYAN}Thank you for using RNS Management Tool!${NC}"
                echo ""
                log_message "=== RNS Management Tool Ended ==="

                if [ "$NEEDS_REBOOT" = true ]; then
                    echo -e "${YELLOW}${BOLD}System reboot recommended${NC}"
                    if confirm_action "Reboot now?"; then
                        sudo reboot
                    fi
                fi
                exit 0
                ;;
            *)
                print_error "Invalid option. Press 'h' for help."
                sleep 1
                ;;
        esac
    done
}

#########################################################
# Script Entry Point
#########################################################

# Ensure we're running on a supported system
if [ "$(uname)" != "Linux" ]; then
    echo "Error: This script is designed for Linux systems"
    echo "For Windows, please use rns_management_tool.ps1"
    exit 1
fi

# Run main program
main

exit 0
