#!/bin/bash
# Real Environment Testing - Test crashcart across different container types
set -e

echo "=== Container Type Compatibility Testing ==="
echo "Testing crashcart against various container environments..."

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

# Test with distroless container (minimal, no shell utilities)
test_distroless_container() {
    log_test "Distroless container (gcr.io/distroless/java)"

    local container_id
    container_id=$(docker run -d --rm gcr.io/distroless/java:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start distroless container" "Image pull failed"
        return 1
    }

    # Test that crashcart can mount into distroless
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "echo 'mounted successfully'; exit" 2>&1 | grep -q "mounted successfully"; then
        pass_test "Mounts successfully into distroless container"
    else
        fail_test "Failed to mount into distroless container" "Mount or shell failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test with scratch container (absolutely minimal)
test_scratch_container() {
    log_test "Scratch container (empty filesystem)"

    # Create a simple binary for scratch container
    cat > /tmp/hello.c << 'EOF'
#include <unistd.h>
int main() { for(;;) sleep(1); }
EOF
    gcc -static -o /tmp/hello /tmp/hello.c

    # Build scratch container
    cat > /tmp/Dockerfile.scratch << 'EOF'
FROM scratch
COPY hello /hello
CMD ["/hello"]
EOF

    docker build -t crashcart-test-scratch -f /tmp/Dockerfile.scratch /tmp/ >/dev/null 2>&1

    local container_id
    container_id=$(docker run -d --rm crashcart-test-scratch 2>/dev/null) || {
        fail_test "Could not start scratch container" "Build or run failed"
        return 1
    }

    # Test that crashcart can mount into scratch
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "ls /dev/crashcart && echo 'mounted in scratch'; exit" 2>&1 | grep -q "mounted in scratch"; then
        pass_test "Mounts successfully into scratch container"
    else
        fail_test "Failed to mount into scratch container" "Mount failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f /tmp/hello /tmp/hello.c /tmp/Dockerfile.scratch
}

# Test with Alpine Linux (musl libc)
test_alpine_container() {
    log_test "Alpine Linux container (musl libc)"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start Alpine container" "Run failed"
        return 1
    }

    # Test debugging tools work in Alpine
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "gdb --version && echo 'gdb works in alpine'; exit" 2>&1 | grep -q "gdb works in alpine"; then
        pass_test "Debugging tools work in Alpine (musl)"
    else
        fail_test "Debugging tools failed in Alpine" "Tool compatibility issue"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test with Ubuntu container (glibc)
test_ubuntu_container() {
    log_test "Ubuntu container (glibc)"

    local container_id
    container_id=$(docker run -d --rm ubuntu:22.04 sleep 3600 2>/dev/null) || {
        fail_test "Could not start Ubuntu container" "Run failed"
        return 1
    }

    # Test debugging tools work with glibc
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "strace -V && echo 'strace works in ubuntu'; exit" 2>&1 | grep -q "strace works in ubuntu"; then
        pass_test "Debugging tools work in Ubuntu (glibc)"
    else
        fail_test "Debugging tools failed in Ubuntu" "Tool compatibility issue"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test with multi-process container
test_multiprocess_container() {
    log_test "Multi-process container"

    # Create container with multiple processes
    local container_id
    container_id=$(docker run -d --rm alpine:latest sh -c 'sleep 3600 & sleep 3600 & wait' 2>/dev/null) || {
        fail_test "Could not start multi-process container" "Run failed"
        return 1
    }

    # Test that we can see multiple processes
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "ps aux | grep -c sleep && echo 'multiprocess visible'; exit" 2>&1 | grep -q "multiprocess visible"; then
        pass_test "Can debug multi-process containers"
    else
        fail_test "Multi-process debugging failed" "Process visibility issue"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test with read-only container
test_readonly_container() {
    log_test "Read-only filesystem container"

    local container_id
    container_id=$(docker run -d --rm --read-only alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start read-only container" "Run failed"
        return 1
    }

    # Test that crashcart still works with read-only filesystem
    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "ls /dev/crashcart && echo 'readonly mount success'; exit" 2>&1 | grep -q "readonly mount success"; then
        pass_test "Works with read-only filesystem containers"
    else
        fail_test "Read-only filesystem mount failed" "Mount permissions issue"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test with privileged vs unprivileged containers
test_security_contexts() {
    log_test "Security context variations"

    # Test unprivileged container
    local container_id
    container_id=$(docker run -d --rm --user 1000:1000 alpine:latest sleep 3600 2>/dev/null) || {
        fail_test "Could not start unprivileged container" "Run failed"
        return 1
    }

    if timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "id && echo 'unprivileged mount success'; exit" 2>&1 | grep -q "unprivileged mount success"; then
        pass_test "Works with unprivileged containers"
    else
        fail_test "Unprivileged container mount failed" "Permission issue"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Cleanup function
cleanup() {
    echo "Cleaning up test containers..."
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-test-scratch") 2>/dev/null || true
    docker rmi crashcart-test-scratch 2>/dev/null || true
}
trap cleanup EXIT

# Run all tests
echo "Starting container type compatibility tests..."
echo

# Skip tests that require images we might not have
if docker image ls | grep -q "distroless/java"; then
    test_distroless_container
else
    echo "SKIP: Distroless image not available"
fi

test_scratch_container
test_alpine_container

if docker image ls | grep -q "ubuntu"; then
    test_ubuntu_container
else
    echo "SKIP: Ubuntu image not available"
fi

test_multiprocess_container
test_readonly_container
test_security_contexts

echo
echo "=== Container Type Compatibility Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✓ All container type compatibility tests PASSED"
    exit 0
else
    echo "✗ $TESTS_FAILED tests FAILED - compatibility issues found"
    exit 1
fi