#!/bin/bash
#########################################################
# Post-Install Verification Script
# Validates that the Reticulum ecosystem is correctly installed
# Adapted from meshforge verify_post_install.sh pattern
#
# Usage:
#   ./scripts/verify_install.sh            # Colored output
#   ./scripts/verify_install.sh --quiet    # Exit code only
#   ./scripts/verify_install.sh --json     # JSON output
#
# Exit codes: 0 = pass, 1 = critical failure, 2 = warnings only
#########################################################

set -o pipefail

# Color setup
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

MODE="default"
[ "${1:-}" = "--quiet" ] && MODE="quiet"
[ "${1:-}" = "--json" ] && MODE="json"

PASS=0
WARN=0
FAIL=0
RESULTS=()

check_pass() {
    ((PASS++))
    RESULTS+=("{\"check\":\"$1\",\"status\":\"pass\"}")
    [ "$MODE" = "default" ] && echo -e "  ${GREEN}[PASS]${NC} $1"
}

check_warn() {
    ((WARN++))
    RESULTS+=("{\"check\":\"$1\",\"status\":\"warn\",\"detail\":\"$2\"}")
    [ "$MODE" = "default" ] && echo -e "  ${YELLOW}[WARN]${NC} $1 — $2"
}

check_fail() {
    ((FAIL++))
    RESULTS+=("{\"check\":\"$1\",\"status\":\"fail\",\"detail\":\"$2\"}")
    [ "$MODE" = "default" ] && echo -e "  ${RED}[FAIL]${NC} $1 — $2"
}

section() {
    [ "$MODE" = "default" ] && echo -e "\n${CYAN}$1${NC}"
}

# Resolve home directory (same logic as lib/core.sh)
REAL_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && \
   [[ "$SUDO_USER" != */* ]] && [[ "$SUDO_USER" != *..* ]]; then
    local_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    [ -n "$local_home" ] && [ -d "$local_home" ] && REAL_HOME="$local_home"
fi

[ "$MODE" = "default" ] && echo -e "${CYAN}RNS Management Tool — Post-Install Verification${NC}"
[ "$MODE" = "default" ] && echo "================================================="

#########################################################
# [1/6] Python & pip
#########################################################
section "[1/6] Python & pip"

if command -v python3 &>/dev/null; then
    pyver=$(python3 --version 2>&1 | awk '{print $2}')
    pymajor="${pyver%%.*}"
    pyminor="${pyver#*.}"; pyminor="${pyminor%%.*}"
    if [ "$pymajor" -ge 3 ] && [ "$pyminor" -ge 7 ] 2>/dev/null; then
        check_pass "Python $pyver (3.7+ required)"
    else
        check_fail "Python $pyver" "requires 3.7+"
    fi
else
    check_fail "Python 3" "not installed (sudo apt install python3)"
fi

if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
    check_pass "pip available"
else
    check_warn "pip" "not found — may be needed for package management"
fi

#########################################################
# [2/6] RNS ecosystem packages
#########################################################
section "[2/6] RNS Ecosystem Packages"

for pkg in rns lxmf nomadnet; do
    ver=$(pip3 show "$pkg" 2>/dev/null | grep -i '^Version:' | awk '{print $2}')
    if [ -n "$ver" ]; then
        check_pass "$pkg v$ver installed"
    else
        if [ "$pkg" = "rns" ]; then
            check_fail "$pkg" "not installed (run option 1 from main menu)"
        else
            check_warn "$pkg" "not installed (optional)"
        fi
    fi
done

#########################################################
# [3/6] Configuration files
#########################################################
section "[3/6] Configuration"

if [ -f "$REAL_HOME/.reticulum/config" ]; then
    check_pass "Reticulum config exists (~/.reticulum/config)"
else
    check_warn "Reticulum config" "not found — will be created on first rnsd start"
fi

if [ -d "$REAL_HOME/.reticulum" ]; then
    config_size=$(du -sh "$REAL_HOME/.reticulum" 2>/dev/null | cut -f1)
    check_pass "Config directory: $config_size"
fi

#########################################################
# [4/6] Service readiness
#########################################################
section "[4/6] Services"

for tool in rnsd rnstatus rnpath rnprobe rncp rnx rnid rnodeconf; do
    if command -v "$tool" &>/dev/null; then
        check_pass "$tool available"
    else
        if [ "$tool" = "rnsd" ] || [ "$tool" = "rnstatus" ]; then
            check_fail "$tool" "not found — install RNS first"
        else
            check_warn "$tool" "not available"
        fi
    fi
done

# Check if rnsd is running
if pgrep -x "rnsd" >/dev/null 2>&1; then
    pid=$(pgrep -x "rnsd" | head -1)
    uptime_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$uptime_s" ] && [ "$uptime_s" -gt 0 ]; then
        check_pass "rnsd running (PID $pid, up ${uptime_s}s)"
    else
        check_pass "rnsd running (PID $pid)"
    fi
elif command -v systemctl &>/dev/null && systemctl --user is-active rnsd.service &>/dev/null 2>&1; then
    check_pass "rnsd running (systemd user service)"
else
    check_warn "rnsd" "not running — start with: rnsd --daemon"
fi

#########################################################
# [5/6] RNODE tools
#########################################################
section "[5/6] RNODE Hardware"

if command -v rnodeconf &>/dev/null; then
    check_pass "rnodeconf available"

    # Check for USB serial devices
    devices=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null)
    if [ -n "$devices" ]; then
        dev_count=$(echo "$devices" | wc -l)
        check_pass "$dev_count USB serial device(s) detected"
    else
        check_warn "USB devices" "none detected — connect RNODE device"
    fi

    # Check dialout group membership
    if id -nG 2>/dev/null | grep -qw dialout; then
        check_pass "User in dialout group"
    else
        check_warn "dialout group" "user not in dialout — run: sudo usermod -aG dialout \$USER"
    fi
else
    check_warn "rnodeconf" "not installed — needed for RNODE devices"
fi

#########################################################
# [6/6] Optional components
#########################################################
section "[6/6] Optional Components"

# MeshChatX (pip wheel: reticulum-meshchatx, console script meshchatx)
if command -v meshchatx &>/dev/null || pip3 show reticulum-meshchatx &>/dev/null 2>&1; then
    check_pass "MeshChatX installed"
else
    check_warn "MeshChatX" "not installed (optional — menu option 4)"
fi

# Sideband
if pip3 show sbapp &>/dev/null 2>&1 || [ -d "$REAL_HOME/Sideband" ]; then
    check_pass "Sideband installed"
else
    check_warn "Sideband" "not installed (optional — menu option 5)"
fi

# Node.js (for MeshChat)
if command -v node &>/dev/null; then
    nodever=$(node --version 2>/dev/null)
    check_pass "Node.js $nodever"
else
    check_warn "Node.js" "not installed (needed for MeshChat)"
fi

#########################################################
# Summary
#########################################################

if [ "$MODE" = "json" ]; then
    echo "{"
    echo "  \"pass\": $PASS,"
    echo "  \"warn\": $WARN,"
    echo "  \"fail\": $FAIL,"
    echo "  \"checks\": [$(IFS=,; echo "${RESULTS[*]}")]"
    echo "}"
elif [ "$MODE" = "default" ]; then
    echo ""
    echo "================================================="
    echo -e "Results: ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failed${NC}"
    echo ""
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
elif [ "$WARN" -gt 0 ]; then
    exit 2
else
    exit 0
fi
