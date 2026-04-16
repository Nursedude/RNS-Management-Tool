Run a security and code quality review of changed files.

1. Identify what changed:
```bash
git diff --name-only HEAD~1..HEAD 2>/dev/null || git diff --name-only
```

2. Run the linter on changed files:
```bash
bash scripts/lint.sh
```

3. For each changed .sh file, check:
   - RNS001: No eval usage
   - RNS002: Device port validation on rnodeconf calls
   - RNS003: Numeric range validation for radio parameters
   - RNS004: Path traversal prevention in import/export
   - RNS005: Confirmation before destructive actions
   - RNS006: Timeout wrappers on network commands
   - RNS007: cd with error handling
   - RNS008: Centralized service detection (no raw pgrep)
   - RNS009: mktemp for temp files (no hardcoded /tmp)
   - RNS010: No sensitive data in logs

4. Report findings as: Critical / Warnings / Suggestions / What's Good
