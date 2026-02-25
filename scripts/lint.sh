#!/bin/bash
# shellcheck disable=SC2034  # Variables used for counting
#########################################################
# RNS Management Tool — Custom Linter
# Enforces project-specific security and coding standards
#
# Adapted from meshforge scripts/lint.py (MF001-MF010)
# Checks RNS001-RNS006 rules from CLAUDE.md
#
# Usage:
#   ./scripts/lint.sh              # Lint all bash source files
#   ./scripts/lint.sh lib/rnode.sh # Lint specific file
#   ./scripts/lint.sh --staged     # Lint only git-staged files (for pre-commit hooks)
#########################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0
WARNINGS=0

# Colors (if terminal supports them)
if [ -t 1 ]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED='' YELLOW='' GREEN='' NC=''
fi

report() {
    local severity="$1" file="$2" line="$3" code="$4" message="$5"
    if [ "$severity" = "E" ]; then
        echo -e "${RED}${file}:${line}: [E] ${code}: ${message}${NC}"
        ((ERRORS++))
    else
        echo -e "${YELLOW}${file}:${line}: [W] ${code}: ${message}${NC}"
        ((WARNINGS++))
    fi
}

lint_file() {
    local filepath="$1"
    local lineno=0

    while IFS= read -r line; do
        ((lineno++))
        local stripped="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace

        # Skip comments
        [[ "$stripped" == "#"* ]] && continue

        # RNS001: No eval usage (command injection risk)
        # Skip lines that merely reference 'eval' in grep patterns, strings, or comments
        if [[ "$line" =~ [^_a-zA-Z\"\'\\]eval[[:space:]] ]] || [[ "$line" =~ ^eval[[:space:]] ]]; then
            # Exclude grep/test assertions that search for eval, not invoke it
            if [[ "$line" != *"grep"* ]] && [[ "$line" != *"echo"* ]] && [[ "$line" != *"report"* ]]; then
                report "E" "$filepath" "$lineno" "RNS001" \
                    "eval usage detected — use array-based command execution instead"
            fi
        fi

        # RNS002: Device port validation — check for rnodeconf calls without prior validation
        # (Informational: just flag direct rnodeconf calls with variable args)
        if [[ "$line" =~ rnodeconf[[:space:]]+\"\$ ]] && [[ "$filepath" != *"test"* ]]; then
            # Check if this file has the validation regex or centralized validator
            if ! grep -qE 'tty\[A-Za-z0-9\]|validate_device_port' "$filepath" 2>/dev/null; then
                report "W" "$filepath" "$lineno" "RNS002" \
                    "rnodeconf called with variable — ensure device port is validated"
            fi
        fi

        # RNS004: Path traversal — check for tar extraction without validation
        if [[ "$line" =~ tar[[:space:]].*-x ]] && [[ "$line" != *"grep"* ]]; then
            # Look backwards in the file for path traversal check
            local context
            context=$(head -n "$lineno" "$filepath" | tail -n 20)
            if ! echo "$context" | grep -q '\.\./\|traversal\|invalid paths\|validate_archive_contents' 2>/dev/null; then
                report "W" "$filepath" "$lineno" "RNS004" \
                    "tar extraction without visible path traversal validation nearby"
            fi
        fi

        # RNS006: Network commands without timeout protection
        # Check for apt/pip/git/curl without run_with_timeout wrapper
        if [[ "$line" =~ sudo[[:space:]]+apt[[:space:]] ]] && \
           [[ "$line" != *"run_with_timeout"* ]] && [[ "$line" != *"retry_with_backoff"* ]]; then
            report "W" "$filepath" "$lineno" "RNS006" \
                "apt command without timeout wrapper — use run_with_timeout"
        fi

        if [[ "$line" =~ pip[3]?[[:space:]]+install ]] && \
           [[ "$line" != *"run_with_timeout"* ]] && [[ "$line" != *"retry_with_backoff"* ]]; then
            report "W" "$filepath" "$lineno" "RNS006" \
                "pip install without timeout wrapper — use run_with_timeout"
        fi

        # RNS003: Radio parameters added to CMD_ARGS should have range validation nearby
        if [[ "$line" =~ CMD_ARGS\+=.*--(sf|cr|txp|freq|bw) ]] && [[ "$filepath" != *"test"* ]]; then
            local context
            context=$(head -n "$lineno" "$filepath" | tail -n 12)
            if ! echo "$context" | grep -qE '\-ge.*\-le|\-lt.*\-gt|\^[0-9]+\$|\^\-\??\[0-9\]|validate_numeric_range|validate_frequency' 2>/dev/null; then
                report "W" "$filepath" "$lineno" "RNS003" \
                    "Radio parameter added to CMD_ARGS without visible range validation nearby"
            fi
        fi

        # RNS005: Destructive operations (rm -rf) should have confirmation nearby
        if [[ "$line" =~ rm[[:space:]]+-rf ]] && [[ "$filepath" != *"test"* ]]; then
            local context
            context=$(head -n "$lineno" "$filepath" | tail -n 15)
            if ! echo "$context" | grep -qE 'confirm_action|CONFIRM.*RESET|y/N|Y/n|cleanup_on_exit|TEMP_EXPORT|mktemp|TMPDIR' 2>/dev/null; then
                report "W" "$filepath" "$lineno" "RNS005" \
                    "rm -rf without visible confirmation or temp-dir context nearby"
            fi
        fi

        # RNS006 extension: rnodeconf calls without timeout protection
        if [[ "$line" =~ [^_a-zA-Z]rnodeconf[[:space:]] ]] && \
           [[ "$line" != *"run_with_timeout"* ]] && [[ "$line" != *"command -v"* ]] && \
           [[ "$line" != *"--version"* ]] && [[ "$line" != *"--help"* ]] && \
           [[ "$line" != *"console"* ]] && [[ "$filepath" != *"test"* ]]; then
            report "W" "$filepath" "$lineno" "RNS006" \
                "rnodeconf call without timeout wrapper — use run_with_timeout"
        fi

    done < "$filepath"
}

# Determine files to lint
FILES=()
if [ "${1:-}" = "--staged" ]; then
    # Lint only git-staged .sh files (for pre-commit hook integration)
    while IFS= read -r f; do
        [[ "$f" == *.sh ]] && [ -f "$f" ] && FILES+=("$f")
    done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
elif [ $# -gt 0 ]; then
    FILES=("$@")
else
    # Default: all bash source files (excluding tests — they intentionally test patterns)
    while IFS= read -r -d '' f; do
        FILES+=("$f")
    done < <(find "$SCRIPT_DIR" -type f \( -name "*.sh" \) \
        ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/tests/*" -print0 | sort -z)
fi

echo "RNS Management Tool Linter"
echo "=========================="
echo "Checking ${#FILES[@]} file(s)..."
echo ""

for file in "${FILES[@]}"; do
    lint_file "$file"
done

echo ""
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}No issues found.${NC}"
else
    echo "Found $ERRORS error(s), $WARNINGS warning(s)"
fi

# Exit with error only for errors, not warnings
[ "$ERRORS" -gt 0 ] && exit 1
exit 0
