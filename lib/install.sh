# shellcheck shell=bash
# shellcheck disable=SC2034  # NEEDS_REBOOT, MENU_BREADCRUMB used by other sourced modules
#########################################################
# lib/install.sh — Prerequisites, ecosystem, MeshChatX, Sideband
# Sourced by rns_management_tool.sh
#########################################################

#########################################################
# System Detection and Prerequisites
#########################################################

# Disk space pre-check (adapted from meshforge diagnostics)
# Returns 0 if sufficient, 1 if low, 2 if critical
check_disk_space() {
    local min_mb="${1:-500}"  # Default: 500MB minimum
    local target_path="${2:-$REAL_HOME}"

    if ! has_command df; then
        log_warn "df command not available, skipping disk check"
        return 0
    fi

    local available_mb
    available_mb=$(df -m "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available_mb" ]; then
        log_warn "Could not determine disk space for $target_path"
        return 0
    fi

    log_debug "Disk space available: ${available_mb}MB at $target_path (minimum: ${min_mb}MB)"

    if [ "$available_mb" -lt 100 ]; then
        print_error "Critical: Only ${available_mb}MB disk space available (need ${min_mb}MB)"
        log_error "Critical disk space: ${available_mb}MB at $target_path"
        return 2
    elif [ "$available_mb" -lt "$min_mb" ]; then
        print_warning "Low disk space: ${available_mb}MB available (recommend ${min_mb}MB)"
        log_warn "Low disk space: ${available_mb}MB at $target_path"
        return 1
    fi

    return 0
}

# Memory pre-check (adapted from meshforge system.py check_memory)
check_available_memory() {
    if [ ! -f /proc/meminfo ]; then
        log_debug "No /proc/meminfo, skipping memory check"
        return 0
    fi

    local total_kb available_kb percent_free
    total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)

    if [ -z "$total_kb" ] || [ -z "$available_kb" ] || [ "$total_kb" -eq 0 ]; then
        log_warn "Could not parse memory info"
        return 0
    fi

    local total_mb=$((total_kb / 1024))
    local available_mb=$((available_kb / 1024))
    percent_free=$((available_kb * 100 / total_kb))

    log_debug "Memory: ${available_mb}MB free of ${total_mb}MB (${percent_free}%)"

    if [ "$percent_free" -lt 10 ]; then
        print_warning "Low memory: ${available_mb}MB free (${percent_free}%)"
        print_info "Hint: Free up memory or add swap space"
        log_warn "Low memory: ${available_mb}MB free (${percent_free}%)"
        return 1
    fi

    return 0
}

# Git safe.directory guard (adapted from meshforge install.sh)
# Prevents "dubious ownership" errors when running as root
ensure_git_safe_directory() {
    local dir="$1"
    if [ -d "$dir/.git" ] && [ "$(id -u)" -eq 0 ]; then
        git config --global --add safe.directory "$dir" 2>/dev/null || true
        log_debug "Added git safe.directory: $dir"
    fi
}

check_python() {
    print_section "Checking Python Installation"

    if has_command python3; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [ "$PYTHON_MAJOR" -ge 3 ] && [ "$PYTHON_MINOR" -ge 7 ]; then
            print_success "Python $PYTHON_VERSION detected"
            log_message "Python version: $PYTHON_VERSION"
            return 0
        else
            print_error "Python $PYTHON_VERSION is too old (requires 3.7+)"
            return 1
        fi
    else
        print_error "Python3 not found"
        return 1
    fi
}

check_pip() {
    print_section "Checking pip Installation"

    if has_command pip3 || has_command pip; then
        if has_command pip3; then
            PIP_CMD="pip3"
        else
            PIP_CMD="pip"
        fi
        PIP_VERSION=$($PIP_CMD --version 2>&1 | awk '{print $2}')
        print_success "pip $PIP_VERSION detected"
        log_message "pip version: $PIP_VERSION"
        return 0
    else
        print_error "pip not found"
        return 1
    fi
}

install_prerequisites() {
    print_section "Installing Prerequisites"

    local packages=("python3" "python3-pip" "git" "curl" "wget" "build-essential")

    if [ "$IS_RASPBERRY_PI" = true ]; then
        packages+=("python3-dev" "libffi-dev" "libssl-dev")
    fi

    echo -e "${YELLOW}The following packages will be installed:${NC}"
    printf '  - %s\n' "${packages[@]}"
    echo ""
    if ! confirm_action "Proceed with installation?" "y"; then
        print_warning "Skipping prerequisites installation"
        return 1
    fi

    print_info "Updating package lists..."
    if retry_with_backoff 3 run_with_timeout "$APT_TIMEOUT" sudo apt update 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Package lists updated"

        print_info "Installing prerequisites..."
        if retry_with_backoff 2 run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Prerequisites installed successfully"
            log_message "Prerequisites installed: ${packages[*]}"
            return 0
        else
            print_error "Failed to install some prerequisites"
            return 1
        fi
    else
        print_error "Failed to update package lists (timeout after ${APT_TIMEOUT}s)"
        return 1
    fi
}

#########################################################
# RNODE Installation and Configuration
#########################################################

install_rnode_tools() {
    print_section "Installing RNODE Tools"

    echo -e "${CYAN}${BOLD}RNODE Installation Guide${NC}\n"
    echo "This will install the RNode configuration utility (rnodeconf)"
    echo "which allows you to:"
    echo "  • Flash RNode firmware to supported devices"
    echo "  • Configure radio parameters"
    echo "  • Test and diagnose RNODE devices"
    echo ""

    # rnodeconf is part of the rns package
    print_info "Installing/Updating RNS (includes rnodeconf)..."

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "RNS and rnodeconf installed successfully"

        # Verify rnodeconf is available
        if has_command rnodeconf; then
            RNODECONF_VERSION=$(rnodeconf --version 2>&1 | head -1 || echo "unknown")
            print_success "rnodeconf is ready: $RNODECONF_VERSION"
            log_message "rnodeconf installed: $RNODECONF_VERSION"
            return 0
        else
            print_warning "rnodeconf installed but not in PATH"
            print_info "You may need to restart your shell or run: hash -r"
            return 0
        fi
    else
        print_error "Failed to install RNS/rnodeconf"
        log_message "RNS installation failed"
        return 1
    fi
}

# NOTE: RNODE device configuration functions (rnode_get_device_port, rnode_autoinstall,
# rnode_configure_radio, configure_rnode_interactive, etc.) live in lib/rnode.sh.
# install_rnode_tools() above handles only the pip installation of rnodeconf.

#########################################################
# Component Installation Functions
#########################################################

declare -A _VERSION_CACHE=()
get_installed_version() {
    local package=$1
    if [ -z "${_VERSION_CACHE[$package]+x}" ]; then
        local pip="${PIP_CMD:-pip3}"
        _VERSION_CACHE[$package]=$("$pip" show "$package" 2>/dev/null | grep "^Version:" | awk '{print $2}')
    fi
    echo "${_VERSION_CACHE[$package]}"
}

update_pip_package() {
    local package=$1
    local display_name=$2

    print_section "Installing/Updating $display_name"

    OLD_VERSION=$(get_installed_version "$package")

    if [ -z "$OLD_VERSION" ]; then
        print_info "Installing $display_name..."
        log_message "Installing $display_name"
    else
        print_info "Current version: $OLD_VERSION"
        print_info "Checking for updates..."
        log_message "Updating $display_name from $OLD_VERSION"
    fi

    # Try update with --break-system-packages flag (needed on newer systems) - with retry
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install "$package" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        NEW_VERSION=$(get_installed_version "$package")

        if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
            print_success "$display_name updated: $OLD_VERSION → $NEW_VERSION"
            log_message "$display_name updated to $NEW_VERSION"
        else
            print_success "$display_name is up to date: $NEW_VERSION"
            log_message "$display_name already latest: $NEW_VERSION"
        fi
        return 0
    else
        print_error "Failed to install/update $display_name"
        log_message "Failed to update $display_name"

        # Offer troubleshooting
        echo -e "\n${YELLOW}Troubleshooting options:${NC}"
        echo "  1) Check internet connection"
        echo "  2) Try updating pip: pip3 install --upgrade pip"
        echo "  3) Check system requirements"

        return 1
    fi
}

install_reticulum_ecosystem() {
    print_section "Installing Reticulum Ecosystem"

    echo -e "${CYAN}This will install/update the complete Reticulum stack:${NC}"
    echo "  • RNS (Reticulum Network Stack) - Core networking"
    echo "  • LXMF - Messaging protocol layer"
    echo "  • NomadNet - Terminal messaging client (optional)"
    echo ""

    # Ask about NomadNet upfront so progress steps are accurate
    local install_nomad=false
    if confirm_action "Include NomadNet (terminal client)?" "y"; then
        install_nomad=true
    fi

    # Step-based progress display (adapted from meshforge pattern)
    if [ "$install_nomad" = true ]; then
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation" \
            "Install/update NomadNet" \
            "Verify NomadNet installation"
    else
        init_operation "Installing Reticulum Ecosystem" \
            "Install/update RNS (core)" \
            "Verify RNS installation" \
            "Install/update LXMF" \
            "Verify LXMF installation"
    fi

    local success=true

    # RNS first (core dependency) - with retry and spinner
    if retry_with_backoff 3 run_with_spinner "Installing RNS..." run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install rns --upgrade --break-system-packages; then
        next_step "success"
        # Verify RNS installation (meshforge post-install verify pattern)
        if python3 -c "import RNS; print(f'RNS {RNS.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "RNS installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # LXMF (depends on RNS) - with retry and spinner
    if retry_with_backoff 3 run_with_spinner "Installing LXMF..." run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install lxmf --upgrade --break-system-packages; then
        next_step "success"
        # Verify LXMF installation
        if python3 -c "import LXMF; print(f'LXMF {LXMF.__version__}')" 2>/dev/null; then
            next_step "success"
        else
            next_step "fail"
            print_warning "LXMF installed but import verification failed"
            success=false
        fi
    else
        next_step "fail"
        next_step "skip"
        success=false
    fi

    # NomadNet (optional)
    if [ "$install_nomad" = true ]; then
        if retry_with_backoff 3 run_with_spinner "Installing NomadNet..." run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install nomadnet --upgrade --break-system-packages; then
            next_step "success"
            if python3 -c "import nomadnet" 2>/dev/null; then
                next_step "success"
            else
                next_step "fail"
                print_warning "NomadNet installed but import verification failed"
            fi
        else
            next_step "fail"
            next_step "skip"
            success=false
        fi
    fi

    # Invalidate version cache so dashboard refreshes
    invalidate_status_cache

    if [ "$success" = true ]; then
        complete_operation "success"
        return 0
    else
        complete_operation "fail"
        show_error_help "pip" ""
        return 1
    fi
}

check_meshchatx_installed() {
    MESHCHATX_VERSION=$(get_installed_version "$MESHCHATX_PKG")
    MESHCHAT_VERSION="$MESHCHATX_VERSION"   # back-compat for older callers
    if [ -n "$MESHCHATX_VERSION" ]; then
        print_info "MeshChatX: v$MESHCHATX_VERSION (installed)"
        log_message "MeshChatX installed: $MESHCHATX_VERSION"
        return 0
    else
        print_warning "MeshChatX: not installed"
        log_message "MeshChatX not installed"
        return 1
    fi
}

# Back-compat alias — older code/tests may still call check_meshchat_installed.
check_meshchat_installed() { check_meshchatx_installed "$@"; }

# cleanup_partial_install — remove a half-installed component directory after a
# failed FIRST-time install so the operator can retry from a clean slate.
# On UPDATE failure we leave the previous (working) install in place — clobbering
# it would turn a recoverable update failure into a total outage.
#
# User-data caveat: an install dir like $SIDEBAND_DIR holds the cloned repo +
# build artifacts only. Identity / config live in $REAL_HOME/.reticulum/ and
# $REAL_HOME/.config/<app>/ respectively, which we never touch.
#
# Usage: cleanup_partial_install <component_name> <install_dir> <is_update>
cleanup_partial_install() {
    local component="$1"
    local target_dir="$2"
    local is_update="$3"

    if [ "$is_update" = "true" ]; then
        print_info "$component update failed — previous install left intact at $target_dir"
        print_info "Re-run the install option to retry; existing version still works"
        log_message "$component update failed; preserving previous install at $target_dir"
        return 0
    fi

    if [ -d "$target_dir" ]; then
        print_info "Cleaning up partial $component install at $target_dir..."
        if rm -rf "$target_dir"; then
            print_success "Partial install cleaned up — safe to retry"
            log_message "Cleaned up partial $component install at $target_dir"
        else
            print_warning "Could not remove $target_dir — remove manually before retry"
            log_warn "Failed to clean up partial $component install at $target_dir"
        fi
    fi
}

# ensure_rns_floor — advisory (non-blocking) check that the installed RNS meets a
# minimum version. MeshChatX declares rns>=1.2.5; pip resolves/upgrades it on
# install, so this only warns if something left an older RNS behind. We do NOT
# pin or fork RNS (that is MeshForge's job, not this lightweight tool's).
ensure_rns_floor() {
    local cur
    cur=$(get_installed_version "rns")
    [ -z "$cur" ] && return 0
    # sort -V -C succeeds when the input is already in ascending order, i.e.
    # RNS_MIN_VERSION <= cur. If it fails, cur is below the floor.
    if printf '%s\n%s\n' "$RNS_MIN_VERSION" "$cur" | sort -V -C 2>/dev/null; then
        return 0
    fi
    print_warning "RNS $cur is below MeshChatX's required $RNS_MIN_VERSION — pip should have upgraded it"
    log_warn "RNS $cur below MeshChatX floor $RNS_MIN_VERSION; verify the install"
    return 0
}

install_meshchatx() {
    print_section "Installing MeshChatX"

    echo -e "${CYAN}${BOLD}About MeshChatX${NC}\n"
    echo "MeshChatX (Quad4 Software) is the actively maintained successor to the"
    echo "original Reticulum MeshChat — a web-based LXMF messaging client."
    echo "It installs as a pip wheel with the frontend bundled, so no Node.js"
    echo "build is required. Run it headless and open the web UI in a browser."
    echo ""

    # Disk space pre-check — the wheel is tens of MB (no npm tree, no clone).
    if ! check_disk_space 100 "$REAL_HOME"; then
        print_error "Insufficient disk space for MeshChatX installation"
        return 1
    fi

    # Python >=3.11 gate — MeshChatX declares requires-python>=3.11. Fail fast
    # with a clear message instead of an opaque pip 'requires-python' error.
    if has_command python3; then
        local py_ok
        py_ok=$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 11) else 0)' 2>/dev/null)
        if [ "$py_ok" != "1" ]; then
            local py_ver
            py_ver=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "unknown")
            print_error "MeshChatX requires Python 3.11+ (found $py_ver)"
            print_info "Upgrade your OS or install a newer Python, then retry."
            log_message "MeshChatX install aborted: Python $py_ver < 3.11"
            return 1
        fi
    else
        print_error "python3 not found — install the Reticulum ecosystem first (menu option 1)"
        return 1
    fi

    log_message "Installing MeshChatX"

    # Legacy migration — the deprecated git/npm install left a heavy tree behind.
    if [ -d "$MESHCHAT_LEGACY_DIR" ]; then
        print_warning "Found the old git-based MeshChat at $MESHCHAT_LEGACY_DIR"
        echo "  This is deprecated and can be hundreds of MB (node_modules + build)."
        echo "  Your Reticulum identity in ~/.reticulum is untouched by removal."
        if confirm_action "Remove the old install to reclaim disk space?" "y"; then
            if rm -rf "$MESHCHAT_LEGACY_DIR"; then
                print_success "Removed legacy MeshChat at $MESHCHAT_LEGACY_DIR"
                log_message "Removed legacy MeshChat dir $MESHCHAT_LEGACY_DIR"
            else
                print_warning "Could not remove $MESHCHAT_LEGACY_DIR — remove it manually"
            fi
        fi
    fi

    # Step-based progress (init_operation from meshforge pattern)
    init_operation "Installing MeshChatX" \
        "Install reticulum-meshchatx (pip)" \
        "Verify installation"

    # Step 1: pip install the wheel (bundled frontend; resolves rns>=1.2.5).
    if retry_with_backoff 3 run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install "$MESHCHATX_PKG" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        next_step "success"
    else
        next_step "fail"
        complete_operation "fail"
        print_error "Failed to install MeshChatX"
        show_error_help "pip" ""
        return 1
    fi

    # Step 2: Verify installation (bust the version cache for a fresh read).
    unset "_VERSION_CACHE[$MESHCHATX_PKG]" 2>/dev/null || true
    MESHCHATX_VERSION=$(get_installed_version "$MESHCHATX_PKG")
    MESHCHAT_VERSION="$MESHCHATX_VERSION"   # back-compat
    if [ -n "$MESHCHATX_VERSION" ]; then
        print_success "MeshChatX v$MESHCHATX_VERSION installed successfully"
        log_message "MeshChatX installed: $MESHCHATX_VERSION"
        next_step "success"
    else
        next_step "fail"
        complete_operation "fail"
        print_error "MeshChatX install reported success but the package is not detectable"
        return 1
    fi

    if ! has_command meshchatx; then
        print_warning "meshchatx installed but not on PATH yet"
        print_info "Restart your shell or run: hash -r  (it lives in ~/.local/bin)"
    fi

    # Advisory RNS version-parity check (MeshChatX needs rns>=$RNS_MIN_VERSION).
    ensure_rns_floor

    create_meshchatx_launcher

    echo ""
    print_info "Start MeshChatX:  meshchatx --headless"
    print_info "Then open:        $MESHCHATX_URL  (self-signed cert — your browser will warn)"

    complete_operation "success"
    return 0
}

# Back-compat alias — older code/tests may still call install_meshchat.
install_meshchat() { install_meshchatx "$@"; }

# Unified desktop launcher creator (merges meshchat + sideband patterns)
# Usage: create_desktop_launcher <filename> <name> <comment> <exec> <icon> [extra_keys]
create_desktop_launcher() {
    local filename="$1" name="$2" comment="$3" exec_cmd="$4" icon="$5" extra_keys="$6"

    if [ -z "$DISPLAY" ] && [ -z "$XDG_CURRENT_DESKTOP" ]; then
        return 0
    fi

    print_info "Creating desktop launcher for $name..."

    local desktop_file="$REAL_HOME/.local/share/applications/${filename}.desktop"
    mkdir -p "$REAL_HOME/.local/share/applications"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Exec=$exec_cmd
Icon=$icon
Terminal=false
Categories=Network;Communication;
${extra_keys}
EOF

    chmod +x "$desktop_file"
    print_success "Desktop launcher created"
    log_message "Created $name desktop launcher"
}

create_meshchatx_launcher() {
    # MeshChatX runs as a headless web daemon; the launcher starts it and the
    # user opens $MESHCHATX_URL in a browser. No bundled icon file exists, so
    # use a generic themed icon name.
    create_desktop_launcher "meshchatx" \
        "Reticulum MeshChatX" \
        "Web-based LXMF messaging client for Reticulum" \
        "meshchatx --headless --host $MESHCHATX_HOST --port $MESHCHATX_PORT --storage-dir $MESHCHATX_STORAGE_DIR" \
        "network-transmit-receive"
}

# Back-compat alias.
create_meshchat_launcher() { create_meshchatx_launcher "$@"; }

#########################################################
# Sideband Installation
#########################################################

install_sideband() {
    print_section "Installing Sideband"

    echo -e "${CYAN}${BOLD}About Sideband${NC}\n"
    echo "Sideband is a graphical LXMF messaging application that provides:"
    echo "  • Secure end-to-end encrypted messaging"
    echo "  • Works over any medium Reticulum supports"
    echo "  • Available for Linux, macOS, Windows, and Android"
    echo ""

    # Check Python first
    if ! check_python || ! check_pip; then
        print_error "Python 3.7+ and pip are required"
        return 1
    fi

    # Check for display (Sideband is a GUI app)
    if [ -z "$DISPLAY" ] && [ -z "$XDG_CURRENT_DESKTOP" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        print_warning "No graphical display detected"
        echo ""
        echo "Sideband requires a graphical environment to run."
        echo "On headless systems, consider using NomadNet (terminal client) instead."
        echo ""
        if ! confirm_action "Continue anyway?"; then
            return 1
        fi
    fi

    # Installation method menu
    echo -e "${BOLD}Installation Options:${NC}\n"
    echo "   1) Install via pip (recommended for Linux)"
    echo "   2) Install from source (latest development version)"
    echo "   3) Download AppImage (portable, no installation)"
    echo "   4) Show platform-specific instructions"
    echo "   0) Cancel"
    echo ""
    echo -n "Select installation method: "
    read -r INSTALL_METHOD

    case $INSTALL_METHOD in
        1)
            install_sideband_pip
            ;;
        2)
            install_sideband_source
            ;;
        3)
            show_sideband_appimage_info
            ;;
        4)
            show_sideband_platform_instructions
            ;;
        0|"")
            print_info "Installation cancelled"
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
}

install_sideband_pip() {
    print_section "Installing Sideband via pip"

    # Check for required system dependencies
    print_info "Checking system dependencies..."

    local missing_deps=()

    # Check for required packages for GUI
    if ! dpkg -l | grep -q "python3-tk"; then
        missing_deps+=("python3-tk")
    fi
    if ! dpkg -l | grep -q "python3-pil"; then
        missing_deps+=("python3-pil" "python3-pil.imagetk")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Installing required dependencies..."
        run_with_timeout "$APT_TIMEOUT" sudo apt update
        run_with_timeout "$APT_TIMEOUT" sudo apt install -y "${missing_deps[@]}" 2>&1 | tee -a "$UPDATE_LOG"
    fi

    print_info "Installing Sideband..."

    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install sbapp --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed successfully"

        # Verify installation
        if has_command sideband || "$PIP_CMD" show sbapp &>/dev/null; then
            local sb_version
            sb_version=$($PIP_CMD show sbapp 2>/dev/null | grep "^Version:" | awk '{print $2}')
            print_success "Sideband v$sb_version is ready"
            log_message "Installed Sideband v$sb_version"

            # Create desktop launcher
            create_sideband_launcher

            echo ""
            print_info "To launch Sideband, run: ${GREEN}sideband${NC}"
        else
            print_warning "Installation completed but sideband command not found"
            print_info "Try: python3 -m sbapp"
        fi
        return 0
    else
        print_error "Failed to install Sideband"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1) Ensure you have Python 3.7 or newer"
        echo "  2) Try: pip3 install --user sbapp"
        echo "  3) Check internet connection"
        log_message "Sideband installation failed"
        return 1
    fi
}

install_sideband_source() {
    print_section "Installing Sideband from Source"

    local is_update=false

    if [ -d "$SIDEBAND_DIR" ]; then
        is_update=true
        print_warning "Sideband directory already exists"
        if confirm_action "Update existing installation?" "y"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
            print_info "Updating from git..."
            # Wrap in an if-conditional: pipefail is on, but a bare pipeline
            # ignored the exit code and let pip install run against a stale tree.
            if ! retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git pull origin main 2>&1 | tee -a "$UPDATE_LOG"; then
                print_error "Failed to pull Sideband updates"
                show_error_help "git" ""
                popd > /dev/null || true
                # is_update=true → cleanup_partial_install will preserve the dir
                cleanup_partial_install "Sideband" "$SIDEBAND_DIR" "$is_update"
                return 1
            fi
        else
            return 1
        fi
    else
        print_info "Cloning Sideband repository..."
        if retry_with_backoff 3 run_with_timeout "$GIT_TIMEOUT" git clone https://github.com/markqvist/Sideband.git "$SIDEBAND_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
            pushd "$SIDEBAND_DIR" > /dev/null || return 1
        else
            print_error "Failed to clone Sideband repository"
            cleanup_partial_install "Sideband" "$SIDEBAND_DIR" "$is_update"
            return 1
        fi
    fi

    print_info "Installing from source..."
    if run_with_timeout "$PIP_TIMEOUT" "$PIP_CMD" install . --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "Sideband installed from source"
        create_sideband_launcher
        popd > /dev/null || true
        return 0
    else
        print_error "Failed to install Sideband from source"
        popd > /dev/null || true
        cleanup_partial_install "Sideband" "$SIDEBAND_DIR" "$is_update"
        return 1
    fi
}

show_sideband_appimage_info() {
    print_section "Downloading Sideband AppImage"

    local appimage_url="https://github.com/markqvist/Sideband/releases/latest"

    echo -e "${YELLOW}AppImage is a portable format that runs without installation.${NC}"
    echo ""
    echo "Please visit the releases page to download the latest AppImage:"
    echo -e "  ${CYAN}$appimage_url${NC}"
    echo ""
    echo "After downloading:"
    echo "  1) Make it executable: chmod +x Sideband*.AppImage"
    echo "  2) Run it: ./Sideband*.AppImage"
    echo ""

    # Try to open browser if available
    if has_command xdg-open && [ -n "$DISPLAY" ]; then
        if confirm_action "Open releases page in browser?" "y"; then
            xdg-open "$appimage_url" 2>/dev/null &
            print_success "Opened browser"
        fi
    fi
}

show_sideband_platform_instructions() {
    print_section "Platform-Specific Instructions"

    echo -e "${BOLD}Linux (Debian/Ubuntu):${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the AppImage from GitHub releases"
    echo ""

    echo -e "${BOLD}Raspberry Pi:${NC}"
    echo "  pip3 install sbapp --break-system-packages"
    echo "  Note: May require extra time to build on older Pi models"
    echo ""

    echo -e "${BOLD}macOS:${NC}"
    echo "  pip3 install sbapp"
    echo "  or download the .dmg from GitHub releases"
    echo ""

    echo -e "${BOLD}Windows:${NC}"
    echo "  pip install sbapp"
    echo "  or download the .exe installer from GitHub releases"
    echo ""

    echo -e "${BOLD}Android:${NC}"
    echo "  Download from F-Droid or GitHub releases (.apk)"
    echo "  Note: Sideband is also available on Google Play"
    echo ""

    echo -e "${CYAN}GitHub Releases:${NC}"
    echo "  https://github.com/markqvist/Sideband/releases"
}

create_sideband_launcher() {
    create_desktop_launcher "sideband" \
        "Sideband" \
        "LXMF Messaging Client for Reticulum" \
        "sideband" \
        "sideband" \
        "Keywords=lxmf;reticulum;mesh;messaging;"
}

#########################################################
# Version Update Checker (adapted from meshforge version_checker.py)
# Queries PyPI for latest versions, compares with installed
#########################################################

# Cache for PyPI version lookups (1-hour TTL, survives menu redraws)
declare -A _PYPI_VERSION_CACHE=()
_PYPI_CACHE_TIME=0
_PYPI_CACHE_TTL=3600  # 1 hour

# Compare two semver strings: returns 0 if $2 > $1 (update available)
compare_semver() {
    local installed="$1" latest="$2"
    [ -z "$installed" ] || [ -z "$latest" ] && return 1

    local IFS='.'
    # shellcheck disable=SC2206
    local -a inst=($installed) lat=($latest)

    local i
    for i in 0 1 2; do
        local iv="${inst[$i]:-0}" lv="${lat[$i]:-0}"
        # Strip non-numeric suffixes (e.g., "6rc1" → "6")
        iv="${iv%%[!0-9]*}"
        lv="${lv%%[!0-9]*}"
        iv="${iv:-0}"
        lv="${lv:-0}"
        if [ "$lv" -gt "$iv" ]; then
            return 0  # update available
        elif [ "$lv" -lt "$iv" ]; then
            return 1  # installed is newer
        fi
    done
    return 1  # equal
}

# Query PyPI JSON API for latest version of a package
get_latest_pypi_version() {
    local package="$1"

    # Check in-memory cache first
    if [ -n "${_PYPI_VERSION_CACHE[$package]+x}" ]; then
        local now
        now=$(date +%s)
        if [ $(( now - _PYPI_CACHE_TIME )) -lt $_PYPI_CACHE_TTL ]; then
            echo "${_PYPI_VERSION_CACHE[$package]}"
            return 0
        fi
    fi

    # Query PyPI (with timeout to avoid blocking on no internet)
    local json
    json=$(run_with_timeout 10 curl -s "https://pypi.org/pypi/${package}/json" 2>/dev/null) || return 1

    # Extract version from JSON (minimal parsing, no jq dependency)
    local version
    version=$(echo "$json" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$version" ]; then
        _PYPI_VERSION_CACHE[$package]="$version"
        _PYPI_CACHE_TIME=$(date +%s)
        echo "$version"
        return 0
    fi
    return 1
}

# Check all ecosystem component versions and display table
# Usage: check_ecosystem_versions [--quiet]
# --quiet: set _UPDATE_AVAILABLE_COUNT without printing
check_ecosystem_versions() {
    local quiet=false
    [ "${1:-}" = "--quiet" ] && quiet=true

    # Packages to check: pip_name:display_name
    local -a packages=(
        "rns:Reticulum (RNS)"
        "lxmf:LXMF Protocol"
        "nomadnet:NomadNet"
        "rnodeconf:RNode Config"
        "sbapp:Sideband"
    )

    local updates_available=0
    local checked=0
    local -a results=()

    if [ "$quiet" != true ]; then
        print_section "Ecosystem Version Check"
        echo ""
        printf "  ${BOLD}%-18s %-12s %-12s %s${NC}\n" "Component" "Installed" "Latest" "Status"
        printf "  %-18s %-12s %-12s %s\n" "─────────────────" "───────────" "───────────" "──────"
    fi

    for entry in "${packages[@]}"; do
        local pip_name="${entry%%:*}"
        local display_name="${entry#*:}"

        local installed latest status_str status_color

        # Clear cache for this lookup to get fresh installed version
        unset "_VERSION_CACHE[$pip_name]" 2>/dev/null || true
        installed=$(get_installed_version "$pip_name")

        if [ -z "$installed" ]; then
            installed="--"
            latest="--"
            status_str="not installed"
            status_color="$YELLOW"
        else
            latest=$(get_latest_pypi_version "$pip_name" 2>/dev/null) || latest=""

            if [ -z "$latest" ]; then
                status_str="offline"
                status_color="$YELLOW"
            elif compare_semver "$installed" "$latest"; then
                status_str="↑ update"
                status_color="$CYAN"
                ((updates_available++))
            else
                status_str="✓ current"
                status_color="$GREEN"
            fi
            ((checked++))
        fi

        if [ "$quiet" != true ]; then
            printf "  %-18s %-12s %-12s ${status_color}%s${NC}\n" \
                "$display_name" "$installed" "${latest:---}" "$status_str"
        fi

        results+=("$pip_name:$installed:${latest:---}:$status_str")
    done

    if [ "$quiet" != true ]; then
        echo ""
        if [ "$updates_available" -gt 0 ]; then
            print_info "$updates_available update(s) available. Use 'Install/Update Reticulum Ecosystem' to upgrade."
        elif [ "$checked" -gt 0 ]; then
            print_success "All installed components are up to date."
        fi
        echo ""
    fi

    _UPDATE_AVAILABLE_COUNT=$updates_available
    log_message "Version check: $checked checked, $updates_available updates available"
    return 0
}
