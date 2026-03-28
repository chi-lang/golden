#!/bin/bash
# test_standalone.sh — Run golden tests in standalone mode
#
# For each golden test:
#   1. Compile with: chi compile --bundle program.chi -o /tmp/program.lua
#   2. Run with: luajit /tmp/program.lua
#   3. Compare output with .expected
#
# Skips tests that use chi_compile/eval (incompatible with standalone).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GOLDEN_DIR="$SCRIPT_DIR"

CHI="${CHI:-chi}"
LUAJIT="${LUAJIT:-luajit}"

# Verify prerequisites
for cmd in "$CHI" "$LUAJIT"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "ERROR: $cmd not found on PATH"
        exit 1
    fi
done

PASS=0
FAIL=0
SKIP=0
ERRORS=""

# Determine which tests to run
if [ $# -gt 0 ]; then
    FILTER="$1"
    FILTER="${FILTER%.chi}"
    CHI_FILES=$(find "$GOLDEN_DIR" -name "*.chi" -path "*${FILTER}*" | sort)
else
    CHI_FILES=$(find "$GOLDEN_DIR" -name "*.chi" | sort)
fi

for chi_file in $CHI_FILES; do
    rel="${chi_file#$GOLDEN_DIR/}"
    expected="${chi_file%.chi}.expected"

    [ -f "$expected" ] || continue

    # Skip tests that use chi_compile/eval (incompatible with standalone)
    if grep -qE '(compileLua|eval\s*\()' "$chi_file" 2>/dev/null; then
        printf "  \033[33mSKIP\033[0m   %s (uses compile/eval)\n" "$rel"
        SKIP=$((SKIP+1))
        continue
    fi

    # Compile to bundled Lua (use temp files to avoid subshell capture issues with JVM)
    tmp_lua=$(mktemp /tmp/chi_standalone_XXXXXX.lua)
    tmp_out=$(mktemp /tmp/chi_standalone_out_XXXXXX.txt)
    "$CHI" compile --bundle "$chi_file" -o "$tmp_lua" > "$tmp_out" 2>/dev/null || true

    # Check if compilation produced a valid bundle
    if ! head -1 "$tmp_lua" 2>/dev/null | grep -q "^-- Chi standalone bundle"; then
        # Compilation failed — check if the expected output matches the error
        compile_stdout=$(cat "$tmp_out")
        rm -f "$tmp_lua" "$tmp_out"
        expected_content=$(cat "$expected")
        if [ "$compile_stdout" = "$expected_content" ]; then
            printf "  \033[32mPASS\033[0m   %s (compile error matched)\n" "$rel"
            PASS=$((PASS+1))
        else
            printf "  \033[31mERROR\033[0m  %s (compilation failed)\n" "$rel"
            printf "    Compile output:\n"
            echo "$compile_stdout" | head -5 | sed 's/^/      /'
            FAIL=$((FAIL+1))
            ERRORS="${ERRORS}  ${rel}\n"
        fi
        continue
    fi
    rm -f "$tmp_out"

    # Run on standalone LuaJIT
    output=$("$LUAJIT" "$tmp_lua" 2>/dev/null) || true
    rm -f "$tmp_lua"

    # Compare with expected
    expected_content=$(cat "$expected")
    if [ "$output" = "$expected_content" ]; then
        printf "  \033[32mPASS\033[0m   %s\n" "$rel"
        PASS=$((PASS+1))
    else
        printf "  \033[31mFAIL\033[0m   %s\n" "$rel"
        printf "    Expected:\n"
        echo "$expected_content" | head -5 | sed 's/^/      /'
        printf "    Got:\n"
        echo "$output" | head -5 | sed 's/^/      /'
        FAIL=$((FAIL+1))
        ERRORS="${ERRORS}  ${rel}\n"
    fi
done

echo ""
if [ $FAIL -eq 0 ]; then
    printf "\033[32m%d passed\033[0m" $PASS
else
    printf "\033[32m%d passed\033[0m, \033[31m%d failed\033[0m" $PASS $FAIL
fi
[ $SKIP -gt 0 ] && printf ", %d skipped" $SKIP
echo "  (standalone: chi compile --bundle + luajit)"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    printf "$ERRORS"
    exit 1
fi
