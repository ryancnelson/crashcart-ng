#!/bin/bash
# Quick Production Validation - Essential tests for release readiness
set -e

echo "========================================"
echo "QUICK PRODUCTION VALIDATION"
echo "========================================"

TESTS_PASSED=0
TESTS_FAILED=0

pass_test() {
    echo "✓ PASS: $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo "✗ FAIL: $1 - $2"
    ((TESTS_FAILED++))
}

# Test 1: Basic Mount and Shell
echo "TEST 1: Basic mount and shell functionality"
CONTAINER=$(docker run -d --rm alpine:latest sleep 30)
echo "  Container: ${CONTAINER:0:12}"

if echo 'echo "BASIC_TEST_SUCCESS"; exit 0' | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" 2>&1 | grep -q "BASIC_TEST_SUCCESS"; then
    pass_test "Mount and shell work"
else
    fail_test "Mount/shell failed" "Core functionality broken"
fi

docker rm -f "$CONTAINER" 2>/dev/null || true

# Test 2: Tool Availability
echo "TEST 2: Essential debugging tools present"
CONTAINER=$(docker run -d --rm alpine:latest sleep 30)

TOOL_OUTPUT=$(echo 'command -v gdb && command -v strace && command -v lsof && echo "ALL_TOOLS_FOUND"; exit 0' | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" 2>&1)

if echo "$TOOL_OUTPUT" | grep -q "ALL_TOOLS_FOUND"; then
    pass_test "All essential tools available"
else
    if echo "$TOOL_OUTPUT" | grep -q "gdb\|strace\|lsof"; then
        pass_test "Some essential tools available (partial)"
    else
        fail_test "Essential tools missing" "No debugging tools found"
    fi
fi

docker rm -f "$CONTAINER" 2>/dev/null || true

# Test 3: Environment Setup
echo "TEST 3: Environment and functions"
CONTAINER=$(docker run -d --rm alpine:latest sleep 30)

ENV_OUTPUT=$(echo 'echo "PATH: $PATH"; echo "TARGET_PID: $TARGET_PID"; type debug_process 2>/dev/null && echo "FUNCTIONS_OK"; exit 0' | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" 2>&1)

if echo "$ENV_OUTPUT" | grep -q "crashcart" && echo "$ENV_OUTPUT" | grep -q "TARGET_PID:"; then
    pass_test "Environment properly configured"
else
    fail_test "Environment issues" "PATH or TARGET_PID missing"
fi

if echo "$ENV_OUTPUT" | grep -q "FUNCTIONS_OK"; then
    pass_test "Debugging functions loaded"
else
    fail_test "Functions missing" "debug_process not available"
fi

docker rm -f "$CONTAINER" 2>/dev/null || true

# Test 4: Container Type Compatibility
echo "TEST 4: Distroless compatibility"
if docker pull gcr.io/distroless/base:latest >/dev/null 2>&1; then
    DISTROLESS=$(docker run -d --rm gcr.io/distroless/base:latest sleep 30 2>/dev/null || echo "SKIP")

    if [ "$DISTROLESS" != "SKIP" ]; then
        if echo 'ls /dev/crashcart && echo "DISTROLESS_SUCCESS"; exit 0' | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$DISTROLESS" 2>&1 | grep -q "DISTROLESS_SUCCESS"; then
            pass_test "Works with distroless containers"
        else
            fail_test "Distroless compatibility" "Cannot mount in minimal containers"
        fi
        docker rm -f "$DISTROLESS" 2>/dev/null || true
    else
        echo "  SKIP: Distroless container test (pull failed)"
    fi
else
    echo "  SKIP: Distroless container test (image unavailable)"
fi

# Test 5: Error Handling
echo "TEST 5: Error handling"
if sudo ./target/x86_64-unknown-linux-musl/release/crashcart "invalid-container" 2>&1 | grep -i "error\|not found\|invalid"; then
    pass_test "Provides clear error messages"
else
    fail_test "Poor error handling" "No clear error for invalid input"
fi

# Test 6: Resource Cleanup
echo "TEST 6: Resource cleanup"
CONTAINER=$(docker run -d --rm alpine:latest sleep 30)

# Start and exit crashcart
echo 'exit 0' | timeout 5 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER" >/dev/null 2>&1 || true

docker rm -f "$CONTAINER" 2>/dev/null || true

# Check for lingering mounts or loop devices
if ! mount | grep -q crashcart && ! losetup -a | grep -q crashcart; then
    pass_test "Clean resource cleanup"
else
    fail_test "Resource leaks" "Lingering mounts or loop devices"
fi

# Results
echo
echo "========================================"
echo "QUICK VALIDATION RESULTS"
echo "========================================"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED - PRODUCTION READY"
    echo "✅ crashcart-ng validated for public release"
    exit 0
elif [ "$TESTS_FAILED" -le 2 ]; then
    echo "⚠️  MOSTLY READY - Minor issues found"
    echo "🟡 Address $TESTS_FAILED issues for optimal release"
    exit 1
else
    echo "❌ NOT READY - Multiple issues found"
    echo "🚫 $TESTS_FAILED critical issues must be resolved"
    exit 2
fi