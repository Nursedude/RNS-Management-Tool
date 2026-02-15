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
                    # Search current + rotated + legacy timestamped logs
                    grep -F --color=always "$SEARCH_TERM" \
                        "$UPDATE_LOG" "${UPDATE_LOG}".* \
                        "$REAL_HOME"/rns_management_*.log 2>/dev/null || \
                        print_warning "No matches found"
                fi
                pause_for_input
                ;;
            4)
                print_section "All Management Logs"
                echo -e "${BOLD}Log files:${NC}\n"
                local found_any=false
                # Show current + rotated logs
                for logfile in "$UPDATE_LOG" "${UPDATE_LOG}.1" "${UPDATE_LOG}.2" "${UPDATE_LOG}.3"; do
                    if [ -f "$logfile" ]; then
                        found_any=true
                        local sz
                        sz=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo "?")
                        echo "  $(basename "$logfile") (${sz} bytes)"
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
                        local sz
                        sz=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo "?")
                        echo "  $(basename "$logfile") (${sz} bytes)"
                    done <<< "$legacy_logs"
                fi
                if [ "$found_any" = false ]; then
                    print_warning "No log files found"
                fi
                echo ""
                print_info "Logs are in: $REAL_HOME/"
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
