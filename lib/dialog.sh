#########################################################
# lib/dialog.sh — whiptail/dialog backend abstraction
# Sourced by rns_management_tool.sh (after ui.sh)
#
# Adapted from meshforge DialogBackend pattern:
#   7 dialog methods: msgbox, yesno, menu, inputbox,
#   infobox, gauge, checklist
#   Backend detection: whiptail > dialog > terminal fallback
#   Default dimensions: 78x22, 14-line list height
#########################################################

# Backend type: "whiptail", "dialog", or "terminal"
DIALOG_BACKEND="terminal"
DIALOG_WIDTH=78
DIALOG_HEIGHT=22
DIALOG_LIST_HEIGHT=14

# Detect best available dialog backend
# Priority: whiptail (lighter, standard on Debian) > dialog > terminal fallback
detect_dialog_backend() {
    if command -v whiptail &>/dev/null; then
        DIALOG_BACKEND="whiptail"
        log_message "Dialog backend: whiptail"
    elif command -v dialog &>/dev/null; then
        DIALOG_BACKEND="dialog"
        log_message "Dialog backend: dialog"
    else
        DIALOG_BACKEND="terminal"
        log_message "Dialog backend: terminal (no whiptail/dialog found)"
    fi
}

# Check if a graphical dialog backend is available
has_dialog_backend() {
    [[ "$DIALOG_BACKEND" == "whiptail" || "$DIALOG_BACKEND" == "dialog" ]]
}

# ─── msgbox ─────────────────────────────────────────────
# Display a message box with OK button
# Usage: dlg_msgbox "Title" "Message body"
dlg_msgbox() {
    local title="$1"
    local message="$2"

    case "$DIALOG_BACKEND" in
        whiptail)
            whiptail --title "$title" --msgbox "$message" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            ;;
        dialog)
            dialog --title "$title" --msgbox "$message" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            ;;
        terminal)
            print_section "$title"
            echo -e "$message"
            echo ""
            pause_for_input
            ;;
    esac
}

# ─── yesno ──────────────────────────────────────────────
# Ask a yes/no question
# Usage: dlg_yesno "Title" "Question text"
# Returns: 0 = yes, 1 = no
dlg_yesno() {
    local title="$1"
    local message="$2"

    case "$DIALOG_BACKEND" in
        whiptail)
            whiptail --title "$title" --yesno "$message" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            return $?
            ;;
        dialog)
            dialog --title "$title" --yesno "$message" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            return $?
            ;;
        terminal)
            confirm_action "$message"
            return $?
            ;;
    esac
}

# ─── menu ───────────────────────────────────────────────
# Display a menu and return the selected tag
# Usage: dlg_menu "Title" "Prompt" "tag1" "label1" "tag2" "label2" ...
# Output: selected tag on stdout, or empty string if cancelled
dlg_menu() {
    local title="$1"
    local prompt="$2"
    shift 2

    case "$DIALOG_BACKEND" in
        whiptail)
            local result
            result=$(whiptail --title "$title" --menu "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" \
                "$@" 3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        dialog)
            local result
            result=$(dialog --title "$title" --menu "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" \
                "$@" 3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        terminal)
            # Fallback: numbered list with read prompt
            print_section "$title"
            [ -n "$prompt" ] && echo -e "$prompt\n"

            local -a tags=()
            local -a labels=()
            local i=0
            while [ $# -gt 0 ]; do
                tags+=("$1")
                labels+=("$2")
                i=$((i + 1))
                echo "  $1) $2"
                shift 2
            done

            echo ""
            echo -n "Select option: "
            read -r choice
            echo "$choice"
            ;;
    esac
}

# ─── inputbox ───────────────────────────────────────────
# Prompt for text input
# Usage: dlg_inputbox "Title" "Prompt text" ["default_value"]
# Output: entered text on stdout
dlg_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    case "$DIALOG_BACKEND" in
        whiptail)
            local result
            result=$(whiptail --title "$title" --inputbox "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$default" \
                3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        dialog)
            local result
            result=$(dialog --title "$title" --inputbox "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$default" \
                3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        terminal)
            if [ -n "$default" ]; then
                echo -n "$prompt [$default]: "
            else
                echo -n "$prompt: "
            fi
            local input
            read -r input
            echo "${input:-$default}"
            ;;
    esac
}

# ─── infobox ────────────────────────────────────────────
# Display a brief message (no button, auto-dismiss with dialog)
# Usage: dlg_infobox "Title" "Brief message"
dlg_infobox() {
    local title="$1"
    local message="$2"

    case "$DIALOG_BACKEND" in
        whiptail)
            whiptail --title "$title" --infobox "$message" 8 "$DIALOG_WIDTH"
            ;;
        dialog)
            dialog --title "$title" --infobox "$message" 8 "$DIALOG_WIDTH"
            ;;
        terminal)
            print_info "$message"
            ;;
    esac
}

# ─── gauge ──────────────────────────────────────────────
# Display a progress gauge (reads percentage from stdin)
# Usage: echo 50 | dlg_gauge "Title" "Working..."
dlg_gauge() {
    local title="$1"
    local message="$2"

    case "$DIALOG_BACKEND" in
        whiptail)
            whiptail --title "$title" --gauge "$message" 8 "$DIALOG_WIDTH" 0
            ;;
        dialog)
            dialog --title "$title" --gauge "$message" 8 "$DIALOG_WIDTH" 0
            ;;
        terminal)
            # Terminal fallback: just show the message
            print_info "$message"
            # Consume stdin silently
            cat > /dev/null
            ;;
    esac
}

# ─── checklist ──────────────────────────────────────────
# Display a checklist (multiple selection)
# Usage: dlg_checklist "Title" "Prompt" "tag1" "label1" "ON" "tag2" "label2" "OFF" ...
# Output: space-separated selected tags on stdout
dlg_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2

    case "$DIALOG_BACKEND" in
        whiptail)
            local result
            result=$(whiptail --title "$title" --checklist "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" \
                "$@" 3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        dialog)
            local result
            result=$(dialog --title "$title" --checklist "$prompt" \
                "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" \
                "$@" 3>&1 1>&2 2>&3) || true
            echo "$result"
            ;;
        terminal)
            # Terminal fallback: show items and ask for comma-separated numbers
            print_section "$title"
            [ -n "$prompt" ] && echo -e "$prompt\n"

            local idx=0
            local -a tags=()
            while [ $# -gt 0 ]; do
                local tag="$1" label="$2" state="$3"
                tags+=("$tag")
                local marker="[ ]"
                [ "$state" = "ON" ] && marker="[*]"
                idx=$((idx + 1))
                echo "  $idx) $marker $label"
                shift 3
            done

            echo ""
            echo -n "Enter numbers (comma-separated) or blank to accept defaults: "
            local input
            read -r input

            if [ -z "$input" ]; then
                # Return defaults (ON items)
                local defaults=""
                local j=0
                for tag in "${tags[@]}"; do
                    # We can't easily re-read the states, so return all tags
                    defaults="$defaults $tag"
                    j=$((j + 1))
                done
                echo "$defaults"
            else
                local selected=""
                IFS=',' read -ra choices <<< "$input"
                for c in "${choices[@]}"; do
                    c=$(echo "$c" | tr -d ' ')
                    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#tags[@]}" ]; then
                        selected="$selected ${tags[$((c - 1))]}"
                    fi
                done
                echo "$selected"
            fi
            ;;
    esac
}
