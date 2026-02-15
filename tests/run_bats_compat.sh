#!/bin/bash
# Lightweight BATS-compatible test runner
# Transforms .bats files into runnable bash and executes each @test.
# Usage: ./tests/run_bats_compat.sh tests/file.bats [--verbose]
#
# Supports: @test, setup(), teardown(), skip, local variables
# Does NOT support: bats helpers (bats-assert, bats-support), load, run

set -o pipefail

VERBOSE=false
[[ "${2:-}" == "--verbose" || "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0
FAIL=0
SKIP=0
ERRORS=""

# Color output
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' NC=''
fi

# Find the .bats file
BATS_FILE=""
for arg in "$@"; do
    if [[ "$arg" == *.bats ]]; then
        BATS_FILE="$arg"
        break
    fi
done

if [ -z "$BATS_FILE" ] || [ ! -f "$BATS_FILE" ]; then
    echo "Usage: $0 <file.bats> [--verbose]"
    exit 1
fi

BATS_TEST_FILENAME="$(cd "$(dirname "$BATS_FILE")" && pwd)/$(basename "$BATS_FILE")"
export BATS_TEST_FILENAME

echo "Running: $(basename "$BATS_FILE")"
echo "═══════════════════════════════════════════"

# Step 1: Transform .bats -> .sh by replacing @test "name" { with _bats_test_N() {
TMPSCRIPT=$(mktemp /tmp/bats_compat_XXXXXX.sh)
trap 'rm -f "$TMPSCRIPT"' EXIT

# Write header
cat > "$TMPSCRIPT" << 'EOF'
#!/bin/bash
set -o pipefail
_BATS_SKIP=false
skip() { _BATS_SKIP=true; }
EOF

# Transform @test blocks into numbered functions
test_num=0
declare -a TEST_NAMES=()

while IFS= read -r line; do
    if [[ "$line" =~ ^@test[[:space:]]+\"(.+)\"[[:space:]]+\{[[:space:]]*$ ]]; then
        test_num=$((test_num + 1))
        TEST_NAMES+=("${BASH_REMATCH[1]}")
        echo "_bats_test_${test_num}() {" >> "$TMPSCRIPT"
    else
        echo "$line" >> "$TMPSCRIPT"
    fi
done < "$BATS_FILE"

# Verify syntax of generated script
if ! bash -n "$TMPSCRIPT" 2>/dev/null; then
    echo "ERROR: Generated test script has syntax errors"
    bash -n "$TMPSCRIPT" 2>&1 | head -10
    exit 1
fi

# Step 2: Run each test function
for i in "${!TEST_NAMES[@]}"; do
    test_idx=$((i + 1))
    test_name="${TEST_NAMES[$i]}"

    result=$(
        source "$TMPSCRIPT" 2>/dev/null
        _BATS_SKIP=false
        setup 2>/dev/null
        "_bats_test_${test_idx}" 2>&1
        _test_rc=$?
        if [ "$_BATS_SKIP" = true ]; then
            echo "__BATS_SKIPPED__"
            exit 77
        fi
        teardown 2>/dev/null
        exit "$_test_rc"
    )
    exit_code=$?

    if [ $exit_code -eq 77 ] || echo "$result" | grep -q "__BATS_SKIPPED__"; then
        SKIP=$((SKIP + 1))
        $VERBOSE && echo -e "  ${YELLOW}[SKIP]${NC} $test_name"
    elif [ $exit_code -eq 0 ]; then
        PASS=$((PASS + 1))
        $VERBOSE && echo -e "  ${GREEN}[PASS]${NC} $test_name"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}[FAIL]${NC} $test_name"
        cleaned=$(echo "$result" | grep -v "__BATS_SKIPPED__" | head -3)
        [ -n "$cleaned" ] && echo "         $cleaned"
        ERRORS+="  - $test_name"$'\n'
    fi
done

echo ""
echo "═══════════════════════════════════════════"
total=$((PASS + FAIL + SKIP))
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} (${total} total)"
echo "═══════════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    echo "$ERRORS"
    exit 1
fi
exit 0
