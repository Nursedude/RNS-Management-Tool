# shellcheck shell=bash
# shellcheck disable=SC2034  # Cross-module globals (PI_MODEL, OS_VERSION, HAS_* flags, etc.) used by other sourced modules
# shellcheck disable=SC2317  # Functions called via TUI menus/traps appear unreachable to static analysis
#########################################################
# lib/utils.sh — Utility functions, logging, caching
# Sourced by rns_management_tool.sh
#########################################################

# Lightweight wrapper around the command -v lookup — single source of truth so
# callsites don't repeat the same probe six times across modules.
has_command() {
    command -v "$1" &>/dev/null
}

# Timeout wrapper for network operations
run_with_timeout() {
    local timeout_val="$1"
    shift
    if has_command timeout; then
        timeout "$timeout_val" "$@"
    else
        # Fallback if timeout command not available
        "$@"
    fi
}

# Atomic file write (adapted from meshforge paths.py atomic_write_text)
# Prevents partial/corrupt files on crash or power loss by writing to temp file
# then atomically renaming. Safe for config and identity files.
# Preserves the target file's existing mode — mktemp creates files at 0600, so
# without this, updates to 0644/0640 config files would be silently tightened.
# Usage: write_atomic "/path/to/file" "content"
write_atomic() {
    local target="$1"
    local content="$2"
    local target_dir
    target_dir=$(dirname "$target")

    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir" || {
            log_error "write_atomic: cannot create directory $target_dir"
            return 1
        }
    fi

    # Capture existing mode before writing so we can restore it after rename
    local original_mode=""
    if [ -e "$target" ]; then
        original_mode=$(stat -c '%a' "$target" 2>/dev/null || \
                        stat -f '%Lp' "$target" 2>/dev/null)
    fi

    local tmpfile
    tmpfile=$(mktemp "${target}.XXXXXX") || {
        log_error "write_atomic: cannot create temp file for $target"
        return 1
    }

    # Write content, sync to disk, restore mode, then atomic rename
    if printf '%s' "$content" > "$tmpfile" && sync "$tmpfile" 2>/dev/null; then
        if [ -n "$original_mode" ]; then
            chmod "$original_mode" "$tmpfile" 2>/dev/null || true
        fi
        if mv -f "$tmpfile" "$target"; then
            return 0
        fi
    fi

    # Cleanup on failure
    rm -f "$tmpfile" 2>/dev/null
    log_error "write_atomic: failed to write $target"
    return 1
}

# Classify error as transient (worth retrying) or permanent (bail immediately)
# Adapted from meshforge RetryPolicy (message_queue.py) error classification
# Returns 0 for transient, 1 for permanent
_is_transient_error() {
    local err_text="$1"
    [ -z "$err_text" ] && return 0  # unknown errors default to transient (retry)

    local err_lower
    err_lower=$(echo "$err_text" | tr '[:upper:]' '[:lower:]')

    # Permanent errors — retrying won't help
    case "$err_lower" in
        *"permission denied"*|*"no such file"*|*"no such directory"*)  return 1 ;;
        *"module not found"*|*"no module named"*|*"import error"*)    return 1 ;;
        *"syntax error"*|*"invalid argument"*|*"not a valid"*)        return 1 ;;
        *"command not found"*|*"not installed"*)                      return 1 ;;
        *"already installed"*|*"already up-to-date"*)                 return 1 ;;
    esac

    # Transient errors — worth retrying.
    # NOTE: pattern order matters — shellcheck SC2221 will flag any later
    # pattern that's a strict superset of an earlier one. The "temporarily
    # unavailable" wildcard already covers "resource temporarily unavailable"
    # so we list "try again" (errno EAGAIN string) on its own.
    case "$err_lower" in
        *"connection refused"*|*"connection reset"*|*"connection timed out"*) return 0 ;;
        *"timeout"*|*"timed out"*|*"temporarily unavailable"*)               return 0 ;;
        *"network unreachable"*|*"could not resolve"*|*"name resolution"*)   return 0 ;;
        *"no route to host"*|*"broken pipe"*|*"reset by peer"*)              return 0 ;;
        *"503"*|*"502"*|*"429"*|*"service unavailable"*)                     return 0 ;;
        # apt/dpkg lock contention — another package manager is running, retrying works
        *"could not get lock"*|*"could not open lock file"*|*"unable to lock"*) return 0 ;;
        # Generic transient errno strings (EAGAIN translates to "Try again")
        *"try again"*)                                                       return 0 ;;
    esac

    return 0  # default: assume transient, retry
}

# Retry with exponential backoff (adapted from meshforge install_reliability_triage.md)
# Enhanced with transient vs permanent error classification (meshforge RetryPolicy pattern)
# and interruptible delays (meshforge ReconnectStrategy.wait pattern)
# Usage: retry_with_backoff <max_retries> <command...>
# Retries with 2s, 4s, 8s... delays between attempts
retry_with_backoff() {
    local max_retries="$1"
    shift
    local attempt=1
    local delay=2
    local err_file
    err_file=$(mktemp "${TMPDIR:-/tmp}/rns_retry_XXXXXX")

    while [ $attempt -le "$max_retries" ]; do
        # Capture stderr to file for error classification; still show it to caller
        if "$@" 2>"$err_file"; then
            rm -f "$err_file"
            return 0
        fi
        local rc=$?
        # Replay stderr so callers still see it
        cat "$err_file" >&2 2>/dev/null || true

        if [ $attempt -lt "$max_retries" ]; then
            local err_text
            err_text=$(cat "$err_file" 2>/dev/null)

            # Classify error: bail immediately on permanent failures
            if ! _is_transient_error "$err_text"; then
                log_warn "Permanent error detected, skipping remaining retries: $err_text"
                rm -f "$err_file"
                return $rc
            fi

            # Add jitter (0-1s) to prevent thundering herd (meshforge ReconnectConfig pattern)
            local jitter=$(( RANDOM % 2 ))
            local total_delay=$((delay + jitter))
            print_warning "Attempt $attempt/$max_retries failed, retrying in ${total_delay}s..."
            log_warn "Retry $attempt/$max_retries (transient error) for: $*"
            # Interruptible sleep: exits immediately on Ctrl-C instead of waiting
            # (adapted from meshforge ReconnectStrategy.wait using threading.Event)
            sleep "$total_delay" &
            wait $! 2>/dev/null || { rm -f "$err_file"; return 130; }
            delay=$((delay * 2))
        fi
        ((attempt++))
    done

    rm -f "$err_file"
    log_error "All $max_retries attempts failed for: $*"
    return 1
}

# Inline spinner for long-running subprocesses (adapted from meshforge progress gauge)
# Usage: run_with_spinner "Installing RNS..." pip3 install rns
# Runs command in background, shows animated spinner, returns command's exit code.
# Output goes to $UPDATE_LOG. Do NOT use for commands needing interactive input (sudo prompts).
run_with_spinner() {
    local label="$1"
    shift

    # Non-interactive mode: run directly without spinner
    if [ "$IS_INTERACTIVE" != true ] || [ ! -t 1 ]; then
        "$@" >> "$UPDATE_LOG" 2>&1
        return $?
    fi

    # Choose spinner characters based on terminal capability
    local -a frames
    if [ "$HAS_COLOR" = true ]; then
        frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    else
        frames=("|" "/" "-" "\\")
    fi

    # Run command in background, capturing output to log
    "$@" >> "$UPDATE_LOG" 2>&1 &
    local cmd_pid=$!

    # Hide cursor during spinner
    tput civis 2>/dev/null || true

    local i=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
        printf '\r  %s %s ' "${frames[$((i % ${#frames[@]}))]}" "$label"
        sleep 0.1
        ((i++))
    done

    # Get exit code from background command
    wait "$cmd_pid"
    local rc=$?

    # Clear spinner line, restore cursor
    printf '\r%*s\r' $((${#label} + 6)) ""
    tput cnorm 2>/dev/null || true

    if [ $rc -eq 0 ]; then
        print_success "$label done"
    else
        print_error "$label failed (exit code: $rc)"
    fi

    return $rc
}

# Port conflict resolver (adapted from meshforge ConflictResolver)
# Identifies process holding a port and offers to stop it.
# Usage: resolve_port_conflict "37428" "rnsd"
resolve_port_conflict() {
    local port="$1"
    local service="$2"

    # Identify blocking process
    local holder_pid="" holder_name=""
    if command -v ss &>/dev/null; then
        local ss_line
        ss_line=$(ss -ulnp 2>/dev/null | grep ":${port} " | head -1)
        holder_pid=$(echo "$ss_line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
        holder_name=$(echo "$ss_line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
    elif command -v netstat &>/dev/null; then
        local net_line
        net_line=$(netstat -ulnp 2>/dev/null | grep ":${port} " | head -1)
        holder_pid=$(echo "$net_line" | awk '{print $NF}' | cut -d/ -f1)
        holder_name=$(echo "$net_line" | awk '{print $NF}' | cut -d/ -f2)
    fi

    if [ -z "$holder_pid" ] || ! [[ "$holder_pid" =~ ^[0-9]+$ ]]; then
        print_info "Port $port conflict detected but cannot identify blocking process"
        return 1
    fi

    echo ""
    print_warning "Port $port is in use by: $holder_name (PID $holder_pid)"
    print_info "This port is needed by $service"
    echo ""

    # Check if it's our own service (stale instance)
    if [ "$holder_name" = "$service" ]; then
        print_info "This appears to be a stale $service instance"
    fi

    # Check ownership - only kill processes we own
    local proc_uid
    proc_uid=$(stat -c %u "/proc/$holder_pid" 2>/dev/null || echo "")
    if [ -n "$proc_uid" ] && [ "$proc_uid" != "$(id -u)" ] && [ "$proc_uid" != "0" ]; then
        print_warning "Process is owned by another user (UID $proc_uid)"
        print_info "Stop it manually: sudo kill $holder_pid"
        return 1
    fi

    echo "   1) Stop the blocking process (SIGTERM)"
    echo "   2) Force stop (SIGKILL)"
    echo "   3) Skip - leave conflict unresolved"
    echo ""
    echo -n "Action: "
    read -r conflict_choice

    case "$conflict_choice" in
        1)
            log_message "Sending SIGTERM to PID $holder_pid ($holder_name) holding port $port"
            if kill "$holder_pid" 2>/dev/null; then
                # Wait up to 5s for process to exit
                local wait_count=0
                while [ $wait_count -lt 5 ] && kill -0 "$holder_pid" 2>/dev/null; do
                    sleep 1
                    ((wait_count++))
                done
                if ! kill -0 "$holder_pid" 2>/dev/null; then
                    print_success "Process $holder_pid stopped, port $port freed"
                    return 0
                else
                    print_warning "Process did not stop after 5s"
                    if confirm_action "Force kill (SIGKILL)?"; then
                        kill -9 "$holder_pid" 2>/dev/null
                        sleep 1
                        if ! kill -0 "$holder_pid" 2>/dev/null; then
                            print_success "Process force-stopped"
                            return 0
                        fi
                        print_error "Could not stop process $holder_pid"
                        return 1
                    fi
                fi
            else
                print_error "Cannot stop process $holder_pid (permission denied?)"
                print_info "Try: sudo kill $holder_pid"
                return 1
            fi
            ;;
        2)
            log_message "Sending SIGKILL to PID $holder_pid ($holder_name) holding port $port"
            if kill -9 "$holder_pid" 2>/dev/null; then
                sleep 1
                if ! kill -0 "$holder_pid" 2>/dev/null; then
                    print_success "Process force-stopped, port $port freed"
                    return 0
                fi
            fi
            print_error "Could not stop process $holder_pid"
            return 1
            ;;
        *)
            print_info "Skipping port conflict resolution"
            return 1
            ;;
    esac
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

    # MeshChatX detection (pip console script: meshchatx, alias meshchat).
    # HAS_MESHCHAT name kept to avoid churn across menu/status readers.
    if command -v meshchatx &>/dev/null; then
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

    # MeshChatX has no Node.js dependency (bundled-frontend pip wheel), so the
    # old Node version warning is gone. MeshChatX needs Python 3.11+; the
    # installer (install_meshchatx) gates on that at install time.
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
        meshchat|meshchatx)
            # MeshChatX is a Python web daemon launched via the meshchatx
            # console script. -f is required because the running process is a
            # python interpreter, not an exec named meshchatx (web UI on
            # 127.0.0.1:8000). pgrep stays centralized here per RNS008.
            if pgrep -f "meshchatx" > /dev/null 2>&1; then
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
        # -k OK: base_url is hard-coded to https://127.0.0.1:<port> above;
        # localhost meshtasticd uses a self-signed cert by default.
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
        # -k OK: same loopback constraint as above (127.0.0.1).
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
