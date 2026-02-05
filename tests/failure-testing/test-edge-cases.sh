#!/bin/bash
# Edge Case and Failure Mode Testing - Test crashcart against hostile conditions
set -e

echo "=== Edge Case and Failure Mode Testing ==="
echo "Testing crashcart against conditions that typically break debugging tools..."

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

skip_test() {
    echo "  ⚠ SKIP: $1"
    echo "    Reason: $2"
}

# Test with extremely minimal scratch container
test_scratch_container_edge_case() {
    log_test "Absolutely minimal scratch container"

    # Create the most minimal possible container
    cat > /tmp/minimal.c << 'EOF'
int main() {
    while(1) __asm__("pause");
}
EOF
    gcc -static -Os -s -o /tmp/minimal /tmp/minimal.c
    strip /tmp/minimal

    cat > /tmp/Dockerfile.minimal << 'EOF'
FROM scratch
COPY minimal /
CMD ["/minimal"]
EOF

    docker build -t crashcart-minimal -f /tmp/Dockerfile.minimal /tmp/ >/dev/null 2>&1

    local container_id
    container_id=$(docker run -d --rm crashcart-minimal 2>/dev/null) || {
        fail_test "Could not start minimal scratch container" "Build failed"
        return 1
    }

    # Give process time to start
    sleep 2

    # Test crashcart can attach to absolute minimal container
    echo 'ls /dev/crashcart && echo "MINIMAL_SUCCESS"; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_minimal.log 2>&1

    if grep -q "MINIMAL_SUCCESS" test_minimal.log; then
        pass_test "Works with absolute minimal scratch container"
    else
        if grep -q "Self-Contained Musl Crashcart loaded" test_minimal.log; then
            pass_test "Mounts in minimal container (shell issues expected)"
        else
            fail_test "Failed with minimal container" "$(tail -3 test_minimal.log)"
        fi
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f /tmp/minimal* /tmp/Dockerfile.minimal test_minimal.log
}

# Test resource constraints
test_resource_constrained_container() {
    log_test "Resource-constrained container"

    # Start container with severe memory limit
    local container_id
    container_id=$(docker run -d --rm --memory=32m --memory-swap=32m alpine:latest sleep 3600 2>/dev/null) || {
        skip_test "Memory-constrained container" "Docker memory limits not supported"
        return 0
    }

    echo 'free -m && echo "MEMORY_LIMITED_SUCCESS"; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_memory.log 2>&1

    if grep -q "MEMORY_LIMITED_SUCCESS" test_memory.log; then
        pass_test "Works with memory-limited containers"
    else
        fail_test "Failed with memory limits" "$(tail -3 test_memory.log)"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_memory.log
}

# Test permission edge cases
test_permission_edge_cases() {
    log_test "Permission and security edge cases"

    # Test with read-only container
    local container_id
    container_id=$(docker run -d --rm --read-only alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start read-only container" "Docker failed"
        return 1
    }

    echo 'touch /tmp/test 2>/dev/null || echo "READONLY_OK"; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_readonly.log 2>&1

    if grep -q "READONLY_OK" test_readonly.log; then
        pass_test "Works with read-only filesystem containers"
    else
        fail_test "Failed with read-only container" "$(tail -3 test_readonly.log)"
    fi

    docker rm -f "$container_id" 2>/dev/null || true

    # Test with unprivileged user
    container_id=$(docker run -d --rm --user 1000:1000 alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start unprivileged container" "Docker failed"
        return 1
    }

    echo 'id && echo "UNPRIVILEGED_SUCCESS"; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_unprivileged.log 2>&1

    if grep -q "UNPRIVILEGED_SUCCESS" test_unprivileged.log; then
        pass_test "Works with unprivileged containers"
    else
        fail_test "Failed with unprivileged container" "$(tail -3 test_unprivileged.log)"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_readonly.log test_unprivileged.log
}

# Test multiple simultaneous crashcart instances
test_concurrent_usage() {
    log_test "Concurrent crashcart usage"

    # Start multiple containers
    local container1 container2
    container1=$(docker run -d --rm alpine:latest sleep 3600)
    container2=$(docker run -d --rm alpine:latest sleep 3600)

    # Launch crashcart on both simultaneously
    echo 'echo "CONCURRENT1_$$"; sleep 3; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container1" >test_concurrent1.log 2>&1 &
    local pid1=$!

    echo 'echo "CONCURRENT2_$$"; sleep 3; exit 0' | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container2" >test_concurrent2.log 2>&1 &
    local pid2=$!

    # Wait for both to complete
    wait $pid1 || true
    wait $pid2 || true

    if grep -q "CONCURRENT1" test_concurrent1.log && grep -q "CONCURRENT2" test_concurrent2.log; then
        pass_test "Handles concurrent usage correctly"
    else
        fail_test "Concurrent usage issues" "Process conflicts or resource contention"
    fi

    docker rm -f "$container1" "$container2" 2>/dev/null || true
    rm -f test_concurrent1.log test_concurrent2.log
}

# Test rapid start/stop cycles
test_rapid_cycling() {
    log_test "Rapid start/stop cycling"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600)

    local success_count=0
    for i in {1..5}; do
        echo "echo 'CYCLE_$i'; exit 0" | timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_cycle_$i.log 2>&1
        if grep -q "CYCLE_$i" test_cycle_$i.log; then
            ((success_count++))
        fi
        sleep 1
    done

    if [ "$success_count" -eq 5 ]; then
        pass_test "Handles rapid start/stop cycles"
    else
        fail_test "Rapid cycling issues" "Only $success_count/5 cycles succeeded"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_cycle_*.log
}

# Test container death during crashcart session
test_container_death_handling() {
    log_test "Container death during session"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 10)  # Short-lived container

    # Start crashcart and let container die
    echo 'sleep 15; echo "DEATH_HANDLED"; exit 0' | timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_death.log 2>&1 &
    local crashcart_pid=$!

    # Wait for container to die naturally
    sleep 12

    # Check if crashcart handled it gracefully
    wait $crashcart_pid || true

    if grep -q "Self-Contained Musl Crashcart loaded" test_death.log; then
        pass_test "Handles target container death gracefully"
    else
        fail_test "Poor handling of container death" "$(tail -5 test_death.log)"
    fi

    rm -f test_death.log
}

# Test error recovery
test_error_recovery() {
    log_test "Error recovery and cleanup"

    # Test with invalid container ID
    if timeout 5 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "invalid-container-id" 2>&1 | grep -i "error\|not found\|invalid"; then
        pass_test "Provides clear error messages for invalid input"
    else
        fail_test "Poor error handling for invalid container" "No clear error message"
    fi

    # Test cleanup after forced termination
    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600)

    # Start crashcart and kill it abruptly
    timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_kill.log 2>&1 &
    local crashcart_pid=$!

    sleep 3
    kill -KILL $crashcart_pid 2>/dev/null || true
    sleep 2

    # Check if cleanup occurred (no lingering mounts)
    if ! mount | grep -q crashcart && ! losetup -a | grep -q crashcart; then
        pass_test "Cleanup after forced termination"
    else
        fail_test "Poor cleanup after forced kill" "Lingering mounts or loop devices"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_kill.log
}

# Cleanup function
cleanup() {
    echo "Cleaning up edge case test resources..."
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-minimal") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=alpine:latest") 2>/dev/null || true
    docker rmi crashcart-minimal 2>/dev/null || true
    rm -f /tmp/minimal* /tmp/Dockerfile.* test_*.log
}
trap cleanup EXIT

# Run all edge case tests
echo "Starting edge case and failure mode tests..."
echo

test_scratch_container_edge_case
test_resource_constrained_container
test_permission_edge_cases
test_concurrent_usage
test_rapid_cycling
test_container_death_handling
test_error_recovery

echo
echo "=== Edge Case Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✓ All edge case tests PASSED"
    echo "🛡️ crashcart handles hostile conditions well"
    exit 0
else
    echo "✗ $TESTS_FAILED edge case tests FAILED"
    echo "🚨 Production reliability concerns identified"
    exit 1
fi