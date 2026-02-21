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

#########################################################
# Source Modules (dependency order)
#########################################################

# Core: terminal detection, colors, home resolution, globals
source "$SCRIPT_DIR/lib/core.sh"

# Utilities: timeout, retry, logging, caching, service checks
source "$SCRIPT_DIR/lib/utils.sh"

# UI: print functions, box drawing, menus, help
source "$SCRIPT_DIR/lib/ui.sh"

# Dialog: whiptail/dialog backend abstraction (meshforge DialogBackend pattern)
source "$SCRIPT_DIR/lib/dialog.sh"

# Installation: prerequisites, ecosystem, MeshChat, Sideband
source "$SCRIPT_DIR/lib/install.sh"

# RNODE: device configuration and management
source "$SCRIPT_DIR/lib/rnode.sh"

# Services: start/stop, meshtasticd, autostart
source "$SCRIPT_DIR/lib/services.sh"

# Backup: backup/restore, export/import
source "$SCRIPT_DIR/lib/backup.sh"

# Diagnostics: system checks with return-value pattern
source "$SCRIPT_DIR/lib/diagnostics.sh"

# Config: templates, editor, viewer, logs
source "$SCRIPT_DIR/lib/config.sh"

# Advanced: emergency mode, advanced menu, startup
source "$SCRIPT_DIR/lib/advanced.sh"

#########################################################
# Main Menu
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
    local tool_count
    tool_count=$(count_rns_tools)
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
# Main Entry Function
#########################################################

main() {
    # Initialize
    detect_environment
    detect_dialog_backend
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

# --check: Dry-run validation mode for CI
# Validates syntax, function definitions, and environment without launching TUI
if [ "${1:-}" = "--check" ]; then
    _check_pass=0
    _check_fail=0

    echo "RNS Management Tool v${SCRIPT_VERSION} — Validation Mode"
    echo ""

    # 1. Syntax (already passed if we got here)
    echo "[PASS] Bash syntax OK"
    ((_check_pass++))

    # 2. Core functions defined
    _required_funcs=(main show_main_menu detect_environment detect_available_tools
                     services_menu backup_restore_menu run_diagnostics
                     install_reticulum_ecosystem configure_rnode_interactive)
    for _fn in "${_required_funcs[@]}"; do
        if declare -F "$_fn" &>/dev/null; then
            ((_check_pass++))
        else
            echo "[FAIL] Missing function: $_fn"
            ((_check_fail++))
        fi
    done
    echo "[PASS] ${#_required_funcs[@]} core functions defined"

    # 3. Lib modules sourced (if modular)
    if [ -d "$SCRIPT_DIR/lib" ]; then
        _mod_count=0
        for _mod in "$SCRIPT_DIR"/lib/*.sh; do
            [ -f "$_mod" ] && ((_mod_count++))
        done
        echo "[PASS] $_mod_count lib modules loaded"
        ((_check_pass++))
    fi

    # 4. Environment detection (non-interactive)
    detect_environment 2>/dev/null
    echo "[PASS] Environment: OS=$OS_TYPE, Arch=$ARCHITECTURE, WSL=$IS_WSL"
    ((_check_pass++))

    # 5. Tool discovery
    detect_available_tools 2>/dev/null
    _tc=$(count_rns_tools)
    echo "[PASS] RNS tools: $_tc/8 available, python3=$HAS_PYTHON3, pip=$HAS_PIP"
    ((_check_pass++))

    # 6. Config file check
    if [ -f "$REAL_HOME/.reticulum/config" ]; then
        echo "[PASS] Reticulum config exists"
    else
        echo "[INFO] Reticulum config not found (first run expected)"
    fi

    echo ""
    echo "Validation passed: $_check_pass checks OK, $_check_fail failures"
    [ "$_check_fail" -gt 0 ] && exit 1
    exit 0
fi

# Run main program
main

exit 0
