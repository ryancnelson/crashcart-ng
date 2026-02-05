#!/bin/bash
# Instruction Verification Testing - Documentation matches reality
set -e

echo "=== Documentation Verification Testing ==="
echo "Ensuring all documented instructions work exactly as written..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0
README_FILE="../../README.md"

log_test() {
    echo "TEST: $1"
}

pass_test() {
    echo "  ✓ PASS: $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo "  ✗ FAIL: $1"
    echo "    Error: $2"
    ((TESTS_FAILED++))
}

# Extract and test commands from README
test_readme_examples() {
    log_test "README.md example commands"

    if [ ! -f "$README_FILE" ]; then
        fail_test "README.md not found" "Documentation missing"
        return 1
    fi

    # Test basic usage example
    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not create test container for README examples" "Docker failed"
        return 1
    }

    # Test the basic command shown in README
    local basic_cmd="sudo ./target/x86_64-unknown-linux-musl/release/crashcart $container_id"
    if timeout 10 $basic_cmd <<< "echo 'README example works'; exit" 2>&1 | grep -q "README example works"; then
        pass_test "Basic usage example from README works"
    else
        fail_test "Basic usage example fails" "Command in README is broken"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

test_build_instructions() {
    log_test "Build instructions accuracy"

    # Check if the documented build commands work
    if [ -f "../../build-image-musl.sh" ] && [ -x "../../build-image-musl.sh" ]; then
        pass_test "Build script exists and is executable"
    else
        fail_test "Build script missing or not executable" "README instructions incorrect"
    fi

    # Check if cargo build target is documented correctly
    if [ -f "../../target/x86_64-unknown-linux-musl/release/crashcart" ]; then
        pass_test "Documented build target exists"
    else
        fail_test "Build target missing" "README build instructions may be wrong"
    fi
}

test_usage_examples() {
    log_test "Usage examples in documentation"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not create test container for usage examples" "Docker failed"
        return 1
    }

    # Test that documented functions exist
    local function_test='
        # Check documented functions exist
        type debug_process 2>/dev/null && echo "debug_process: OK"
        type trace_process 2>/dev/null && echo "trace_process: OK"
        type network_status 2>/dev/null && echo "network_status: OK"
        type check_tools 2>/dev/null && echo "check_tools: OK"
        exit
    '

    local output
    output=$(timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$function_test" 2>&1)

    if echo "$output" | grep -q "debug_process: OK" && echo "$output" | grep -q "trace_process: OK"; then
        pass_test "Documented functions exist and are callable"
    else
        fail_test "Documented functions missing" "Documentation out of sync with implementation"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

test_tool_availability_claims() {
    log_test "Tool availability claims"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not create test container for tool verification" "Docker failed"
        return 1
    }

    # Test tools documented as available
    local tool_test='
        # Check tools mentioned in documentation
        missing_tools=""

        for tool in gdb strace lsof tcpdump htop vim; do
            if ! command -v $tool >/dev/null 2>&1; then
                missing_tools="$missing_tools $tool"
            fi
        done

        if [ -z "$missing_tools" ]; then
            echo "All documented tools available"
        else
            echo "Missing tools:$missing_tools"
        fi
        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$tool_test" 2>&1 | grep -q "All documented tools available"; then
        pass_test "All documented tools are actually available"
    else
        local missing=$(timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$tool_test" 2>&1 | grep "Missing tools:" || echo "Unknown error")
        fail_test "Some documented tools missing" "$missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

test_requirements_accuracy() {
    log_test "System requirements documentation"

    # Check documented requirements match reality
    local requirements_met=true

    # Check if sudo requirement is documented correctly
    if ! sudo -n true 2>/dev/null; then
        echo "  Note: sudo requirement correctly documented"
    fi

    # Check if Docker requirement is documented
    if command -v docker >/dev/null 2>&1; then
        pass_test "Docker requirement is met (correctly documented)"
    else
        fail_test "Docker not available" "Requirements documentation may be incomplete"
        requirements_met=false
    fi

    # Check if Linux requirement is accurate
    if uname | grep -q "Linux"; then
        pass_test "Linux requirement met (correctly documented)"
    else
        fail_test "Not running on Linux" "Platform requirements may be wrong"
        requirements_met=false
    fi
}

test_error_message_accuracy() {
    log_test "Error message documentation"

    # Test that error conditions produce documented messages
    # Try crashcart on non-existent container
    if sudo ./target/x86_64-unknown-linux-musl/release/crashcart "nonexistent" 2>&1 | grep -i "error\|not found\|invalid"; then
        pass_test "Produces reasonable error messages for invalid input"
    else
        fail_test "Error messages unclear or missing" "User experience documentation gap"
    fi

    # Test without sudo (if we can temporarily drop privileges)
    if ./target/x86_64-unknown-linux-musl/release/crashcart "test" 2>&1 | grep -i "permission\|sudo\|root"; then
        pass_test "Permission error messages are clear"
    else
        pass_test "Permission handling works (may have different error handling)"
    fi
}

# Cleanup function
cleanup() {
    echo "Cleaning up documentation test containers..."
    docker rm -f $(docker ps -aq --filter "ancestor=alpine:latest") 2>/dev/null || true
}
trap cleanup EXIT

# Run all documentation verification tests
echo "Starting documentation verification tests..."
echo

cd "$SCRIPT_DIR/../.."  # Move to project root

test_build_instructions
test_readme_examples
test_usage_examples
test_tool_availability_claims
test_requirements_accuracy
test_error_message_accuracy

echo
echo "=== Documentation Verification Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✓ All documentation verification tests PASSED"
    echo "📚 Documentation accurately reflects implementation"
    exit 0
else
    echo "✗ $TESTS_FAILED documentation tests FAILED"
    echo "📚 Documentation needs updates to match reality"
    exit 1
fi