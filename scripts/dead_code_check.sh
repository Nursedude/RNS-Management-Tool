#!/bin/bash
#########################################################
# RNS Management Tool — Dead Code Detection
# Finds functions defined in lib/ that are never referenced
# elsewhere in the codebase. Run as a development/audit tool.
#
# Usage: bash scripts/dead_code_check.sh
#########################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' NC=''
fi

echo "RNS Management Tool — Dead Code Detection"
echo "==========================================="
echo ""

dead_count=0
checked_count=0

for lib in "$SCRIPT_DIR"/lib/*.sh; do
    local_dead=0
    module_name=$(basename "$lib")

    # Extract function names (pattern: funcname() { or funcname () {)
    while IFS= read -r func_name; do
        [ -z "$func_name" ] && continue
        ((checked_count++))

        # Count files that reference this function (excluding tests, .git, this script)
        ref_files=$(grep -rl --include='*.sh' --include='*.bats' \
            -e "$func_name" "$SCRIPT_DIR" 2>/dev/null | \
            grep -v '/\.git/' | \
            grep -v '/tests/' | \
            grep -v 'dead_code_check' | \
            sort -u)

        ref_count=$(echo "$ref_files" | grep -c '^' 2>/dev/null || echo 0)

        # If only found in 1 file (the definition itself), it's potentially unused
        if [ "$ref_count" -le 1 ]; then
            echo -e "  ${YELLOW}UNUSED:${NC} $func_name  (defined in $module_name)"
            ((dead_count++))
            ((local_dead++))
        fi
    done < <(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$lib" | sed 's/()//')

    if [ "$local_dead" -gt 0 ]; then
        echo ""
    fi
done

echo ""
echo "==========================================="
echo -e "Checked: $checked_count functions across $(ls "$SCRIPT_DIR"/lib/*.sh | wc -l) modules"
if [ "$dead_count" -eq 0 ]; then
    echo -e "${GREEN}No unused functions found.${NC}"
else
    echo -e "${YELLOW}Found $dead_count potentially unused function(s).${NC}"
    echo "Review manually — some may be called dynamically or via menu dispatch."
fi
