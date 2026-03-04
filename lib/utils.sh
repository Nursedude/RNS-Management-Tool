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
            # Add jitter (0-1s) to prevent thundering herd (meshforge ReconnectConfig pattern)
            local jitter=$(( RANDOM % 2 ))
            local total_delay=$((delay + jitter))
            print_warning "Attempt $attempt/$max_retries failed, retrying in ${total_delay}s..."
            log_warn "Retry $attempt/$max_retries for: $*"
            sleep "$total_delay"
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

    # Dependency version validation (adapted from meshforge dependency_guard.py)
    # Log warnings for outdated versions, don't block startup
    if [ "$HAS_PYTHON3" = true ]; then
        local pyver
        pyver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
        if [ -n "$pyver" ]; then
            local pymajor pyminor
            pymajor="${pyver%%.*}"
            pyminor="${pyver##*.}"
            if [ "$pymajor" -lt 3 ] || { [ "$pymajor" -eq 3 ] && [ "$pyminor" -lt 7 ]; }; then
                log_warn "Python $pyver detected — RNS requires 3.7+"
            fi
        fi
    fi

    if [ "$HAS_NODE" = true ] && [ "$HAS_MESHCHAT" = true ]; then
        local nodever
        nodever=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
        if [ -n "$nodever" ] && [ "$nodever" -lt 18 ] 2>/dev/null; then
            log_warn "Node.js v${nodever} detected — MeshChat requires 18+"
        fi
    fi
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
    if [ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$UPDATE_LOG"
    fi
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$UPDATE_LOG"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$UPDATE_LOG"
}

# Cleanup handler (adapted from meshforge set -e pattern + cf3fb86 terminal restoration)
# Ensures temp files are cleaned, terminal is restored, and log is flushed on exit/interrupt
cleanup_on_exit() {
    local exit_code=$?
    # Restore terminal state (meshforge TUI stability fix — prevents dirty terminal)
    tput cnorm 2>/dev/null || true   # Show cursor (in case hidden during progress)
    stty echo 2>/dev/null || true   # Re-enable echo (in case disabled during password input)
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
trap 'tput cnorm 2>/dev/null; stty echo 2>/dev/null; echo ""; print_warning "Interrupted by user"; exit 130' INT TERM

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
# Returns: 0 if running (any active state), 1 if stopped
# Side effect: Sets _LAST_SERVICE_STATE to granular health state string
check_service_status() {
    local service="$1"
    _LAST_SERVICE_STATE="$SVC_STATE_STOPPED"
    case "$service" in
        rnsd)
            # Prefer systemctl (single source of truth), fall back to exact pgrep
            # Never use pgrep -f — it matches editors, grep, and the script itself
            local rnsd_detected=false
            if command -v systemctl &>/dev/null && systemctl --user is-active rnsd.service &>/dev/null 2>&1; then
                rnsd_detected=true
            elif pgrep -x "rnsd" > /dev/null 2>&1; then
                rnsd_detected=true
            fi

            if [ "$rnsd_detected" = true ]; then
                # Check port binding for zombie/health classification
                local port_bound=false
                if command -v ss &>/dev/null; then
                    ss -ulnp 2>/dev/null | grep -q ':37428 ' && port_bound=true
                elif command -v netstat &>/dev/null; then
                    netstat -ulnp 2>/dev/null | grep -q ':37428 ' && port_bound=true
                else
                    # If neither ss nor netstat available, trust process detection
                    port_bound=true
                fi

                # Get uptime for state classification
                local uptime_secs=999
                local rnsd_pid
                rnsd_pid=$(pgrep -x "rnsd" 2>/dev/null | head -1)
                if [ -n "$rnsd_pid" ] && [ -d "/proc/$rnsd_pid" ]; then
                    local elapsed
                    elapsed=$(ps -o etimes= -p "$rnsd_pid" 2>/dev/null | tr -d ' ')
                    [ -n "$elapsed" ] && uptime_secs="$elapsed"
                fi

                # Classify health state based on port binding + uptime
                if [ "$port_bound" = true ]; then
                    if [ "$uptime_secs" -le 10 ]; then
                        _LAST_SERVICE_STATE="$SVC_STATE_STARTING"
                    else
                        _LAST_SERVICE_STATE="$SVC_STATE_RUNNING"
                    fi
                    return 0
                else
                    # Port not bound — zombie or still starting
                    if [ "$uptime_secs" -gt 30 ]; then
                        _LAST_SERVICE_STATE="$SVC_STATE_ZOMBIE"
                        log_warn "rnsd detected but UDP port 37428 not bound (zombie, uptime ${uptime_secs}s)"
                    else
                        _LAST_SERVICE_STATE="$SVC_STATE_STARTING"
                    fi
                    # Zombie returns 1 (not healthy), starting returns 0
                    if [ "$_LAST_SERVICE_STATE" = "$SVC_STATE_ZOMBIE" ]; then
                        return 1
                    fi
                    return 0
                fi
            fi
            _LAST_SERVICE_STATE="$SVC_STATE_STOPPED"
            return 1
            ;;
        meshtasticd)
            local mtd_detected=false
            if command -v systemctl &>/dev/null && systemctl is-active --quiet meshtasticd 2>/dev/null; then
                mtd_detected=true
            elif pgrep -x "meshtasticd" > /dev/null 2>&1; then
                mtd_detected=true
            fi
            if [ "$mtd_detected" = true ]; then
                _LAST_SERVICE_STATE="$SVC_STATE_RUNNING"
                return 0
            fi
            _LAST_SERVICE_STATE="$SVC_STATE_STOPPED"
            return 1
            ;;
        nomadnet)
            if pgrep -x "nomadnet" > /dev/null 2>&1; then
                _LAST_SERVICE_STATE="$SVC_STATE_RUNNING"
                return 0
            fi
            return 1
            ;;
        meshchat)
            # Match node process running meshchat, not any process mentioning the string
            if pgrep -f "node.*reticulum-meshchat" > /dev/null 2>&1; then
                _LAST_SERVICE_STATE="$SVC_STATE_RUNNING"
                return 0
            fi
            return 1
            ;;
        *)
            if pgrep -x "$service" > /dev/null 2>&1; then
                _LAST_SERVICE_STATE="$SVC_STATE_RUNNING"
                return 0
            fi
            return 1
            ;;
    esac
}

# Get granular health state for a service
# Usage: state=$(get_service_health "rnsd")
get_service_health() {
    local service="$1"
    check_service_status "$service"
    echo "$_LAST_SERVICE_STATE"
}

# Convenience wrapper (backward-compatible)
is_rnsd_running() {
    check_service_status "rnsd"
}

# Service pre-flight check: blocking mode (meshforge advisory/blocking pattern)
# Usage: require_service "rnsd" "Network tools require rnsd to be running" || return 1
require_service() {
    local service="$1"
    local message="${2:-$service must be running for this operation}"

    if ! check_service_status "$service"; then
        print_error "$message"
        echo ""
        case "$service" in
            rnsd)
                echo -e "  ${CYAN}Start with:${NC} rnsd --daemon"
                echo -e "  ${CYAN}Or from menu:${NC} Services > Start rnsd daemon"
                ;;
            meshtasticd)
                echo -e "  ${CYAN}Start with:${NC} sudo systemctl start meshtasticd"
                ;;
        esac
        return 1
    fi
    return 0
}

# Service pre-flight check: advisory mode (warn but continue)
# Usage: advise_service "rnsd" "stopped" "Editing config while rnsd runs may cause issues"
advise_service() {
    local service="$1"
    local desired_state="$2"  # "running" or "stopped"
    local message="${3:-Consider checking $service state before proceeding}"

    local is_running=false
    check_service_status "$service" && is_running=true

    if [ "$desired_state" = "stopped" ] && [ "$is_running" = true ]; then
        print_warning "$message"
        if ! confirm_action "Continue anyway?" "y"; then
            return 1
        fi
    elif [ "$desired_state" = "running" ] && [ "$is_running" = false ]; then
        print_warning "$message"
        if ! confirm_action "Continue anyway?" "y"; then
            return 1
        fi
    fi
    return 0
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
        log_debug "meshtasticd HTTP probe failed: ${base_url} (http_code=${http_code:-none})"
    done

    log_debug "meshtasticd HTTP API not reachable on any port"
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

# validate_rns_hash moved to lib/validation.sh (centralized validation module)

# Safe call wrapper (adapted from meshforge _safe_call pattern)
# Enhanced: captures stderr for error pattern matching + fix hints
safe_call() {
    local label="$1"
    shift

    local rc=0
    local stderr_file
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/rns_mgmt_XXXXXX.tmp")

    "$@" 2>"$stderr_file" || rc=$?

    if [ $rc -eq 0 ]; then
        rm -f "$stderr_file"
        return 0
    fi

    # Capture last meaningful stderr line for context
    local last_err=""
    if [ -s "$stderr_file" ]; then
        last_err=$(tail -1 "$stderr_file" | head -c 200)
        log_error "safe_call: '$label' stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

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
            # Match known error patterns from stderr for fix hints
            # (meshforge _safe_call exception-specific handling pattern)
            if [ -n "$last_err" ]; then
                if [[ "$last_err" == *"ModuleNotFoundError"* ]] || [[ "$last_err" == *"ImportError"* ]]; then
                    show_error_help "python" ""
                elif [[ "$last_err" == *"Permission denied"* ]] || [[ "$last_err" == *"EACCES"* ]]; then
                    show_error_help "permission" ""
                elif [[ "$last_err" == *"Connection refused"* ]] || [[ "$last_err" == *"Network unreachable"* ]]; then
                    show_error_help "network" ""
                elif [[ "$last_err" == *"externally-managed"* ]]; then
                    show_error_help "pip" ""
                else
                    print_info "Last error: $last_err"
                fi
            fi
            ;;
    esac

    return $rc
}

# Cached status queries (adapted from meshforge status_bar.py)
# Now caches granular health states instead of simple running/stopped
get_cached_rnsd_status() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_RNSD_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_RNSD_STATUS" ]; then
        check_service_status "rnsd"
        _CACHE_RNSD_STATUS="$_LAST_SERVICE_STATE"
        _CACHE_RNSD_PID=$(pgrep -x "rnsd" 2>/dev/null | head -1)
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

# Cached meshtasticd status (avoids hitting systemctl+curl on every menu redraw)
# Adapted from meshforge service_check.py caching pattern
# Now caches granular health states
get_cached_meshtasticd_status() {
    local now
    now=$(date +%s)
    local age=$(( now - _CACHE_MTD_TIME ))
    if [ $age -ge $STATUS_CACHE_TTL ] || [ -z "$_CACHE_MTD_STATUS" ]; then
        check_service_status "meshtasticd"
        _CACHE_MTD_STATUS="$_LAST_SERVICE_STATE"
        # If running, check HTTP API reachability for finer-grained state
        if [ "$_CACHE_MTD_STATUS" = "$SVC_STATE_RUNNING" ]; then
            if ! check_meshtasticd_http_api; then
                _CACHE_MTD_STATUS="$SVC_STATE_UNREACHABLE"
            fi
        fi
        _CACHE_MTD_TIME=$now
    fi
    echo "$_CACHE_MTD_STATUS"
}

# Invalidate all status caches (call after install/service changes)
invalidate_status_cache() {
    _LAST_SERVICE_STATE=""
    _CACHE_RNSD_STATUS=""
    _CACHE_RNSD_TIME=0
    _CACHE_RNSD_PID=""
    _CACHE_RNS_VER=""
    _CACHE_RNS_TIME=0
    _CACHE_LXMF_VER=""
    _CACHE_LXMF_TIME=0
    _CACHE_MTD_STATUS=""
    _CACHE_MTD_TIME=0
    # Clear pip version cache (defined in lib/install.sh)
    if declare -p _VERSION_CACHE &>/dev/null 2>&1; then
        _VERSION_CACHE=()
    fi
    detect_available_tools
}
