#!/usr/bin/env bash
# Regenerate the rough line/file counts reported in CLAUDE.md "Project Metrics".
# Output is intentionally informal — numbers drift with every commit.

set -euo pipefail
cd "$(dirname "$0")/.."

count_lines() { wc -l "$@" 2>/dev/null | awk 'END { print $1 }'; }

bash_lines=$(count_lines rns_management_tool.sh lib/*.sh)
ps_lines=$(count_lines rns_management_tool.ps1 pwsh/*.ps1)
test_lines=$(count_lines tests/*.bats tests/*.sh tests/*.ps1)
bash_fn_count=$(grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{' rns_management_tool.sh lib/*.sh | wc -l)

printf 'Bash:       %s lines (main + lib/)\n' "$bash_lines"
printf 'PowerShell: %s lines (main + pwsh/)\n' "$ps_lines"
printf 'Tests:      %s lines (tests/)\n' "$test_lines"
printf 'Functions:  %s (bash)\n' "$bash_fn_count"
