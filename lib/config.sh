# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/config.sh — Configuration templates, editor, viewer, logs
# Sourced by rns_management_tool.sh
#########################################################

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
    if ! read -r -t 300 TMPL_CHOICE; then
        echo ""
        print_warning "No selection within 5 minutes — cancelling"
        return 1
    fi

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
            if ! read -r -t 300 VIEW_CHOICE; then
                echo ""
                print_warning "No selection within 5 minutes — cancelling"
                return 1
            fi
            case $VIEW_CHOICE in
                1) template_file="$template_dir/minimal.conf" ;;
                2) template_file="$template_dir/lora_rnode.conf" ;;
                3) template_file="$template_dir/tcp_client.conf" ;;
                4) template_file="$template_dir/transport_node.conf" ;;
                *) print_error "Invalid choice"; return 1 ;;
            esac
            if [ -f "$template_file" ]; then
                echo ""
                local display_lines=$(($(tput lines 2>/dev/null || echo 40) - 5))
                [ "$display_lines" -lt 20 ] && display_lines=20
                head -n "$display_lines" "$template_file"
                local total_lines
                total_lines=$(wc -l < "$template_file")
                if [ "$total_lines" -gt "$display_lines" ]; then
                    echo ""
                    print_info "Showing first $display_lines of $total_lines lines"
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
# Deployment Profiles
#########################################################

# Deployment profiles go beyond config templates — they apply a template AND
# configure service settings (autostart, transport mode) for a specific role.
apply_deployment_profile() {
    print_section "Deployment Profiles"

    echo -e "${BOLD}Deployment profiles configure your system for a specific role:${NC}\n"
    echo "   1) Relay Node"
    echo "      Stationary, always-on transport node. Routes traffic for the network."
    echo "      Config: Transport enabled, autostart at boot"
    echo ""
    echo "   2) Mobile Station"
    echo "      Portable device with LoRa radio. Manual start for field operations."
    echo "      Config: LoRa RNODE, no transport, no autostart"
    echo ""
    echo "   3) Base Station"
    echo "      Stationary LoRa gateway bridging radio and internet."
    echo "      Config: Transport + LoRa + TCP, autostart at boot"
    echo ""
    echo "   0) Cancel"
    echo ""
    echo -n "Select profile: "
    if ! read -r -t 300 PROFILE_CHOICE; then
        echo ""
        print_warning "No selection within 5 minutes — cancelling"
        return 1
    fi

    local profile_name="" template_file="" enable_autostart=false
    local template_dir="$SCRIPT_DIR/config_templates"

    case $PROFILE_CHOICE in
        1) profile_name="Relay Node"
           template_file="$template_dir/transport_node.conf"
           enable_autostart=true
           ;;
        2) profile_name="Mobile Station"
           template_file="$template_dir/lora_rnode.conf"
           enable_autostart=false
           ;;
        3) profile_name="Base Station"
           template_file="$template_dir/transport_node.conf"
           enable_autostart=true
           ;;
        0|"") return 0 ;;
        *) print_error "Invalid option"; return 1 ;;
    esac

    if [ ! -f "$template_file" ]; then
        print_error "Template file not found: $template_file"
        return 1
    fi

    echo ""
    echo -e "${BOLD}Profile: $profile_name${NC}"
    echo "  Config template: $(basename "$template_file")"
    echo "  Autostart: $([ "$enable_autostart" = true ] && echo "Yes" || echo "No")"
    echo ""

    echo -e "${YELLOW}WARNING: This will replace your current Reticulum config.${NC}"
    echo -e "${GREEN}Your existing config will be backed up first.${NC}"
    echo ""

    if ! confirm_action "Apply '$profile_name' deployment profile?"; then
        print_info "Cancelled — no changes made"
        return 0
    fi

    # Step 1: Backup current config
    local config_dir="$REAL_HOME/.reticulum"
    local config_file="$config_dir/config"
    if [ -f "$config_file" ]; then
        local backup_name
        backup_name="config.backup.$(date +%Y%m%d_%H%M%S)"
        local backup_path="$config_dir/$backup_name"
        if ! cp "$config_file" "$backup_path"; then
            print_error "Backup failed — aborting (your config is unchanged)"
            return 1
        fi
        print_success "Backed up current config to: ~/.reticulum/$backup_name"
        log_message "Deployment profile backup: $backup_path"
    fi

    # Step 2: Apply template
    mkdir -p "$config_dir"
    if ! cp "$template_file" "$config_file"; then
        print_error "Failed to apply template"
        return 1
    fi
    print_success "Applied $(basename "$template_file") template"

    # Step 3: Configure autostart
    if [ "$enable_autostart" = true ]; then
        if has_command systemctl; then
            setup_autostart
        fi
    else
        if has_command systemctl && \
           systemctl --user is-enabled rnsd.service &>/dev/null 2>&1; then
            disable_autostart
        fi
    fi

    log_message "Applied deployment profile: $profile_name (template: $(basename "$template_file"), autostart: $enable_autostart)"
    print_success "Deployment profile '$profile_name' applied"
    echo ""
    print_info "Review your config before starting rnsd:"
    echo -e "  ${CYAN}nano ~/.reticulum/config${NC}"

    if [ "$enable_autostart" = true ]; then
        echo ""
        if confirm_action "Start rnsd now?" "y"; then
            start_services
        fi
    fi

    invalidate_status_cache
}

#########################################################
# Configuration Editor
#########################################################

# Edit a config file with the user's preferred editor
# Creates backup before editing (MeshForge safety principle)
edit_config_file() {
    print_section "Edit Configuration"

    # Select available editor: prefer $EDITOR, then $VISUAL, then nano, then vi
    local editor=""
    for candidate in "${EDITOR:-}" "${VISUAL:-}" nano vi; do
        [ -n "$candidate" ] && command -v "$candidate" &>/dev/null && editor="$candidate" && break
    done
    if [ -z "$editor" ]; then
        print_error "No text editor found (tried \$EDITOR, nano, vi)"
        return 1
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
    if ! read -r -t 300 EDIT_CHOICE; then
        echo ""
        print_warning "No selection within 5 minutes — cancelling"
        return 1
    fi

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

    # Advisory: editing config while rnsd runs may need a restart
    # (meshforge service pre-flight advisory pattern)
    advise_service "rnsd" "stopped" "rnsd is running. Config changes take effect on restart." || return

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
    if ! read -r -t 300 CONFIG_CHOICE; then
        echo ""
        print_warning "No selection within 5 minutes — cancelling"
        return 1
    fi

    case $CONFIG_CHOICE in
        1)
            if [ -f "$REAL_HOME/.reticulum/config" ]; then
                echo -e "${CYAN}File: ~/.reticulum/config${NC}\n"
                show_paged_output "Reticulum Configuration" < "$REAL_HOME/.reticulum/config"
            fi
            ;;
        2)
            if [ -f "$REAL_HOME/.nomadnetwork/config" ]; then
                echo -e "${CYAN}File: ~/.nomadnetwork/config${NC}\n"
                show_paged_output "NomadNet Configuration" < "$REAL_HOME/.nomadnetwork/config"
            fi
            ;;
        3)
            if [ -f "$REAL_HOME/.lxmf/config" ]; then
                echo -e "${CYAN}File: ~/.lxmf/config${NC}\n"
                show_paged_output "LXMF Configuration" < "$REAL_HOME/.lxmf/config"
            fi
            ;;
        0|"")
            return
            ;;
    esac
}

# Log-viewer helpers — each renders one log source. The dispatcher
# (view_logs_menu) is intentionally thin so the file stays under the 200-line
# function-size guideline in CLAUDE.md and each log source can be unit-tested
# in isolation. Helpers use the _logs_ prefix to signal "private to this file".
#
# Convention: helpers print their output but never call pause_for_input —
# the dispatcher owns that so behavior is uniform across all menu options.

_logs_show_rnsd() {
    print_section "rnsd Daemon Logs"
    if has_command journalctl; then
        print_info "Showing recent rnsd-related log entries..."
        echo ""
        journalctl --user -u rnsd --no-pager -n 50 2>/dev/null || \
            journalctl -t rnsd --no-pager -n 50 2>/dev/null || \
            print_warning "No systemd logs found for rnsd"
    else
        print_warning "journalctl not available"
        print_info "Try: ps aux | grep rnsd"
    fi
}

# meshtasticd logs (meshforge 259f22e — expanded log viewer)
_logs_show_meshtasticd() {
    print_section "meshtasticd Logs"
    if ! has_command meshtasticd; then
        print_info "meshtasticd is not installed"
    elif has_command journalctl; then
        print_info "Showing recent meshtasticd log entries..."
        echo ""
        sudo journalctl -u meshtasticd --no-pager -n 50 2>/dev/null || \
            print_warning "No systemd logs found for meshtasticd"
    else
        print_warning "journalctl not available"
    fi
}

_logs_show_reticulum_journal() {
    print_section "Reticulum Journal Entries"
    if has_command journalctl; then
        print_info "Showing recent Reticulum-related journal entries..."
        echo ""
        # Search for rnsd, rns, lxmf across both user and system journals
        {
            journalctl --user -u rnsd --no-pager -n 20 2>/dev/null
            journalctl --user --grep="reticulum\|lxmf\|nomadnet\|meshchat\|sideband" --no-pager -n 20 2>/dev/null
        } | sort -u | tail -n 50 || print_warning "No Reticulum journal entries found"
    else
        print_warning "journalctl not available"
    fi
}

_logs_show_management() {
    print_section "Management Tool Log"
    if [ -f "$UPDATE_LOG" ]; then
        echo -e "${CYAN}File: $UPDATE_LOG${NC}\n"
        tail -n 100 "$UPDATE_LOG" | show_paged_output "Recent Log Entries"
    else
        # Find most recent log
        local latest_log
        latest_log=$(find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | sort -r | head -1)
        if [ -n "$latest_log" ]; then
            echo -e "${CYAN}File: $latest_log${NC}\n"
            tail -n 100 "$latest_log" | show_paged_output "Recent Log Entries"
        else
            print_warning "No log files found"
        fi
    fi
}

_logs_show_meshchat_build() {
    print_section "MeshChat Build Log"
    local meshchat_build_log="${REAL_HOME}/meshchat_build.log"
    if [ -f "$meshchat_build_log" ]; then
        echo -e "${CYAN}File: $meshchat_build_log${NC}"
        echo -e "${YELLOW}This log is from a failed build — it is removed on success.${NC}\n"
        tail -n 80 "$meshchat_build_log" | show_paged_output "MeshChat Build Output"
    else
        print_info "No MeshChat build log found"
        print_info "This file only exists after a failed build (removed on success)"
        # Check management log for MeshChat-related entries
        if [ -f "$UPDATE_LOG" ]; then
            echo ""
            print_info "MeshChat entries from management log:"
            echo ""
            grep -i "meshchat\|npm\|node\|build" "$UPDATE_LOG" 2>/dev/null | tail -n 20 || \
                print_info "No MeshChat entries found in management log"
        fi
    fi
}

_logs_show_nomadnet() {
    print_section "NomadNet Log"
    local nomadnet_log="$REAL_HOME/.nomadnetwork/logfile"
    if [ -f "$nomadnet_log" ]; then
        echo -e "${CYAN}File: $nomadnet_log${NC}\n"
        tail -n 80 "$nomadnet_log" | show_paged_output "NomadNet Log"
    else
        print_info "No NomadNet log found at $nomadnet_log"
        print_info "NomadNet may not have been run yet"
    fi
}

_logs_show_sideband() {
    print_section "Sideband Log"
    local sideband_log="$REAL_HOME/.sideband/logfile"
    if [ -f "$sideband_log" ]; then
        echo -e "${CYAN}File: $sideband_log${NC}\n"
        tail -n 80 "$sideband_log" | show_paged_output "Sideband Log"
    else
        print_info "No Sideband log found at $sideband_log"
        # Try alternate locations
        local alt_log
        alt_log=$(find "$REAL_HOME/.config/sideband" "$REAL_HOME/.sideband" -name "*.log" -type f 2>/dev/null | head -1)
        if [ -n "$alt_log" ]; then
            echo -e "${CYAN}Found log at: $alt_log${NC}\n"
            tail -n 80 "$alt_log" | show_paged_output "Sideband Log"
        else
            print_info "Sideband may not have been run yet"
        fi
    fi
}

_logs_search() {
    print_section "Search Logs"
    echo -n "Enter search term: "
    # 5-min timeout (matches the rest of the lib/ TUI prompts post-PR-#78)
    if ! read -r -t 300 SEARCH_TERM; then
        echo ""
        print_warning "No search term within 5 minutes — cancelling"
        return 1
    fi
    if [ -n "$SEARCH_TERM" ]; then
        print_info "Searching for '$SEARCH_TERM' in log files..."
        echo ""
        # Search management logs + app logs
        {
            grep -F --color=always "$SEARCH_TERM" \
                "$UPDATE_LOG" "${UPDATE_LOG}".* \
                "$REAL_HOME"/rns_management_*.log \
                "$REAL_HOME/meshchat_build.log" \
                "$REAL_HOME/.nomadnetwork/logfile" \
                "$REAL_HOME/.sideband/logfile" 2>/dev/null
        } || print_warning "No matches found"
    fi
}

# Enhanced log listing with line counts (meshforge 259f22e pattern)
_logs_list_all() {
    print_section "All Log Files"
    echo -e "${BOLD}Management logs:${NC}\n"
    local found_any=false
    # Show current + rotated logs with sizes and line counts
    for logfile in "$UPDATE_LOG" "${UPDATE_LOG}.1" "${UPDATE_LOG}.2" "${UPDATE_LOG}.3"; do
        if [ -f "$logfile" ]; then
            found_any=true
            local sz lc mod_time
            sz=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo "?")
            lc=$(wc -l < "$logfile" 2>/dev/null || echo "?")
            mod_time=$(stat -c%y "$logfile" 2>/dev/null | cut -d. -f1 || echo "?")
            echo "  $(basename "$logfile") (${sz} bytes, ${lc} lines, modified: ${mod_time})"
        fi
    done
    # Show any legacy timestamped logs
    local legacy_logs
    legacy_logs=$(find "$REAL_HOME" -maxdepth 1 -name "rns_management_*.log" -type f 2>/dev/null | sort -r)
    if [ -n "$legacy_logs" ]; then
        found_any=true
        echo ""
        echo -e "  ${YELLOW}Legacy timestamped logs:${NC}"
        while IFS= read -r logfile; do
            [ -z "$logfile" ] && continue
            local sz lc
            sz=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo "?")
            lc=$(wc -l < "$logfile" 2>/dev/null || echo "?")
            echo "  $(basename "$logfile") (${sz} bytes, ${lc} lines)"
        done <<< "$legacy_logs"
    fi
    if [ "$found_any" = false ]; then
        print_warning "No management logs found"
    fi

    # Application logs
    echo ""
    echo -e "${BOLD}Application logs:${NC}\n"
    local app_found=false
    for app_log in "$REAL_HOME/meshchat_build.log" "$REAL_HOME/.nomadnetwork/logfile" "$REAL_HOME/.sideband/logfile"; do
        if [ -f "$app_log" ]; then
            app_found=true
            local sz lc mod_time
            sz=$(stat -c%s "$app_log" 2>/dev/null || stat -f%z "$app_log" 2>/dev/null || echo "?")
            lc=$(wc -l < "$app_log" 2>/dev/null || echo "?")
            mod_time=$(stat -c%y "$app_log" 2>/dev/null | cut -d. -f1 || echo "?")
            echo "  $(basename "$app_log") (${sz} bytes, ${lc} lines, modified: ${mod_time})"
        fi
    done
    if [ "$app_found" = false ]; then
        print_info "No application logs found"
    fi

    echo ""
    print_info "Logs directory: $REAL_HOME/"
}

view_logs_menu() {
    while true; do
        print_header
        MENU_BREADCRUMB="Main Menu > Logs"
        print_breadcrumb

        echo -e "${BOLD}Log Viewer:${NC}\n"
        echo -e "  ${CYAN}─── System Journal ───${NC}"
        echo "   1) View rnsd daemon logs (systemd)"
        echo "   2) View meshtasticd logs (systemd)"
        echo "   3) View all Reticulum journal entries"
        echo ""
        echo -e "  ${CYAN}─── Application Logs ───${NC}"
        echo "   4) View management tool log"
        echo "   5) View MeshChat build log"
        echo "   6) View NomadNet log"
        echo "   7) View Sideband log"
        echo ""
        echo -e "  ${CYAN}─── Search & List ───${NC}"
        echo "   8) Search logs for keyword"
        echo "   9) List all log files"
        echo ""
        echo "   0) Back"
        echo ""
        echo -n "Select option: "
        read_menu_choice LOG_CHOICE

        case $LOG_CHOICE in
            1) _logs_show_rnsd; pause_for_input ;;
            2) _logs_show_meshtasticd; pause_for_input ;;
            3) _logs_show_reticulum_journal; pause_for_input ;;
            4) _logs_show_management; pause_for_input ;;
            5) _logs_show_meshchat_build; pause_for_input ;;
            6) _logs_show_nomadnet; pause_for_input ;;
            7) _logs_show_sideband; pause_for_input ;;
            8) _logs_search; pause_for_input ;;
            9) _logs_list_all; pause_for_input ;;
            0|"") return ;;
            *) print_error "Invalid option" ;;
        esac
    done
}
