#!/bin/bash

################################################################################
# QUICK FIXES - Update Deprecated/Outdated Software
# Run this script to immediately update npm, pip, and critical security packages
################################################################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}RNS Management Tool Quick Fixes${NC}"
echo -e "${BLUE}================================${NC}\n"

# =============================================================================
# FIX 1: Update npm to latest version
# =============================================================================
echo -e "${YELLOW}[1/4] Updating npm...${NC}"
if command -v npm &> /dev/null; then
    CURRENT_NPM=$(npm --version)
    echo "Current npm version: $CURRENT_NPM"

    echo "Installing npm@latest..."
    npm install -g npm@latest

    NEW_NPM=$(npm --version)
    echo -e "${GREEN}✓ npm updated: $CURRENT_NPM → $NEW_NPM${NC}\n"
else
    echo -e "${RED}✗ npm not found${NC}\n"
fi

# =============================================================================
# FIX 2: Update pip to latest version
# =============================================================================
echo -e "${YELLOW}[2/4] Updating pip...${NC}"
if command -v pip3 &> /dev/null; then
    CURRENT_PIP=$(pip3 --version | awk '{print $2}')
    echo "Current pip version: $CURRENT_PIP"

    echo "Installing pip latest version..."
    pip3 install --upgrade pip --break-system-packages

    NEW_PIP=$(pip3 --version | awk '{print $2}')
    echo -e "${GREEN}✓ pip updated: $CURRENT_PIP → $NEW_PIP${NC}\n"
else
    echo -e "${RED}✗ pip3 not found${NC}\n"
fi

# =============================================================================
# FIX 3: Update critical security packages
# =============================================================================
echo -e "${YELLOW}[3/4] Updating security-critical Python packages...${NC}"
echo "This may take a few minutes...\n"

SECURITY_PACKAGES=(
    "cryptography"
    "PyJWT"
    "setuptools"
    "wheel"
)

for package in "${SECURITY_PACKAGES[@]}"; do
    echo -e "Updating ${BLUE}$package${NC}..."
    if pip3 show "$package" &> /dev/null; then
        OLD_VER=$(pip3 show "$package" | grep "^Version:" | awk '{print $2}')
        pip3 install --upgrade "$package" --break-system-packages 2>&1 | grep -i "successfully\|already\|requirement" || true
        NEW_VER=$(pip3 show "$package" | grep "^Version:" | awk '{print $2}')

        if [ "$OLD_VER" != "$NEW_VER" ]; then
            echo -e "${GREEN}  ✓ $package: $OLD_VER → $NEW_VER${NC}"
        else
            echo -e "${GREEN}  ✓ $package: $NEW_VER (already latest)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ $package not installed, skipping${NC}"
    fi
done

echo ""

# =============================================================================
# FIX 4: Update global npm packages
# =============================================================================
echo -e "${YELLOW}[4/4] Updating global npm packages...${NC}"
if command -v npm &> /dev/null; then
    echo "Checking for outdated global packages..."
    npm update -g

    echo -e "${GREEN}✓ Global npm packages updated${NC}\n"
else
    echo -e "${RED}✗ npm not available${NC}\n"
fi

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}================================${NC}\n"

echo "Current versions after updates:"
echo ""

if command -v python3 &> /dev/null; then
    echo "Python:  $(python3 --version | awk '{print $2}')"
fi

if command -v pip3 &> /dev/null; then
    echo "pip:     $(pip3 --version | awk '{print $2}')"
fi

if command -v node &> /dev/null; then
    echo "Node.js: $(node --version)"
fi

if command -v npm &> /dev/null; then
    echo "npm:     $(npm --version)"
fi

echo ""
echo -e "${GREEN}✓ Quick fixes completed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review DEPRECATION_AUDIT_REPORT.md for detailed findings"
echo "  2. Review FIXES_TO_APPLY.sh for script improvements"
echo "  3. Test the reticulum_updater.sh script"
echo ""
echo -e "${YELLOW}Note: The main script (reticulum_updater.sh) still needs updates.${NC}"
echo "See DEPRECATION_AUDIT_REPORT.md section 8 for required changes."
echo ""
