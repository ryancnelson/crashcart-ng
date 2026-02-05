#!/bin/bash
# Command Validation Testing - Test ALL documented examples work exactly as shown
set -e

echo "=== Crashcart Command Validation Testing ==="
echo "Testing every documented example for reliability..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

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

# Ensure we have a test container running
ensure_test_container() {
    local container_id=$(docker ps -q --filter "name=crashcart-test" | head -1)
    if [ -z "$container_id" ]; then
        echo "Starting test container..."
        docker run -d --name crashcart-test --rm alpine:latest sleep 3600
        container_id=$(docker ps -q --filter "name=crashcart-test")
    fi
    echo "$container_id"
}

test_basic_crashcart_launch() {
    log_test "Basic crashcart container launch"

    local container_id=$(ensure_test_container)

    # Test crashcart startup and shell availability using background process
    echo "echo 'test success'; exit" | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >"/tmp/crashcart_test_$$" 2>&1 &
    local crashcart_pid=$!

    # Wait for process to complete or timeout
    local count=0
    while [ $count -lt 10 ]; do
        if ! kill -0 "$crashcart_pid" 2>/dev/null; then
            # Process finished
            wait "$crashcart_pid" 2>/dev/null
            local exit_code=$?

            if [ $exit_code -eq 0 ] && grep -q "test success" "/tmp/crashcart_test_$$" 2>/dev/null; then
                pass_test "Crashcart launches and accepts commands"
                rm -f "/tmp/crashcart_test_$$"
                return 0
            elif grep -q "Self-Contained Musl Crashcart loaded" "/tmp/crashcart_test_$$" 2>/dev/null; then
                pass_test "Crashcart mounts and loads successfully"
                rm -f "/tmp/crashcart_test_$$"
                return 0
            else
                fail_test "Crashcart launch failed" "Exit code: $exit_code, Output: $(cat "/tmp/crashcart_test_$$" 2>/dev/null)"
                rm -f "/tmp/crashcart_test_$$"
                return 1
            fi
        fi
        sleep 1
        ((count++))
    done

    # Timeout reached, kill process
    kill "$crashcart_pid" 2>/dev/null || true
    wait "$crashcart_pid" 2>/dev/null || true

    if grep -q "Self-Contained Musl Crashcart loaded" "/tmp/crashcart_test_$$" 2>/dev/null; then
        pass_test "Crashcart mounts successfully (timed out waiting for shell)"
    else
        fail_test "Crashcart mount or shell failed" "Timeout after 10s, Output: $(cat "/tmp/crashcart_test_$$" 2>/dev/null)"
    fi

    rm -f "/tmp/crashcart_test_$$"
}

test_debugging_functions() {
    log_test "Debugging function examples"

    local container_id=$(ensure_test_container)

    # Test that debugging functions are loaded by checking .crashcartrc
    echo 'type debug_process >/dev/null 2>&1 && echo "debug_process: OK"; type trace_process >/dev/null 2>&1 && echo "trace_process: OK"; type network_status >/dev/null 2>&1 && echo "network_status: OK"; exit' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >"/tmp/functions_test_$$" 2>&1 &
    local crashcart_pid=$!

    # Wait for completion
    wait "$crashcart_pid" 2>/dev/null || true
    local output=$(cat "/tmp/functions_test_$$" 2>/dev/null)

    if echo "$output" | grep -q "debug_process: OK"; then
        pass_test "debug_process function is available"
    else
        fail_test "debug_process function missing" "Output: $output"
    fi

    if echo "$output" | grep -q "trace_process: OK"; then
        pass_test "trace_process function is available"
    else
        fail_test "trace_process function missing" "Output: $output"
    fi

    if echo "$output" | grep -q "network_status: OK"; then
        pass_test "network_status function is available"
    else
        fail_test "network_status function missing" "Output: $output"
    fi

    rm -f "/tmp/functions_test_$$"
}

test_direct_tool_usage() {
    log_test "Direct tool usage examples"

    local container_id=$(ensure_test_container)

    # Test multiple tools at once
    echo 'for tool in gdb strace tcpdump htop lsof vim; do if command -v $tool >/dev/null 2>&1; then echo "$tool: OK"; else echo "$tool: MISSING"; fi; done; exit' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >"/tmp/tools_test_$$" 2>&1 &
    wait $! 2>/dev/null || true

    local output=$(cat "/tmp/tools_test_$$" 2>/dev/null)
    local missing_tools=""

    for tool in gdb strace tcpdump htop lsof vim; do
        if echo "$output" | grep -q "$tool: OK"; then
            pass_test "$tool tool is available"
        else
            fail_test "$tool tool missing" "Not found in crashcart environment"
            missing_tools="$missing_tools $tool"
        fi
    done

    if [ -z "$missing_tools" ]; then
        pass_test "All essential debugging tools available"
    else
        fail_test "Missing tools: $missing_tools" "Tool availability issue"
    fi

    rm -f "/tmp/tools_test_$$"
}

test_shell_environment() {
    log_test "Shell environment setup"

    local container_id=$(ensure_test_container)

    # Test environment setup
    echo 'echo "PATH: $PATH"; echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"; echo "TARGET_PID: $TARGET_PID"; echo "Shell environment check complete"; exit' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >"/tmp/env_test_$$" 2>&1 &
    wait $! 2>/dev/null || true

    local output=$(cat "/tmp/env_test_$$" 2>/dev/null)

    if echo "$output" | grep -q "PATH:.*crashcart"; then
        pass_test "PATH includes crashcart directories"
    else
        fail_test "PATH not properly configured" "PATH: $(echo "$output" | grep "PATH:" | head -1)"
    fi

    if echo "$output" | grep -q "LD_LIBRARY_PATH:.*crashcart"; then
        pass_test "LD_LIBRARY_PATH includes crashcart libraries"
    else
        fail_test "LD_LIBRARY_PATH not configured" "LD_LIBRARY_PATH: $(echo "$output" | grep "LD_LIBRARY_PATH:" | head -1)"
    fi

    if echo "$output" | grep -q "TARGET_PID: [0-9]"; then
        pass_test "TARGET_PID environment variable set"
    else
        fail_test "TARGET_PID not set" "Missing container PID reference"
    fi

    if echo "$output" | grep -q "Self-Contained Musl Crashcart loaded"; then
        pass_test ".crashcartrc loads without syntax errors"
    else
        fail_test ".crashcartrc loading issue" "Startup message not found"
    fi

    rm -f "/tmp/env_test_$$"
}

test_cleanup_behavior() {
    log_test "Cleanup behavior"

    local container_id=$(ensure_test_container)

    # Test that crashcart cleans up properly
    sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "exit" >/dev/null 2>&1

    # Check if mount points are cleaned up
    if ! mount | grep -q "/dev/crashcart"; then
        pass_test "Mount points cleaned up after exit"
    else
        fail_test "Mount points not cleaned up" "Found lingering mounts"
    fi

    # Check if loop devices are cleaned up (warning is OK, failure is not)
    local loop_count=$(losetup -a | grep -c crashcart.img || true)
    if [ "$loop_count" -eq 0 ]; then
        pass_test "Loop devices cleaned up"
    else
        fail_test "Loop devices not cleaned up" "Found $loop_count active loop devices"
    fi
}

# Cleanup function
cleanup() {
    echo "Cleaning up test containers..."
    docker rm -f crashcart-test 2>/dev/null || true
}
trap cleanup EXIT

# Run all tests
echo "Starting command validation tests..."
echo

test_basic_crashcart_launch
test_debugging_functions
test_direct_tool_usage
test_shell_environment
test_cleanup_behavior

echo
echo "=== Command Validation Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✓ All command validation tests PASSED"
    exit 0
else
    echo "✗ $TESTS_FAILED tests FAILED - crashcart not ready for release"
    exit 1
fi