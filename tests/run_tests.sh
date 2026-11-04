#!/usr/bin/env bash
# PCMod test runner.
#
# Rebuilds the translated Lua 5.1 fixtures from the current addon sources,
# syntax-checks them, then runs every mock_*.lua suite. Safe for CI and manual
# use: it never touches the real addon files (only tests/.build/).
#
# Usage:
#   ./run_tests.sh              run everything
#   ./run_tests.sh mock_fs      run a single suite by name (without .lua)
#
# Exit codes: 0 = all passed, 1 = build failed, 2 = a suite failed,
#             3 = missing dependency.
set -u

cd "$(dirname "$0")" || exit 1

C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

# --- dependencies -----------------------------------------------------------
for dep in python3 luac5.1 lua5.1; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Missing dependency: ${dep} (install Lua 5.1 + Python 3)" >&2
        exit 3
    fi
done

# --- build fixtures (also compile-checks every listed source) ---------------
echo "${C_BOLD}== Building translated fixtures and syntax-checking sources ==${C_RESET}"
if ! python3 lib/build_fixtures.py; then
    echo "${C_RED}Fixture build / syntax check failed.${C_RESET}" >&2
    exit 1
fi

TESTS=(
    mock_fs
    mock_notepad
    mock_notepad_ui
    mock_files
    mock_files_ui
    mock_open_ui
    mock_ipv6
    mock_entity_ipv6
    mock_router
    mock_bios
    mock_network
    mock_dhcp
    mock_leases
    mock_routing
    mock_wiring
    mock_windows
    mock_mycomp
    mock_mycomp_prog
    mock_ui_scale
    mock_hackyclicky
    mock_elements
)

# Allow narrowing to a single suite: ./run_tests.sh mock_fs
if [ "$#" -gt 0 ]; then
    TESTS=( "$@" )
fi

run_suite() {
    # Lua 5.1 everywhere; use `timeout` only when it exists (it is not POSIX).
    if command -v timeout >/dev/null 2>&1; then
        (cd .build && timeout 30 lua5.1 "$1")
    else
        (cd .build && lua5.1 "$1")
    fi
}

echo "${C_BOLD}== Running ${#TESTS[@]} test suite(s) ==${C_RESET}"

pass=0
fail=0
failed_names=()

for t in "${TESTS[@]}"; do
    name="${t%.lua}"
    printf '%-24s' "$name"
    output="$(run_suite "${name}.lua" 2>&1)"
    if [ $? -eq 0 ]; then
        printf "${C_GREEN}PASS${C_RESET}\n"
        pass=$((pass + 1))
    else
        printf "${C_RED}FAIL${C_RESET}\n"
        fail=$((fail + 1))
        failed_names+=("$name")
        printf '%s\n' "$output" | sed 's/^/    /'
    fi
done

echo
echo "Passed: ${pass}   Failed: ${fail}"
if [ "$fail" -ne 0 ]; then
    printf 'Failed suites: %s\n' "${failed_names[*]}" >&2
    exit 2
fi
echo "${C_GREEN}${C_BOLD}All PCMod test suites passed.${C_RESET}"