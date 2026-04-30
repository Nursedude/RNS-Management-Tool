# Security Policy

## Supported Versions

Active development is on the `0.4.x-beta` line. Only the current minor receives
security fixes; older betas should be upgraded.

| Version       | Supported          |
| ------------- | ------------------ |
| 0.4.x-beta    | :white_check_mark: |
| < 0.4         | :x:                |

## Reporting a Vulnerability

If you find a security issue, please report it privately:

- **Email:** shawnmfarley@gmail.com
- **Response SLA:** initial acknowledgement within 48 hours
- **Coordinated disclosure:** please give us a reasonable window to ship a fix
  before public disclosure (typical: 30 days, negotiable for critical issues
  affecting the live mesh)

What helps:

- Description of the issue and the impact you observed
- Reproduction steps (commands, inputs, the file you ran against)
- Affected version (`./rns_management_tool.sh --version` or git SHA)
- Whether you've already shared it with anyone else

Please **do not** open a public GitHub issue for unfixed security problems.

## Security Measures

The codebase enforces a small set of hard rules via the custom linter
(`scripts/lint.sh`) and a multi-stage pre-commit hook (`.githooks/pre-commit`).
Each rule is encoded so that a future contributor can't silently re-introduce a
known-bad pattern.

| Rule    | Requirement                                                   | Enforced by                                |
| ------- | ------------------------------------------------------------- | ------------------------------------------ |
| RNS001  | No `eval`; use array-based command execution                  | `scripts/lint.sh`, `tests/regression_guards.bats` |
| RNS002  | All device ports validated before subprocess use              | `lib/validation.sh::validate_device_port`, linter |
| RNS003  | Numeric range validation on radio parameters                  | `lib/validation.sh`, linter                |
| RNS004  | Path traversal prevention in import/export                    | `lib/validation.sh`, linter                |
| RNS005  | Confirmation required for destructive actions                 | `confirm_action()`; linter scans for `rm -rf` without prompt |
| RNS006  | Subprocess timeout protection                                 | `run_with_timeout` / `retry_with_backoff` in `lib/utils.sh` |
| RNS007  | `cd` always uses error handling (`cd ... \|\| return 1`)      | `scripts/lint.sh`                          |
| RNS008  | No direct `pgrep` outside centralized service detection       | `lib/utils.sh::check_service_status`, linter |
| RNS009  | Temp files use `mktemp` / `${TMPDIR:-/tmp}`, not hardcoded `/tmp` | `scripts/lint.sh`                       |
| RNS010  | No sensitive data (passwords, tokens, keys) in log output     | `scripts/lint.sh`                          |
| RNS011  | No hardcoded `/home/<user>/` paths in tracked files           | `scripts/lint.sh` (adapted from meshforge MF014) |

Additional gates (in `.githooks/pre-commit`):

1. Bash syntax check on every staged `.sh` file
2. Custom linter (`RNS001`–`RNS011`) on staged files
3. Private-key detection — blocks PEM-encoded keys and Reticulum identity files
4. Large-file warning (>1 MB)
5. ShellCheck (when installed)
6. JSON validation for staged `.claude/*.json` files — prevents a malformed
   settings file from silently disabling Claude Code permission gates

To install the hook:

```bash
git config core.hooksPath .githooks
```

## Known Hardening Notes

- `curl -k` is used in a small number of places; every call site is restricted
  to `127.0.0.1` (see `lib/utils.sh::check_meshtasticd_http_api`,
  `lib/services.sh`). Comments at each site mark this as intentional.
- Atomic config writes go through `lib/utils.sh::write_atomic`, which preserves
  file mode and uses an `mktemp`+rename to survive crashes/power-loss.
- The retry helper (`lib/utils.sh::retry_with_backoff`) classifies errors as
  transient vs. permanent before retrying — permanent errors short-circuit so we
  don't burn time retrying a `ModuleNotFoundError`.

## Out of Scope

- Vulnerabilities in upstream Reticulum, NomadNet, MeshChat, or rnodeconf
  themselves — please report those to their respective projects.
- Denial-of-service issues that require root or local console access; this tool
  assumes a trusted operator on the host.

Thank you for helping keep the project safe.
