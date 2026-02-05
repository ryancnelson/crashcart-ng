#!/bin/bash
# Master test runner for crashcart-ng comprehensive testing
set -e

echo "========================================"
echo "CRASHCART-NG COMPREHENSIVE TEST SUITE"
echo "========================================"
echo "Production-ready testing for public release"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASSED=0
TOTAL_FAILED=0
SUITE_COUNT=0

run_test_suite() {
    local suite_name="$1"
    local test_script="$2"

    echo "========================================"
    echo "RUNNING: $suite_name"
    echo "========================================"

    if [ ! -f "$test_script" ]; then
        echo "✗ TEST SUITE MISSING: $test_script"
        ((TOTAL_FAILED++))
        return 1
    fi

    if [ ! -x "$test_script" ]; then
        echo "✗ TEST SUITE NOT EXECUTABLE: $test_script"
        ((TOTAL_FAILED++))
        return 1
    fi

    ((SUITE_COUNT++))

    if "$test_script"; then
        echo "✓ $suite_name: PASSED"
        ((TOTAL_PASSED++))
    else
        echo "✗ $suite_name: FAILED"
        ((TOTAL_FAILED++))
    fi

    echo
}

# Pre-flight checks
echo "========================================"
echo "PRE-FLIGHT CHECKS"
echo "========================================"

# Check crashcart binary exists
if [ ! -f "./target/x86_64-unknown-linux-musl/release/crashcart" ]; then
    echo "✗ CRITICAL: crashcart binary not found"
    echo "  Run: cargo build --release --target x86_64-unknown-linux-musl"
    exit 1
fi

echo "✓ Crashcart binary found"

# Check Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "✗ CRITICAL: Docker not available"
    exit 1
fi

echo "✓ Docker available"

# Check sudo access
if ! sudo -n true 2>/dev/null; then
    echo "✗ CRITICAL: sudo access required for crashcart"
    exit 1
fi

echo "✓ Sudo access available"

# Check crashcart image exists
if [ ! -f "./crashcart.img" ]; then
    echo "✗ CRITICAL: crashcart.img not found"
    echo "  Run: ./build-image-musl.sh"
    exit 1
fi

echo "✓ Crashcart image found"
echo

# Run test suites in priority order
echo "Starting comprehensive test execution..."
echo

# A) Command Validation Testing - Every example must work
run_test_suite "A1. Basic Functionality" "$SCRIPT_DIR/command-validation/test-basic-functionality.sh"
run_test_suite "A2. Command Validation" "$SCRIPT_DIR/command-validation/test-all-examples.sh"

# B) Real Environment Testing - Different containers/hosts
run_test_suite "B. Container Types" "$SCRIPT_DIR/environment-testing/test-container-types.sh"

# C) End-to-End Workflow Testing - Complete debugging journeys
run_test_suite "C1. Production Workflows" "$SCRIPT_DIR/workflow-testing/test-production-scenarios.sh"
run_test_suite "C2. Crisis Scenarios" "$SCRIPT_DIR/production-testing/test-crisis-scenarios.sh"

# D) Instruction Verification Testing - User experience
run_test_suite "D. Documentation Verification" "$SCRIPT_DIR/instruction-testing/test-documentation.sh"

# E) Edge Case and Failure Mode Testing
run_test_suite "E. Edge Cases & Failures" "$SCRIPT_DIR/failure-testing/test-edge-cases.sh"

# Final results
echo "========================================"
echo "COMPREHENSIVE TEST RESULTS"
echo "========================================"
echo "Test suites run: $SUITE_COUNT"
echo "Suites passed: $TOTAL_PASSED"
echo "Suites failed: $TOTAL_FAILED"
echo

if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo "🎉 ALL TEST SUITES PASSED"
    echo "✅ crashcart-ng is PRODUCTION READY for release"
    echo
    echo "Ready for:"
    echo "  - Public GitHub release"
    echo "  - Documentation updates"
    echo "  - Production deployment"
else
    echo "❌ $TOTAL_FAILED TEST SUITE(S) FAILED"
    echo "🚫 crashcart-ng is NOT ready for production release"
    echo
    echo "Issues must be resolved before release:"
    echo "  - Fix failing test suites"
    echo "  - Verify all functionality"
    echo "  - Ensure user experience quality"
fi

echo
echo "========================================"

exit $TOTAL_FAILED