# RNS Management Tool — Persistent Issues & Resolution Patterns

> **Purpose**: Document recurring issues and their proper fixes to prevent regression.
> This serves as institutional memory for development.
> Adapted from meshforge `.claude/foundations/persistent_issues.md` pattern.
>
> **Last audited**: 2026-02-25 (v0.3.5-beta)

---

## Active Issues

### PI-001: RNODE Not Detected on Linux

| Field | Value |
|-------|-------|
| **Platform** | Linux (all distros) |
| **Symptom** | RNODE device connected but `/dev/ttyUSB*` not accessible |
| **Root Cause** | User not in `dialout` group — serial devices require group membership |
| **Fix** | `sudo usermod -aG dialout $USER` then **logout/login** (group change requires new session) |
| **Code Location** | `scripts/verify_install.sh` checks this; `lib/rnode.sh` prompts for device port |
| **Regression Guard** | `tests/regression_guards.bats` — RNS002 device port validation tests |
| **Status** | **Active** — cannot auto-fix (requires logout) |

### PI-002: rnsd Won't Start

| Field | Value |
|-------|-------|
| **Platform** | All |
| **Symptom** | `rnsd --daemon` exits immediately or errors |
| **Root Cause** | Missing `~/.reticulum/config` file (never created or deleted) |
| **Fix** | Run `rnsd` once — it auto-creates default config. Or use config templates (menu option 9) |
| **Code Location** | `lib/diagnostics.sh:diag_check_configuration()` checks for config existence |
| **Regression Guard** | `tests/integration_tests.bats` — diagnostics tests |
| **Status** | **Active** — by design (first-run creates config) |

### PI-003: MeshChat Build Fails

| Field | Value |
|-------|-------|
| **Platform** | All |
| **Symptom** | `npm install` or `npm run build` fails during MeshChat installation |
| **Root Cause** | Node.js version too old — MeshChat requires Node 18+, many systems ship 12-16 |
| **Fix** | Script auto-upgrades to Node.js 22 LTS via NodeSource when version is < 18 |
| **Code Location** | `lib/install.sh:install_meshchat()` — checks node version, installs NodeSource if needed |
| **Regression Guard** | `tests/rns_management_tool.bats` — MeshChat installation pattern tests |
| **Status** | **Mitigated** — auto-upgrade handles most cases |

### PI-004: Permission Denied Running Script

| Field | Value |
|-------|-------|
| **Platform** | Linux |
| **Symptom** | `bash: ./rns_management_tool.sh: Permission denied` |
| **Root Cause** | Execute bit not set after git clone (some git configs strip permissions) |
| **Fix** | `chmod +x rns_management_tool.sh` |
| **Code Location** | README.md quickstart instructions include this step |
| **Regression Guard** | `.github/workflows/lint.yml` — `check-mode` job verifies script is executable by bash |
| **Status** | **Active** — user action required |

### PI-005: pip Externally-Managed Error (PEP 668)

| Field | Value |
|-------|-------|
| **Platform** | Debian 12+ (Bookworm), Raspberry Pi OS (latest) |
| **Symptom** | `pip install` errors with "externally-managed-environment" |
| **Root Cause** | PEP 668 restricts system-wide pip installs to prevent conflicts with apt packages |
| **Fix** | Script auto-detects PEP 668 and adds `--break-system-packages` flag to pip commands |
| **Code Location** | `lib/utils.sh:detect_environment()` sets `PEP668_DETECTED=true`; `lib/install.sh` uses it |
| **Regression Guard** | `tests/integration_tests.bats` — PLATFORM section checks PEP668 detection |
| **Status** | **Mitigated** — auto-detected and handled |

---

## Resolution History

| Date | Issue | Resolution |
|------|-------|------------|
| 2026-02-25 | Validation scattered across modules | Created `lib/validation.sh` — centralized validation (RNS002-RNS004) |
| 2026-02-25 | CI jobs could hang indefinitely | Added `timeout-minutes` to all 7 CI jobs |
| 2026-02-25 | No pre-commit enforcement | Created `.githooks/pre-commit` — linter + syntax on commit |
| 2026-02-25 | No regression guard tests | Created `tests/regression_guards.bats` — architectural invariant tests |
| 2026-02-21 | Security review completed | Full OWASP-style review — Rating: A (see SECURITY_REVIEW.md) |

---

## How to Add a New Issue

1. Assign the next PI-XXX number
2. Fill in all fields: Platform, Symptom, Root Cause, Fix, Code Location
3. Add a regression guard test in `tests/regression_guards.bats`
4. Reference the regression guard in the issue entry
5. Set status: Active, Mitigated, or Fixed

---

*Made with care for the Reticulum community*
