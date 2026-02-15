# shellcheck shell=bash
#########################################################
# lib/ui.sh — UI/TUI functions, box drawing, menus
# Sourced by rns_management_tool.sh
#########################################################

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
