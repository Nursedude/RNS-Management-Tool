# shellcheck shell=bash
# shellcheck disable=SC2034  # MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/backup.sh — Backup, restore, export, import
# Sourced by rns_management_tool.sh
#########################################################

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
