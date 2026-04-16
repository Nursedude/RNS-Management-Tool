Run the RNS Management Tool test suite.

```bash
# Syntax check all bash files
bash -n rns_management_tool.sh
for f in lib/*.sh; do bash -n "$f"; done

# Run --check mode
bash rns_management_tool.sh --check

# Custom linter (RNS001-RNS010)
bash scripts/lint.sh

# Smoke tests
bash tests/smoke_test.sh --verbose

# BATS test suites
bash tests/run_bats_compat.sh tests/rns_management_tool.bats
bash tests/run_bats_compat.sh tests/regression_guards.bats
bash tests/run_bats_compat.sh tests/integration_tests.bats
bash tests/run_bats_compat.sh tests/hardware_validation.bats
bash tests/run_bats_compat.sh tests/functional_tests.bats
```

Report pass/fail counts and any failures. If any test fails, investigate the
root cause and fix it before reporting success.
