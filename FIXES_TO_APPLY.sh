#!/bin/bash

################################################################################
# CRITICAL FIXES FOR reticulum_updater.sh
# These changes fix deprecated Node.js installation and add security improvements
#
# USAGE:
# 1. Review this file
# 2. Manually apply changes to reticulum_updater.sh
# 3. Test thoroughly before deployment
#
# OR use the provided sed commands at the end to apply automatically (advanced)
################################################################################

# =============================================================================
# FIX 1: Add modern Node.js installation function
# Location: Add after line 98 (after check_pip function)
# =============================================================================

cat << 'EOF'

install_nodejs_modern() {
    print_section "Installing Modern Node.js"

    # Check if nodejs is already installed and up to date
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        if [ "$NODE_MAJOR" -ge 18 ]; then
            print_success "Node.js $NODE_VERSION is already installed (compatible)"

            # Update npm if needed
            NPM_VERSION=$(npm --version | cut -d. -f1)
            if [ "$NPM_VERSION" -lt 10 ]; then
                print_info "Updating npm to latest version..."
                npm install -g npm@latest 2>&1 | tee -a "$UPDATE_LOG"
            fi
            return 0
        else
            print_warning "Node.js $NODE_VERSION is too old, upgrading..."
        fi
    fi

    print_info "Installing Node.js from NodeSource repository..."
    log_message "Installing Node.js from NodeSource"

    # Install curl if not present
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        sudo apt install -y curl 2>&1 | tee -a "$UPDATE_LOG"
    fi

    # Install NodeSource repository for Node.js 22.x (LTS)
    if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "NodeSource repository added"

        # Install Node.js (includes npm)
        if sudo apt install -y nodejs 2>&1 | tee -a "$UPDATE_LOG"; then
            NODE_VERSION=$(node --version)
            NPM_VERSION=$(npm --version)
            print_success "Node.js $NODE_VERSION and npm $NPM_VERSION installed"
            log_message "Installed Node.js $NODE_VERSION and npm $NPM_VERSION"

            # Verify minimum versions
            NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
            if [ "$NODE_MAJOR" -ge 18 ]; then
                print_success "Node.js version check passed"
                return 0
            else
                print_error "Installed Node.js version is still too old"
                return 1
            fi
        else
            print_error "Failed to install Node.js"
            log_message "Node.js installation failed"
            return 1
        fi
    else
        print_error "Failed to add NodeSource repository"
        print_warning "Falling back to system Node.js (may be outdated)"
        log_message "NodeSource setup failed, using system nodejs"

        # Fallback to system packages
        sudo apt update
        sudo apt install -y nodejs npm 2>&1 | tee -a "$UPDATE_LOG"

        print_warning "System Node.js installed - may be outdated"
        print_warning "MeshChat build may fail with old Node.js versions"
        return 0
    fi
}

check_nodejs_version() {
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)

        print_info "Node.js version: $NODE_VERSION"

        if [ "$NODE_MAJOR" -lt 18 ]; then
            print_error "Node.js version $NODE_VERSION is too old for MeshChat"
            print_error "MeshChat requires Node.js 18 or higher"
            echo -e "${YELLOW}Would you like to upgrade Node.js now?${NC}"
            echo -n "Upgrade Node.js? (Y/n): "
            read -r UPGRADE_NODE

            if [[ ! "$UPGRADE_NODE" =~ ^[Nn]$ ]]; then
                install_nodejs_modern
                return $?
            else
                return 1
            fi
        else
            print_success "Node.js version $NODE_VERSION (compatible)"
            log_message "Node.js version check passed: $NODE_VERSION"
            return 0
        fi
    else
        print_error "Node.js not found"
        return 1
    fi
}

EOF

# =============================================================================
# FIX 2: Update MeshChat update function (around line 356-382)
# Replace the nodejs/npm installation section
# =============================================================================

cat << 'EOF'

# OLD CODE TO REPLACE (lines 356-382):
#     if ! command -v npm &> /dev/null; then
#         print_error "npm is required but not installed"
#         echo -n "Install Node.js and npm? (Y/n): "
#         read -r INSTALL_NPM
#         if [[ ! "$INSTALL_NPM" =~ ^[Nn]$ ]]; then
#             sudo apt update
#             sudo apt install -y nodejs npm
#         else
#             print_warning "Skipping MeshChat update (npm required)"
#             return 1
#         fi
#     fi

# NEW CODE:
    if ! command -v npm &> /dev/null; then
        print_error "npm is required but not installed"
        echo -n "Install Node.js and npm? (Y/n): "
        read -r INSTALL_NPM
        if [[ ! "$INSTALL_NPM" =~ ^[Nn]$ ]]; then
            if ! install_nodejs_modern; then
                print_error "Failed to install Node.js and npm"
                print_warning "Skipping MeshChat update"
                return 1
            fi
        else
            print_warning "Skipping MeshChat update (npm required)"
            return 1
        fi
    else
        # npm exists, but check version compatibility
        check_nodejs_version || {
            print_warning "Node.js version check failed but continuing anyway"
        }
    fi

EOF

# =============================================================================
# FIX 3: Update MeshChat install function (around line 420-434)
# Replace the nodejs/npm installation section
# =============================================================================

cat << 'EOF'

# OLD CODE TO REPLACE (lines 423-433):
#     if ! command -v npm &> /dev/null; then
#         print_info "Installing Node.js and npm..."
#         sudo apt update
#         sudo apt install -y nodejs npm
#     fi

# NEW CODE:
    if ! command -v npm &> /dev/null; then
        print_info "Installing Node.js and npm..."
        if ! install_nodejs_modern; then
            print_error "Failed to install Node.js and npm"
            return 1
        fi
    else
        # Verify Node.js version is compatible
        if ! check_nodejs_version; then
            print_error "Node.js version is incompatible with MeshChat"
            return 1
        fi
    fi

EOF

# =============================================================================
# FIX 4: Add npm security audit to MeshChat installation (line 393 and 443)
# =============================================================================

cat << 'EOF'

# ADD AFTER: npm install (line 393 and line 443)
# OLD CODE:
#         if npm install 2>&1 | tee -a "$UPDATE_LOG"; then
#             print_success "Dependencies updated"

# NEW CODE:
        if npm install 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Dependencies installed"

            # Check for security vulnerabilities
            print_info "Running security audit..."
            if npm audit 2>&1 | tee -a "$UPDATE_LOG"; then
                print_success "No critical vulnerabilities found"
            else
                print_warning "Vulnerabilities detected, attempting automatic fix..."
                npm audit fix --audit-level=moderate 2>&1 | tee -a "$UPDATE_LOG" || true
                print_info "Review audit log for details"
            fi

EOF

# =============================================================================
# ADDITIONAL RECOMMENDATIONS
# =============================================================================

cat << 'EOF'

# =============================================================================
# OPTIONAL: Update system packages first (add early in script)
# =============================================================================

update_npm_if_needed() {
    if command -v npm &> /dev/null; then
        NPM_CURRENT=$(npm --version)
        NPM_MAJOR=$(echo "$NPM_CURRENT" | cut -d. -f1)

        if [ "$NPM_MAJOR" -lt 10 ]; then
            print_warning "npm $NPM_CURRENT is outdated"
            print_info "Updating npm to latest version..."
            npm install -g npm@latest 2>&1 | tee -a "$UPDATE_LOG"
            NPM_NEW=$(npm --version)
            print_success "npm updated: $NPM_CURRENT → $NPM_NEW"
        fi
    fi
}

update_pip_if_needed() {
    PIP_CURRENT=$($PIP_CMD --version | awk '{print $2}')
    PIP_MAJOR=$(echo "$PIP_CURRENT" | cut -d. -f1)

    if [ "$PIP_MAJOR" -lt 24 ]; then
        print_warning "pip $PIP_CURRENT is outdated"
        print_info "Updating pip to latest version..."
        $PIP_CMD install --upgrade pip --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"
        PIP_NEW=$($PIP_CMD --version | awk '{print $2}')
        print_success "pip updated: $PIP_CURRENT → $PIP_NEW"
    fi
}

EOF

echo ""
echo "============================================================================"
echo "AUTOMATED FIXES"
echo "============================================================================"
echo ""
echo "To create a patched version of the script automatically, review and run:"
echo ""
echo "  ./apply_fixes.sh"
echo ""
echo "Or manually apply the changes above to reticulum_updater.sh"
echo ""
echo "After applying fixes, test with:"
echo "  1. shellcheck reticulum_updater.sh  (if available)"
echo "  2. bash -n reticulum_updater.sh  (syntax check)"
echo "  3. Test run in a VM or test environment"
echo ""
