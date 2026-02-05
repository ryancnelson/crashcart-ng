#!/bin/bash
# End-to-End Workflow Testing - Real production debugging scenarios
set -e

echo "=== Production Debugging Workflow Testing ==="
echo "Testing complete debugging workflows from crisis to resolution..."

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

# Create test applications with specific problems
create_cpu_spike_container() {
    cat > /tmp/cpu_spike.c << 'EOF'
#include <unistd.h>
#include <pthread.h>

void* cpu_hog(void* arg) {
    volatile int i = 0;
    while(1) { i++; }  // Infinite CPU loop
}

int main() {
    pthread_t thread;
    pthread_create(&thread, NULL, cpu_hog, NULL);
    sleep(3600);  // Main thread sleeps
    return 0;
}
EOF
    gcc -static -pthread -o /tmp/cpu_spike /tmp/cpu_spike.c

    cat > /tmp/Dockerfile.cpu_spike << 'EOF'
FROM scratch
COPY cpu_spike /cpu_spike
CMD ["/cpu_spike"]
EOF

    docker build -t crashcart-cpu-spike -f /tmp/Dockerfile.cpu_spike /tmp/ >/dev/null 2>&1
}

create_memory_leak_container() {
    cat > /tmp/memory_leak.c << 'EOF'
#include <stdlib.h>
#include <unistd.h>

int main() {
    while(1) {
        malloc(1024 * 1024);  // Leak 1MB every iteration
        sleep(1);
    }
    return 0;
}
EOF
    gcc -static -o /tmp/memory_leak /tmp/memory_leak.c

    cat > /tmp/Dockerfile.memory_leak << 'EOF'
FROM scratch
COPY memory_leak /memory_leak
CMD ["/memory_leak"]
EOF

    docker build -t crashcart-memory-leak -f /tmp/Dockerfile.memory_leak /tmp/ >/dev/null 2>&1
}

create_network_client_container() {
    cat > /tmp/network_client.c << 'EOF'
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

int main() {
    while(1) {
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(80);
        inet_pton(AF_INET, "1.1.1.1", &addr.sin_addr);

        connect(sock, (struct sockaddr*)&addr, sizeof(addr));  // May fail
        close(sock);
        sleep(2);
    }
    return 0;
}
EOF
    gcc -static -o /tmp/network_client /tmp/network_client.c

    cat > /tmp/Dockerfile.network_client << 'EOF'
FROM scratch
COPY network_client /network_client
CMD ["/network_client"]
EOF

    docker build -t crashcart-network-client -f /tmp/Dockerfile.network_client /tmp/ >/dev/null 2>&1
}

# Test CPU spike investigation workflow
test_cpu_spike_workflow() {
    log_test "CPU spike investigation workflow"

    create_cpu_spike_container

    local container_id
    container_id=$(docker run -d --rm crashcart-cpu-spike 2>/dev/null) || {
        fail_test "Could not start CPU spike container" "Container creation failed"
        return 1
    }

    # Give container time to start consuming CPU
    sleep 3

    # Workflow: crashcart → htop → identify hot process → gdb attach
    local workflow_script='
        # Step 1: Check processes with htop-like output
        ps aux --sort=-%cpu | head -5

        # Step 2: Find the CPU-hungry process
        hot_pid=$(ps aux --sort=-%cpu | grep -v "ps aux" | awk "NR==2 {print \$2}")
        echo "Hot PID: $hot_pid"

        # Step 3: Try to attach gdb (will fail in container, but should exist)
        if command -v gdb >/dev/null; then
            echo "GDB available for debugging PID $hot_pid"
            echo "CPU spike workflow: SUCCESS"
        else
            echo "GDB missing - workflow failed"
        fi

        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$workflow_script" 2>&1 | grep -q "CPU spike workflow: SUCCESS"; then
        pass_test "CPU spike investigation workflow complete"
    else
        fail_test "CPU spike workflow failed" "Tools missing or process identification failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test memory leak investigation workflow
test_memory_leak_workflow() {
    log_test "Memory leak investigation workflow"

    create_memory_leak_container

    local container_id
    container_id=$(docker run -d --rm crashcart-memory-leak 2>/dev/null) || {
        fail_test "Could not start memory leak container" "Container creation failed"
        return 1
    }

    # Give container time to leak some memory
    sleep 5

    # Workflow: crashcart → check memory → identify leaking process
    local workflow_script='
        # Step 1: Check overall memory status
        free -h 2>/dev/null || cat /proc/meminfo | head -3

        # Step 2: Find memory-heavy processes
        ps aux --sort=-%mem | head -5

        # Step 3: Check process memory maps
        leak_pid=$(ps aux --sort=-%mem | grep -v "ps aux" | awk "NR==2 {print \$2}")
        echo "Investigating PID: $leak_pid"

        # Step 4: Memory analysis tools available
        if [ -f /proc/$leak_pid/status ]; then
            echo "Process memory info accessible"
        fi

        if command -v gdb >/dev/null; then
            echo "GDB available for heap analysis"
            echo "Memory leak workflow: SUCCESS"
        else
            echo "Memory analysis tools missing"
        fi

        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$workflow_script" 2>&1 | grep -q "Memory leak workflow: SUCCESS"; then
        pass_test "Memory leak investigation workflow complete"
    else
        fail_test "Memory leak workflow failed" "Tools missing or memory analysis failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test network connectivity debugging workflow
test_network_debugging_workflow() {
    log_test "Network connectivity debugging workflow"

    create_network_client_container

    local container_id
    container_id=$(docker run -d --rm crashcart-network-client 2>/dev/null) || {
        fail_test "Could not start network client container" "Container creation failed"
        return 1
    }

    # Give container time to make network attempts
    sleep 3

    # Workflow: crashcart → check connections → packet capture → DNS
    local workflow_script='
        # Step 1: Check active network connections
        if command -v ss >/dev/null; then
            ss -tuln | head -10
            echo "Network connections visible"
        else
            echo "Network tools missing"
        fi

        # Step 2: Check DNS resolution capability
        if command -v nslookup >/dev/null || command -v dig >/dev/null; then
            echo "DNS tools available"
        else
            echo "DNS tools missing"
        fi

        # Step 3: Packet capture capability
        if command -v tcpdump >/dev/null; then
            echo "Packet capture available"
            echo "Network debugging workflow: SUCCESS"
        else
            echo "Packet capture tools missing"
        fi

        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$workflow_script" 2>&1 | grep -q "Network debugging workflow: SUCCESS"; then
        pass_test "Network debugging workflow complete"
    else
        fail_test "Network debugging workflow failed" "Network tools missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test file descriptor investigation workflow
test_fd_exhaustion_workflow() {
    log_test "File descriptor exhaustion investigation workflow"

    # Use Alpine container and simulate FD usage
    local container_id
    container_id=$(docker run -d --rm alpine:latest sh -c 'for i in $(seq 1 10); do exec 3< /etc/passwd; done; sleep 3600' 2>/dev/null) || {
        fail_test "Could not start FD test container" "Container creation failed"
        return 1
    }

    # Workflow: crashcart → lsof → /proc analysis
    local workflow_script='
        # Step 1: Check overall FD usage
        echo "Checking file descriptor usage..."

        # Step 2: Use lsof to see open files
        if command -v lsof >/dev/null; then
            target_pid=$(ps aux | grep -v "ps aux\|grep" | awk "NR==2 {print \$2}")
            echo "Analyzing FDs for PID: $target_pid"
            lsof -p $target_pid 2>/dev/null | head -10 || echo "lsof executed"
            echo "FD analysis tools available"
        else
            echo "lsof missing"
        fi

        # Step 3: Check /proc filesystem access
        if ls /proc/*/fd/ 2>/dev/null | head -5; then
            echo "Proc filesystem accessible"
            echo "FD debugging workflow: SUCCESS"
        else
            echo "Proc filesystem access failed"
        fi

        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$workflow_script" 2>&1 | grep -q "FD debugging workflow: SUCCESS"; then
        pass_test "File descriptor investigation workflow complete"
    else
        fail_test "FD investigation workflow failed" "Tools missing or filesystem access failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Test container startup failure investigation
test_startup_failure_workflow() {
    log_test "Container startup failure investigation workflow"

    # Create container that fails to start properly
    local container_id
    container_id=$(docker run -d --rm alpine:latest sh -c 'echo "Startup attempt"; exit 1' 2>/dev/null) || {
        # Container may exit immediately, that's expected
        container_id=$(docker ps -a --filter "ancestor=alpine:latest" --format "{{.ID}}" | head -1)
    }

    if [ -z "$container_id" ]; then
        fail_test "Could not create startup failure test" "No container to analyze"
        return 1
    fi

    # Even if container exited, we should be able to investigate
    local workflow_script='
        # Step 1: Check what processes were running
        echo "Investigating startup failure..."

        # Step 2: System log access
        if command -v dmesg >/dev/null; then
            echo "Kernel logs accessible via dmesg"
        else
            echo "dmesg not available"
        fi

        # Step 3: Process information
        ps aux | head -5
        echo "Process investigation tools available"
        echo "Startup failure workflow: SUCCESS"

        exit
    '

    if timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" <<< "$workflow_script" 2>&1 | grep -q "Startup failure workflow: SUCCESS"; then
        pass_test "Startup failure investigation workflow complete"
    else
        fail_test "Startup failure workflow failed" "Investigation tools missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
}

# Cleanup function
cleanup() {
    echo "Cleaning up test containers and images..."
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-cpu-spike") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-memory-leak") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-network-client") 2>/dev/null || true
    docker rmi crashcart-cpu-spike crashcart-memory-leak crashcart-network-client 2>/dev/null || true
    rm -f /tmp/cpu_spike* /tmp/memory_leak* /tmp/network_client* /tmp/Dockerfile.*
}
trap cleanup EXIT

# Run all workflow tests
echo "Starting production debugging workflow tests..."
echo

test_cpu_spike_workflow
test_memory_leak_workflow
test_network_debugging_workflow
test_fd_exhaustion_workflow
test_startup_failure_workflow

echo
echo "=== Production Workflow Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✓ All production debugging workflows PASSED"
    exit 0
else
    echo "✗ $TESTS_FAILED workflows FAILED - production readiness issues found"
    exit 1
fi