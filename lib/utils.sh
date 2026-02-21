# shellcheck shell=bash
# shellcheck disable=SC2034  # Cross-module globals (PI_MODEL, OS_VERSION, HAS_* flags, etc.) used by other sourced modules
# shellcheck disable=SC2317  # Functions called via TUI menus/traps appear unreachable to static analysis
#########################################################
# lib/utils.sh — Utility functions, logging, caching
# Sourced by rns_management_tool.sh
#########################################################

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

    log_message "Tools detected: RNS=$(count_rns_tools)/8 (rnsd=$HAS_RNSD rnstatus=$HAS_RNSTATUS rnpath=$HAS_RNPATH rnprobe=$HAS_RNPROBE rncp=$HAS_RNCP rnx=$HAS_RNX rnid=$HAS_RNID rnodeconf=$HAS_RNODECONF)"
    log_message "Dependencies: python3=$HAS_PYTHON3 pip=$HAS_PIP node=$HAS_NODE git=$HAS_GIT"
}

# Count available RNS tools (eliminates duplicate counting logic)
count_rns_tools() {
    local count=0
    [ "$HAS_RNSD" = true ] && ((count++))
    [ "$HAS_RNSTATUS" = true ] && ((count++))
    [ "$HAS_RNPATH" = true ] && ((count++))
    [ "$HAS_RNPROBE" = true ] && ((count++))
    [ "$HAS_RNCP" = true ] && ((count++))
    [ "$HAS_RNX" = true ] && ((count++))
    [ "$HAS_RNID" = true ] && ((count++))
    [ "$HAS_RNODECONF" = true ] && ((count++))
    echo "$count"
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
    rm -f "${TMPDIR:-/tmp}"/rns_mgmt_*.tmp 2>/dev/null
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
            echo "  3) Verify you own the files: ls -la \"$context\""
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
            echo "  4) Check permissions: sudo chmod 666 \"$context\""
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

# Centralized service status check (adapted from meshforge service_check.py)
# Single source of truth for all service detection - avoids scattered pgrep calls
# Usage: check_service_status <service_name>
# Returns: 0 if running, 1 if stopped
check_service_status() {
    local service="$1"
    case "$service" in
        rnsd)
            # Prefer systemctl (single source of truth), fall back to exact pgrep
            # Never use pgrep -f — it matches editors, grep, and the script itself
            if command -v systemctl &>/dev/null && systemctl --user is-active rnsd.service &>/dev/null 2>&1; then
                return 0
            fi
            pgrep -x "rnsd" > /dev/null 2>&1
            ;;
        meshtasticd)
            if command -v systemctl &>/dev/null && systemctl is-active --quiet meshtasticd 2>/dev/null; then
                return 0
            fi
            pgrep -x "meshtasticd" > /dev/null 2>&1
            ;;
        nomadnet)
            pgrep -x "nomadnet" > /dev/null 2>&1
            ;;
        meshchat)
            # Match node process running meshchat, not any process mentioning the string
            pgrep -f "node.*reticulum-meshchat" > /dev/null 2>&1
            ;;
        *)
            pgrep -x "$service" > /dev/null 2>&1
            ;;
    esac
}

# Convenience wrapper (backward-compatible)
is_rnsd_running() {
    check_service_status "rnsd"
}

# meshtasticd HTTP API health check (simplified from meshforge meshtastic_http.py)
# Reads port from config first, falls back to common ports
MESHTASTICD_HTTP_URL=""
check_meshtasticd_http_api() {
    MESHTASTICD_HTTP_URL=""

    if ! command -v curl &>/dev/null; then
        return 1
    fi

    # Try to read configured port first (avoids probing 16 combinations)
    local config_port=""
    local config_path="/etc/meshtasticd/config.yaml"
    if [ -r "$config_path" ]; then
        config_port=$(grep -A2 "Webserver:" "$config_path" 2>/dev/null | grep "Port:" | awk '{print $2}' | tr -d '[:space:]')
    fi

    # Build port list: configured port first, then common fallbacks
    local ports=()
    [ -n "$config_port" ] && ports+=("$config_port")
    for p in 443 9443 80 4403; do
        [ "$p" != "$config_port" ] && ports+=("$p")
    done

    for port in "${ports[@]}"; do
        local scheme="https"
        [ "$port" -eq 80 ] && scheme="http"

        local base_url="${scheme}://127.0.0.1:${port}"

        # Single probe: JSON report endpoint
        local response
        if response=$(curl -sk --connect-timeout 2 --max-time 3 \
            -H "Accept: application/json" \
            "${base_url}/json/report" 2>/dev/null) && [ -n "$response" ]; then
            local trimmed
            trimmed="${response#"${response%%[![:space:]]*}"}"
            if [[ "$trimmed" == "{"* ]]; then
                MESHTASTICD_HTTP_URL="$base_url"
                return 0
            fi
        fi

        # Fallback: check HTTP status on protobuf endpoint
        local http_code
        http_code=$(curl -sk --connect-timeout 2 --max-time 3 \
            -o /dev/null -w "%{http_code}" \
            "${base_url}/api/v1/fromradio" 2>/dev/null)
        case "$http_code" in
            200|204|400|404|405)
                MESHTASTICD_HTTP_URL="$base_url"
                return 0
                ;;
        esac
    done

    return 1
}

# meshtasticd config validation
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

    if ! grep -q "Webserver:" "$config_path" 2>/dev/null; then
        echo "Fix: Add 'Webserver:' section with 'Port: 443' to $config_path"
        return 1
    fi

    local uncommented
    uncommented=$(grep "Webserver:" "$config_path" 2>/dev/null | grep -v "^[[:space:]]*#" | head -1)
    if [ -z "$uncommented" ]; then
        echo "Fix: Webserver section is commented out in $config_path"
        return 1
    fi

    echo "Config has Webserver section — check meshtasticd logs if API unreachable"
    return 0
}

# Validate RNS destination hash format (hex string, 20-64 chars)
# Usage: validate_rns_hash "$hash" || return 1
validate_rns_hash() {
    local hash="$1"
    if [ -z "$hash" ]; then
        print_error "No destination hash provided"
        return 1
    fi
    if [[ ! "$hash" =~ ^[0-9a-fA-F]{20,64}$ ]]; then
        print_error "Invalid destination hash format (expected 20-64 hex characters)"
        return 1
    fi
    return 0
}

# Safe call wrapper (adapted from meshforge _safe_call pattern)
safe_call() {
    local label="$1"
    shift

    local rc=0
    "$@" || rc=$?

    if [ $rc -eq 0 ]; then
        return 0
    fi

    log_error "safe_call: '$label' failed with exit code $rc"

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
            print_info "$label: Interrupted by user"
            ;;
        *)
            print_error "$label failed (exit code: $rc)"
            ;;
    esac

    return $rc
}

# Cached status queries (adapted from meshforge status_bar.py)
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

get_rnsd_uptime() {
    local pid="${_CACHE_RNSD_PID:-}"
    [ -z "$pid" ] && echo "" && return

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
        _CACHE_RNS_VER=$(get_installed_version "rns")
        _CACHE_RNS_TIME=$now
    fi
    echo "$_CACHE_RNS_VER"
}

get_cached_lxmf_version() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_LXMF_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_LXMF_VER" ]; then
        _CACHE_LXMF_VER=$(get_installed_version "lxmf")
        _CACHE_LXMF_TIME=$now
    fi
    echo "$_CACHE_LXMF_VER"
}

# Invalidate all status caches (call after install/service changes)
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
