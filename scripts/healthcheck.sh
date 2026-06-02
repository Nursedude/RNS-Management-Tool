#!/bin/bash
# RNS-Management-Tool healthcheck — would CI be green right now?
#
# Mirrors CI's shellcheck + smoke-test invocation. Born from the
# 2026-05-03 ecosystem audit pattern: prod runs fine, repo CI rots
# invisibly. This repo is shell-heavy (rns_management_tool.sh entry
# point + scripts/).
#
# Usage: scripts/healthcheck.sh
# Exit: 0 ok / 1 lint / 2 smoke

set -u
cd "$(dirname "$0")/.." || exit 1

print_ok()   { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
print_fail() { printf "\033[1;31m✗\033[0m %s\n" "$1"; }
print_step() { printf "\n\033[1;36m=== %s ===\033[0m\n" "$1"; }

RC=0

print_step "bash -n (syntax)"
for f in rns_management_tool.sh scripts/*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f"; then
        print_fail "syntax error: $f"
        RC=1
    fi
done
[ "$RC" -eq 0 ] && print_ok "all shell files parse"

if command -v shellcheck >/dev/null 2>&1; then
    print_step "shellcheck"
    if ! shellcheck -x -S warning rns_management_tool.sh; then
        print_fail "shellcheck warnings on entry point"
        RC=1
    fi
    for f in scripts/*.sh modules/*.sh; do
        [ -f "$f" ] || continue
        shellcheck -x -S warning "$f" || RC=1
    done
    [ "$RC" -eq 0 ] && print_ok "shellcheck clean"
else
    print_fail "shellcheck not installed (apt install shellcheck)"
fi

if [ -x "scripts/lint.sh" ]; then
    print_step "scripts/lint.sh"
    if scripts/lint.sh; then
        print_ok "lint.sh clean"
    else
        print_fail "lint.sh failed"
        RC=1
    fi
fi

print_step "Summary"
[ "$RC" -eq 0 ] && print_ok "All checks passed" || print_fail "Failures detected"
exit "$RC"
