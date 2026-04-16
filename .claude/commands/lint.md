Run the RNS Management Tool linter and static analysis.

```bash
# Custom linter (RNS001-RNS010)
bash scripts/lint.sh

# ShellCheck (if available)
if command -v shellcheck &>/dev/null; then
  shellcheck -x -S warning rns_management_tool.sh
  for f in lib/*.sh; do shellcheck -x -S warning "$f"; done
fi
```

Report all warnings and errors. For any issues found:
1. Identify whether each is a real issue or false positive
2. Fix real issues
3. If a false positive, explain why and consider updating the linter
