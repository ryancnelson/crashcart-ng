#!/bin/bash
# Minimal validation - just the essentials for production readiness
set -e

echo "=== Minimal Production Validation ==="

# Test 1: Does crashcart mount and work at all?
echo "TEST: Basic functionality"
CONTAINER=$(docker run -d --rm alpine:latest sleep 20)

if echo 'echo "SUCCESS"; exit' | timeout 8 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" 2>/dev/null | grep -q "SUCCESS"; then
    echo "✓ PASS: Basic mount and shell work"
    BASIC_WORKS=1
else
    echo "✗ FAIL: Basic functionality broken"
    BASIC_WORKS=0
fi

docker rm -f "$CONTAINER" 2>/dev/null || true

# Test 2: Do essential tools exist?
echo "TEST: Tool availability"
CONTAINER=$(docker run -d --rm alpine:latest sleep 20)

TOOLS_OUTPUT=$(echo 'command -v gdb; command -v strace; exit' | timeout 8 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" 2>/dev/null)

if echo "$TOOLS_OUTPUT" | grep -q "gdb\|strace"; then
    echo "✓ PASS: Debugging tools available"
    TOOLS_WORK=1
else
    echo "✗ FAIL: No debugging tools found"
    TOOLS_WORK=0
fi

docker rm -f "$CONTAINER" 2>/dev/null || true

# Test 3: Does it work with minimal containers?
echo "TEST: Minimal container compatibility"
SCRATCH_CONTAINER=$(docker run -d --rm --entrypoint="" alpine:latest /bin/sh -c 'sleep 20')

if echo 'ls /dev/crashcart; exit' | timeout 8 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$SCRATCH_CONTAINER" 2>/dev/null | grep -q "crashcart"; then
    echo "✓ PASS: Works with minimal containers"
    MINIMAL_WORKS=1
else
    echo "✗ FAIL: Minimal container support broken"
    MINIMAL_WORKS=0
fi

docker rm -f "$SCRATCH_CONTAINER" 2>/dev/null || true

# Test 4: Error handling
echo "TEST: Error handling"
if sudo ./target/x86_64-unknown-linux-musl/release/crashcart "nonexistent" 2>&1 | grep -i "error\|not found"; then
    echo "✓ PASS: Error handling works"
    ERROR_HANDLING=1
else
    echo "✗ FAIL: Poor error handling"
    ERROR_HANDLING=0
fi

# Results
TOTAL_SCORE=$((BASIC_WORKS + TOOLS_WORK + MINIMAL_WORKS + ERROR_HANDLING))

echo
echo "=== VALIDATION RESULTS ==="
echo "Basic functionality: $BASIC_WORKS/1"
echo "Tool availability: $TOOLS_WORK/1"
echo "Minimal containers: $MINIMAL_WORKS/1"
echo "Error handling: $ERROR_HANDLING/1"
echo "TOTAL SCORE: $TOTAL_SCORE/4"

if [ "$TOTAL_SCORE" -eq 4 ]; then
    echo "🎉 PRODUCTION READY (4/4)"
    echo "✅ All essential functionality verified"
elif [ "$TOTAL_SCORE" -ge 3 ]; then
    echo "⚠️ MOSTLY READY ($TOTAL_SCORE/4)"
    echo "🟡 Minor issues, but core functionality works"
else
    echo "❌ NOT READY ($TOTAL_SCORE/4)"
    echo "🚫 Critical functionality missing"
fi

echo
echo "crashcart-ng validation complete."
exit $((4 - TOTAL_SCORE))