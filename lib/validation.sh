# shellcheck shell=bash
# shellcheck disable=SC2034  # Cross-module globals used by other sourced modules
#########################################################
# lib/validation.sh — Centralized input validation
# Sourced by rns_management_tool.sh
#
# Consolidates validation logic scattered across modules
# into a single source of truth (adapted from meshforge
# centralized validation patterns).
#
# Functions:
#   validate_device_port     — USB/serial device path (RNS002)
#   validate_numeric_range   — Generic bounded numeric check (RNS003)
#   validate_rns_hash        — Reticulum destination hash
#   validate_archive_path    — Import file safety (RNS004)
#   validate_archive_contents — Tar traversal + symlink check (RNS004)
#   validate_frequency       — RF frequency in Hz
#   validate_identifier      — Alphanumeric + underscore string
#########################################################

# RNS002: Device port validation
# Usage: validate_device_port "/dev/ttyUSB0" || return 1
validate_device_port() {
    local port="$1"
    if [ -z "$port" ]; then
        print_error "No device port specified"
        return 1
    fi
    if [[ ! "$port" =~ ^/dev/tty[A-Za-z0-9]+$ ]]; then
        print_error "Invalid device port format. Expected: /dev/ttyUSB0 or /dev/ttyACM0"
        return 1
    fi
    return 0
}

# RNS003: Generic numeric range validation
# Usage: validate_numeric_range "$value" 7 12 "Spreading Factor" || return 1
# Supports negative ranges (e.g., -10 to 30 for TX power)
validate_numeric_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local label="${4:-Value}"

    if [ -z "$value" ]; then
        return 1  # Empty is not an error — caller decides whether to skip
    fi
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        print_warning "Invalid $label — must be numeric. Skipping."
        return 1
    fi
    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        print_warning "Invalid $label — must be between $min and $max. Skipping."
        return 1
    fi
    return 0
}

# Validate RNS destination hash format (hex string, 20-64 chars)
# Usage: validate_rns_hash "$hash" || return 1
validate_rns_hash() {
    local hash="$1"
    if [ -z "$hash" ]; then
        print_error "No destination hash provided"
        return 1
    fi
    if [[ ! "$hash" =~ ^[0-9a-fA-F]{20,64}$ ]]; then
        print_error "Invalid destination hash format (expected 20-64 hex characters)"
        return 1
    fi
    return 0
}

# RNS004: Validate an import file path (safe, exists, correct extension)
# Usage: validate_archive_path "$filepath" || return 1
validate_archive_path() {
    local filepath="$1"

    # Reject empty or paths with null bytes
    if [[ -z "$filepath" ]] || [[ "$filepath" == *$'\0'* ]]; then
        print_error "Invalid file path"
        return 1
    fi

    # Resolve to absolute path without following symlinks
    filepath=$(realpath -s "$filepath" 2>/dev/null) || {
        print_error "Cannot resolve path: $filepath"
        return 1
    }

    if [ ! -f "$filepath" ]; then
        print_error "File not found: $filepath"
        return 1
    fi

    if [[ ! "$filepath" =~ \.tar\.gz$ ]]; then
        print_error "Invalid file format. Expected .tar.gz archive"
        return 1
    fi

    return 0
}

# RNS004: Validate archive contents for path traversal and symlinks
# Usage: validate_archive_contents "$filepath" || return 1
validate_archive_contents() {
    local filepath="$1"

    # Check for path traversal attempts (../) and absolute paths
    if tar -tzf "$filepath" 2>/dev/null | grep -qE '(^/|\.\./)'; then
        print_error "Security: Archive contains invalid paths (absolute or traversal)"
        log_message "SECURITY: Rejected archive with invalid paths: $filepath"
        return 1
    fi

    # Check for symlink entries (potential symlink attack)
    if tar -tvf "$filepath" 2>/dev/null | grep -qE '^l'; then
        print_error "Security: Archive contains symbolic links (potential symlink attack)"
        log_message "SECURITY: Rejected archive with symlinks: $filepath"
        return 1
    fi

    return 0
}

# Validate RF frequency (must be positive integer, reasonable Hz range)
# Common LoRa frequencies: 137-1020 MHz → 137000000-1020000000 Hz
# Usage: validate_frequency "$freq" || return 1
validate_frequency() {
    local freq="$1"
    if [ -z "$freq" ]; then
        return 1  # Empty — caller decides
    fi
    if [[ ! "$freq" =~ ^[0-9]+$ ]]; then
        print_warning "Invalid frequency — must be numeric. Skipping."
        return 1
    fi
    # Sanity check: 100 MHz to 1.1 GHz covers all LoRa ISM bands
    if [ "$freq" -lt 100000000 ] || [ "$freq" -gt 1100000000 ]; then
        print_warning "Frequency $freq Hz outside expected LoRa range (100-1100 MHz). Proceed with caution."
    fi
    return 0
}

# Validate alphanumeric identifier (model names, platform names, etc.)
# Usage: validate_identifier "$value" "Model" || return 1
validate_identifier() {
    local value="$1"
    local label="${2:-Identifier}"

    if [ -z "$value" ]; then
        return 1  # Empty — caller decides
    fi
    if [[ ! "$value" =~ ^[a-zA-Z0-9_]+$ ]]; then
        print_warning "Invalid $label — only alphanumeric and underscores allowed. Skipping."
        return 1
    fi
    return 0
}
