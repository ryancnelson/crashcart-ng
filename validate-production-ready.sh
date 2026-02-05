#!/bin/bash
# Production Readiness Validation Script
# Comprehensive validation for crashcart-ng public release

set -e

echo "========================================"
echo "CRASHCART-NG PRODUCTION READINESS CHECK"
echo "========================================"
echo "Validating all aspects for public release..."
echo

SUCCESS_COLOR='\033[0;32m'
ERROR_COLOR='\033[0;31m'
WARN_COLOR='\033[1;33m'
NC='\033[0m' # No Color

CHECKS_PASSED=0
CHECKS_FAILED=0
CRITICAL_FAILED=0

check_pass() {
    echo -e "  ${SUCCESS_COLOR}✓ PASS${NC}: $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "  ${ERROR_COLOR}✗ FAIL${NC}: $1"
    echo -e "    ${ERROR_COLOR}Error: $2${NC}"
    ((CHECKS_FAILED++))
    if [ "$3" = "critical" ]; then
        ((CRITICAL_FAILED++))
    fi
}

check_warn() {
    echo -e "  ${WARN_COLOR}⚠ WARN${NC}: $1"
    echo -e "    ${WARN_COLOR}Warning: $2${NC}"
}

# Pre-requisite checks
echo "========================================"
echo "PRE-REQUISITE VALIDATION"
echo "========================================"

echo "CHECK: Development environment"
if [ -f "target/x86_64-unknown-linux-musl/release/crashcart" ]; then
    check_pass "Crashcart binary exists"
else
    check_fail "Crashcart binary missing" "Run: cargo build --release --target x86_64-unknown-linux-musl" "critical"
fi

if [ -f "crashcart.img" ]; then
    check_pass "Crashcart image exists"
else
    check_fail "Crashcart image missing" "Run: ./build-image-musl.sh" "critical"
fi

if command -v docker >/dev/null 2>&1; then
    check_pass "Docker available"
else
    check_fail "Docker not available" "Docker required for testing" "critical"
fi

if sudo -n true 2>/dev/null; then
    check_pass "Sudo access available"
else
    check_fail "Sudo access required" "Crashcart needs sudo for container access" "critical"
fi

echo
echo "CHECK: Documentation completeness"
if [ -f "README.md" ]; then
    if grep -q "crashcart" README.md && grep -q "debug" README.md; then
        check_pass "README.md exists and mentions crashcart"
    else
        check_fail "README.md incomplete" "Missing essential content"
    fi
else
    check_fail "README.md missing" "Documentation required for release"
fi

if [ -f "tests/TEST_RESULTS.md" ]; then
    check_pass "Test documentation exists"
else
    check_warn "Test results documentation missing" "Should document test coverage"
fi

# Quick functionality validation
echo
echo "========================================"
echo "CORE FUNCTIONALITY VALIDATION"
echo "========================================"

echo "CHECK: Basic crashcart functionality"
TEMP_CONTAINER=$(docker run -d --rm alpine:latest sleep 30)
echo "  Testing with container: ${TEMP_CONTAINER:0:12}"

if echo 'echo "VALIDATION_SUCCESS"; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$TEMP_CONTAINER" >validation_test.log 2>&1; then
    if grep -q "VALIDATION_SUCCESS" validation_test.log; then
        check_pass "Basic mount and shell functionality works"
    else
        check_fail "Shell execution issues" "Command execution failed"
    fi
else
    check_fail "Mount or shell failed" "Core functionality broken" "critical"
fi

docker rm -f "$TEMP_CONTAINER" 2>/dev/null || true
rm -f validation_test.log

# Test suite validation
echo
echo "========================================"
echo "TEST INFRASTRUCTURE VALIDATION"
echo "========================================"

echo "CHECK: Test suite completeness"
test_files=(
    "tests/run-all-tests.sh"
    "tests/command-validation/test-basic-functionality.sh"
    "tests/environment-testing/test-container-types.sh"
    "tests/production-testing/test-crisis-scenarios.sh"
    "tests/failure-testing/test-edge-cases.sh"
    "tests/instruction-testing/test-documentation.sh"
)

missing_tests=""
for test_file in "${test_files[@]}"; do
    if [ -f "$test_file" ] && [ -x "$test_file" ]; then
        check_pass "$(basename "$test_file") exists and executable"
    else
        check_fail "Test missing: $test_file" "Test suite incomplete"
        missing_tests="$missing_tests $test_file"
    fi
done

if [ -z "$missing_tests" ]; then
    check_pass "Complete test suite available"
else
    check_fail "Incomplete test suite" "Missing: $missing_tests"
fi

# Quick test execution
echo
echo "CHECK: Test execution validation"
if ./tests/command-validation/test-basic-functionality.sh >/dev/null 2>&1; then
    check_pass "Basic functionality tests execute successfully"
else
    check_fail "Basic functionality tests failing" "Core functionality has issues" "critical"
fi

# Code quality checks
echo
echo "========================================"
echo "CODE QUALITY VALIDATION"
echo "========================================"

echo "CHECK: Git repository state"
if git status --porcelain | grep -q .; then
    check_warn "Uncommitted changes present" "Should commit all changes before release"
else
    check_pass "Git repository clean"
fi

if git log -1 --pretty=format:"%s" | grep -q "test\|fix\|feat"; then
    check_pass "Recent commits indicate active development"
else
    check_warn "Recent commit messages unclear" "Good commit messages help users"
fi

# Release preparation checks
echo
echo "========================================"
echo "RELEASE PREPARATION VALIDATION"
echo "========================================"

echo "CHECK: Version and release information"
if grep -q "v0\." target/x86_64-unknown-linux-musl/release/crashcart --version 2>/dev/null || ./target/x86_64-unknown-linux-musl/release/crashcart --version 2>&1 | grep -q "v0\|0\."; then
    check_pass "Version information available"
else
    check_warn "Version information unclear" "Should have clear version"
fi

if [ -f "CHANGELOG.md" ] || [ -f "HISTORY.md" ]; then
    check_pass "Change history documentation exists"
else
    check_warn "Change history missing" "Users appreciate changelog"
fi

# Security and safety checks
echo
echo "========================================"
echo "SECURITY & SAFETY VALIDATION"
echo "========================================"

echo "CHECK: Security considerations"
if grep -r "password\|secret\|key" . --exclude-dir=.git --exclude="*.md" | grep -v "password-i.ri\|test"; then
    check_warn "Potential secrets in code" "Review for hardcoded credentials"
else
    check_pass "No obvious secrets in codebase"
fi

if sudo ./target/x86_64-unknown-linux-musl/release/crashcart "nonexistent" 2>&1 | grep -i "error\|not found"; then
    check_pass "Error handling provides feedback"
else
    check_warn "Error handling unclear" "Users need clear error messages"
fi

# Final assessment
echo
echo "========================================"
echo "PRODUCTION READINESS ASSESSMENT"
echo "========================================"

echo "Validation Summary:"
echo "  Checks passed: $CHECKS_PASSED"
echo "  Checks failed: $CHECKS_FAILED"
echo "  Critical failures: $CRITICAL_FAILED"
echo

if [ "$CRITICAL_FAILED" -eq 0 ]; then
    if [ "$CHECKS_FAILED" -eq 0 ]; then
        echo -e "${SUCCESS_COLOR}🎉 PRODUCTION READY${NC}"
        echo "✅ crashcart-ng is ready for public release"
        echo
        echo "Recommended next steps:"
        echo "1. Run comprehensive test suite: ./tests/run-all-tests.sh"
        echo "2. Create GitHub release with artifacts"
        echo "3. Update documentation with final testing results"
        echo "4. Announce release to users"
    else
        echo -e "${WARN_COLOR}⚠️  MOSTLY READY${NC}"
        echo "🟡 crashcart-ng is functional but has non-critical issues"
        echo
        echo "Address these issues before release:"
        echo "- Fix $CHECKS_FAILED non-critical validation failures"
        echo "- Run full test suite to verify quality"
        echo "- Consider addressing warnings for better user experience"
    fi
else
    echo -e "${ERROR_COLOR}❌ NOT PRODUCTION READY${NC}"
    echo "🚫 crashcart-ng has critical issues preventing release"
    echo
    echo "CRITICAL ISSUES TO RESOLVE:"
    echo "- $CRITICAL_FAILED critical validation failures"
    echo "- Core functionality must work before release"
    echo "- Build and test infrastructure must be complete"
fi

echo
echo "========================================"

exit $CRITICAL_FAILED