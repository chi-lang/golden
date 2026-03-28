#!/bin/bash
# test_dual.sh — Dual execution test for Chi golden programs
#
# Runs each golden test program in two ways and compares output:
#   1. JVM mode:        chi program.chi
#   2. Standalone mode: luajit with chi_runtime.lua + stdlib
#
# Programs that use chi_compile/eval/compileLua are skipped in standalone mode.
#
# Usage:
#   ./test_dual.sh                  — run all tests
#   ./test_dual.sh strings/basic    — run specific test
#
# Requires: chi on PATH, luajit on PATH, CHI_HOME set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GOLDEN_DIR="$SCRIPT_DIR"

CHI="${CHI:-chi}"
LUAJIT="${LUAJIT:-luajit}"

# Locate runtime files
RUNTIME_LUA="${RUNTIME_LUA:-$(dirname "$SCRIPT_DIR")/compiler/src/main/resources/chi_runtime.lua}"
UTF8_LUA="${UTF8_LUA:-$(dirname "$SCRIPT_DIR")/compiler/src/main/resources/utf8.lua}"
CHISTR_LUA="${CHISTR_LUA:-$(dirname "$SCRIPT_DIR")/compiler/src/main/resources/chistr.lua}"
STDLIB_CHIM="${STDLIB_CHIM:-$(dirname "$SCRIPT_DIR")/stdlib/std.chim}"

# Verify prerequisites
for cmd in "$CHI" "$LUAJIT"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "ERROR: $cmd not found on PATH"
        exit 1
    fi
done

for f in "$RUNTIME_LUA" "$UTF8_LUA" "$CHISTR_LUA" "$STDLIB_CHIM"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Required file not found: $f"
        exit 1
    fi
done

# Programs that use chi_compile/eval (incompatible with standalone)
STANDALONE_SKIP_PATTERNS=()

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

    # Check if test uses chi_compile/eval (incompatible with standalone)
    skip=false
    if grep -qE '(compileLua|eval\s*\()' "$chi_file" 2>/dev/null; then
        skip=true
    fi

    if [ "$skip" = true ]; then
        printf "  \033[33mSKIP\033[0m   %s (uses compile/eval)\n" "$rel"
        SKIP=$((SKIP+1))
        continue
    fi

    # Mode 1: JVM execution
    output_jvm=$("$CHI" "$chi_file" 2>/dev/null) || true

    # Mode 2: Get Lua code from chi -l, then run standalone
    lua_code=$("$CHI" -l "$chi_file" 2>/dev/null) || true

    if [ -z "$lua_code" ]; then
        printf "  \033[31mERROR\033[0m  %s (failed to compile)\n" "$rel"
        FAIL=$((FAIL+1))
        continue
    fi

    # Skip compile-error tests: chi -l outputs error text (not Lua code)
    if ! echo "$lua_code" | head -1 | grep -q '^local '; then
        printf "  \033[33mSKIP\033[0m   %s (compile error test)\n" "$rel"
        SKIP=$((SKIP+1))
        continue
    fi

    # Create a temporary Lua file that loads runtime + stdlib + program
    tmp_lua=$(mktemp /tmp/chi_dual_XXXXXX.lua)
    cat > "$tmp_lua" <<LUAEOF
-- Load UTF-8 support
utf8 = (function()
$(cat "$UTF8_LUA")
end)()

-- Load chistr
chistr = (function()
$(cat "$CHISTR_LUA")
end)()

-- Load runtime
dofile("$RUNTIME_LUA")

-- Load stdlib
$(cat "$STDLIB_CHIM")

-- Run program
$lua_code
LUAEOF

    output_lua=$("$LUAJIT" "$tmp_lua" 2>/dev/null) || true
    rm -f "$tmp_lua"

    # Compare outputs
    if [ "$output_jvm" = "$output_lua" ]; then
        printf "  \033[32mPASS\033[0m   %s\n" "$rel"
        PASS=$((PASS+1))
    else
        printf "  \033[31mFAIL\033[0m   %s\n" "$rel"
        printf "    JVM output:\n"
        echo "$output_jvm" | head -5 | sed 's/^/      /'
        printf "    LuaJIT output:\n"
        echo "$output_lua" | head -5 | sed 's/^/      /'
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
echo "  (dual: chi + luajit)"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    printf "$ERRORS"
    exit 1
fi
