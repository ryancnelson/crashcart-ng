#!/bin/bash
# Production Crisis Scenario Testing - Real debugging workflows
set -e

echo "=== Production Crisis Scenario Testing ==="
echo "Testing crashcart in realistic production emergency scenarios..."

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

# Create realistic problem containers
create_problem_containers() {
    # CPU hog container
    cat > /tmp/cpu_hog.c << 'EOF'
#include <pthread.h>
#include <unistd.h>

void* cpu_burn(void* arg) {
    volatile long i = 0;
    while(1) { i++; }
}

int main() {
    pthread_t threads[4];
    for(int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, cpu_burn, NULL);
    }
    sleep(3600);
    return 0;
}
EOF
    gcc -static -pthread -o /tmp/cpu_hog /tmp/cpu_hog.c

    # Memory leak container
    cat > /tmp/memory_hog.c << 'EOF'
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

int main() {
    while(1) {
        void* ptr = malloc(1024 * 1024);  // 1MB leak per second
        if(ptr) memset(ptr, 0, 1024 * 1024);  // Touch the memory
        sleep(1);
    }
    return 0;
}
EOF
    gcc -static -o /tmp/memory_hog /tmp/memory_hog.c

    # Network service container
    cat > /tmp/network_service.c << 'EOF'
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <string.h>

int main() {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(8080);

    bind(sock, (struct sockaddr*)&addr, sizeof(addr));
    listen(sock, 5);

    while(1) {
        int client = accept(sock, NULL, NULL);
        if(client > 0) {
            write(client, "HTTP/1.1 200 OK\r\n\r\nHello\n", 27);
            close(client);
        }
    }
    return 0;
}
EOF
    gcc -static -o /tmp/network_service /tmp/network_service.c

    # Build containers
    for app in cpu_hog memory_hog network_service; do
        cat > /tmp/Dockerfile.$app << EOF
FROM scratch
COPY $app /$app
CMD ["/$app"]
EOF
        docker build -t crashcart-$app -f /tmp/Dockerfile.$app /tmp/ >/dev/null 2>&1
    done
}

# Scenario 1: "Production server is using 100% CPU"
test_cpu_spike_investigation() {
    log_test "CPU spike investigation scenario"

    local container_id
    container_id=$(docker run -d --rm crashcart-cpu_hog 2>/dev/null) || {
        fail_test "Could not start CPU spike container" "Build failed"
        return 1
    }

    # Give CPU hog time to start consuming CPU
    sleep 3

    # Crisis workflow: Identify hot process, get stack traces
    local investigation='
        # Step 1: Find the hot process
        echo "=== CPU Investigation ==="
        ps aux --sort=-%cpu | head -10

        # Step 2: Get the PID of the CPU hog
        HOT_PID=$(ps aux --sort=-%cpu | grep -v "ps aux\|grep\|crashcart" | head -2 | tail -1 | awk "{print \$2}")
        echo "Investigating PID: $HOT_PID"

        # Step 3: Check if we can attach debugging tools
        if command -v gdb >/dev/null 2>&1; then
            echo "GDB available for stack trace analysis"
            # Note: In real scenario, would do: gdb -p $HOT_PID
            echo "Would analyze stack traces of PID $HOT_PID"
        fi

        # Step 4: Check thread information
        if [ -f /proc/$HOT_PID/status ]; then
            echo "Process information accessible via /proc"
            grep -E "^(Threads|voluntary_ctxt_switches|nonvoluntary_ctxt_switches)" /proc/$HOT_PID/status
        fi

        echo "CPU_INVESTIGATION_COMPLETE"
        exit 0
    '

    echo "$investigation" | timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_cpu_investigation.log 2>&1

    if grep -q "CPU_INVESTIGATION_COMPLETE" test_cpu_investigation.log && grep -q "GDB available" test_cpu_investigation.log; then
        pass_test "CPU spike investigation workflow successful"
    else
        fail_test "CPU investigation workflow failed" "Missing tools or process access failed"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_cpu_investigation.log
}

# Scenario 2: "Memory usage is climbing, possible leak"
test_memory_leak_investigation() {
    log_test "Memory leak investigation scenario"

    local container_id
    container_id=$(docker run -d --rm crashcart-memory_hog 2>/dev/null) || {
        fail_test "Could not start memory leak container" "Build failed"
        return 1
    }

    # Give memory hog time to allocate some memory
    sleep 5

    # Crisis workflow: Find memory consumer, analyze allocation
    local investigation='
        # Step 1: Check overall memory status
        echo "=== Memory Investigation ==="
        free -h 2>/dev/null || cat /proc/meminfo | head -5

        # Step 2: Find memory-heavy processes
        ps aux --sort=-%mem | head -10

        # Step 3: Get the PID of memory consumer
        MEM_PID=$(ps aux --sort=-%mem | grep -v "ps aux\|grep\|crashcart" | head -2 | tail -1 | awk "{print \$2}")
        echo "Investigating memory usage of PID: $MEM_PID"

        # Step 4: Check memory maps
        if [ -f /proc/$MEM_PID/smaps ]; then
            echo "Memory maps accessible via /proc"
            echo "RSS usage: $(grep "^Rss:" /proc/$MEM_PID/smaps | awk "{sum += \$2} END {print sum} " || echo "0") KB"
        fi

        # Step 5: Check if memory debugging tools available
        if command -v gdb >/dev/null 2>&1; then
            echo "GDB available for heap analysis"
            # Note: In real scenario, would analyze heap with gdb
        fi

        echo "MEMORY_INVESTIGATION_COMPLETE"
        exit 0
    '

    echo "$investigation" | timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_memory_investigation.log 2>&1

    if grep -q "MEMORY_INVESTIGATION_COMPLETE" test_memory_investigation.log && grep -q "Memory maps accessible" test_memory_investigation.log; then
        pass_test "Memory leak investigation workflow successful"
    else
        fail_test "Memory investigation workflow failed" "Process access or tools missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_memory_investigation.log
}

# Scenario 3: "Service isn't responding, network issues?"
test_network_debugging_scenario() {
    log_test "Network service debugging scenario"

    local container_id
    container_id=$(docker run -d --rm -p 8080:8080 crashcart-network_service 2>/dev/null) || {
        fail_test "Could not start network service container" "Build failed"
        return 1
    }

    # Give service time to start listening
    sleep 3

    # Crisis workflow: Check network connectivity and service state
    local investigation='
        # Step 1: Check what ports are listening
        echo "=== Network Investigation ==="
        if command -v ss >/dev/null 2>&1; then
            echo "Active network connections:"
            ss -tuln | head -10
        elif command -v netstat >/dev/null 2>&1; then
            echo "Active network connections:"
            netstat -tuln | head -10
        fi

        # Step 2: Find the service process
        SERVICE_PID=$(ps aux | grep -v "ps aux\|grep\|crashcart" | head -2 | tail -1 | awk "{print \$2}")
        echo "Investigating service PID: $SERVICE_PID"

        # Step 3: Check network namespace and connectivity
        if [ -f /proc/$SERVICE_PID/net/tcp ]; then
            echo "Network namespace accessible"
            echo "TCP connections: $(wc -l < /proc/$SERVICE_PID/net/tcp)"
        fi

        # Step 4: Check if network capture tools available
        if command -v tcpdump >/dev/null 2>&1; then
            echo "Packet capture available via tcpdump"
            # Note: In real scenario, would capture packets
        fi

        # Step 5: Test basic connectivity tools
        if command -v curl >/dev/null 2>&1; then
            echo "HTTP client tools available"
        fi

        echo "NETWORK_INVESTIGATION_COMPLETE"
        exit 0
    '

    echo "$investigation" | timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_network_investigation.log 2>&1

    if grep -q "NETWORK_INVESTIGATION_COMPLETE" test_network_investigation.log && grep -q "Network namespace accessible" test_network_investigation.log; then
        pass_test "Network debugging scenario successful"
    else
        fail_test "Network debugging workflow failed" "Network tools or access missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_network_investigation.log
}

# Scenario 4: "Container keeps crashing, need to debug startup"
test_crash_debugging_scenario() {
    log_test "Container crash debugging scenario"

    # Create a container that crashes after a short time
    cat > /tmp/crasher.c << 'EOF'
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>

void crash_handler(int sig) {
    exit(1);
}

int main() {
    signal(SIGALRM, crash_handler);
    alarm(5);  // Crash after 5 seconds
    while(1) sleep(1);
    return 0;
}
EOF
    gcc -static -o /tmp/crasher /tmp/crasher.c

    cat > /tmp/Dockerfile.crasher << 'EOF'
FROM scratch
COPY crasher /crasher
CMD ["/crasher"]
EOF
    docker build -t crashcart-crasher -f /tmp/Dockerfile.crasher /tmp/ >/dev/null 2>&1

    local container_id
    container_id=$(docker run -d --rm crashcart-crasher 2>/dev/null) || {
        fail_test "Could not start crasher container" "Build failed"
        return 1
    }

    # Quick investigation before crash
    local investigation='
        # Step 1: Check running processes immediately
        echo "=== Crash Investigation ==="
        ps aux | head -10

        # Step 2: Check system logs if available
        if command -v dmesg >/dev/null 2>&1; then
            echo "Kernel logs accessible via dmesg"
            dmesg | tail -5
        fi

        # Step 3: Check process state
        MAIN_PID=$(ps aux | grep -v "ps aux\|grep\|crashcart" | head -2 | tail -1 | awk "{print \$2}")
        echo "Main process PID: $MAIN_PID"

        if [ -f /proc/$MAIN_PID/status ]; then
            echo "Process status accessible"
            grep "^State:" /proc/$MAIN_PID/status
        fi

        # Step 4: Check if debugging tools ready
        if command -v strace >/dev/null 2>&1; then
            echo "System call tracing available"
            # Note: In real scenario, would strace the process
        fi

        echo "CRASH_INVESTIGATION_COMPLETE"
        exit 0
    '

    echo "$investigation" | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_crash_investigation.log 2>&1 &
    local crashcart_pid=$!

    # Let it run, then wait
    wait $crashcart_pid || true

    if grep -q "CRASH_INVESTIGATION_COMPLETE" test_crash_investigation.log && grep -q "Process status accessible" test_crash_investigation.log; then
        pass_test "Crash debugging scenario successful"
    else
        fail_test "Crash debugging workflow failed" "Process access or debugging tools missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f /tmp/crasher* /tmp/Dockerfile.crasher test_crash_investigation.log
}

# Test comprehensive debugging toolkit availability
test_debugging_toolkit_completeness() {
    log_test "Complete debugging toolkit verification"

    local container_id
    container_id=$(docker run -d --rm alpine:latest sleep 3600)

    # Check all essential debugging tools are present and functional
    local toolkit_check='
        echo "=== Debugging Toolkit Check ==="

        # Core debugging tools
        missing_tools=""
        for tool in gdb strace ltrace lsof; do
            if command -v $tool >/dev/null 2>&1; then
                echo "✓ $tool available"
            else
                echo "✗ $tool missing"
                missing_tools="$missing_tools $tool"
            fi
        done

        # Network debugging tools
        for tool in tcpdump ss netstat; do
            if command -v $tool >/dev/null 2>&1; then
                echo "✓ $tool available"
            else
                echo "⚠ $tool missing (network debugging may be limited)"
            fi
        done

        # System monitoring tools
        for tool in htop top ps; do
            if command -v $tool >/dev/null 2>&1; then
                echo "✓ $tool available"
            else
                echo "⚠ $tool missing (monitoring may be limited)"
            fi
        done

        # Text processing and utilities
        for tool in vim less grep find; do
            if command -v $tool >/dev/null 2>&1; then
                echo "✓ $tool available"
            else
                echo "⚠ $tool missing (productivity impact)"
            fi
        done

        if [ -z "$missing_tools" ]; then
            echo "TOOLKIT_COMPLETE"
        else
            echo "TOOLKIT_INCOMPLETE: $missing_tools"
        fi

        exit 0
    '

    echo "$toolkit_check" | timeout 15 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$container_id" >test_toolkit.log 2>&1

    if grep -q "TOOLKIT_COMPLETE" test_toolkit.log; then
        pass_test "Complete debugging toolkit available"
    else
        local missing=$(grep "TOOLKIT_INCOMPLETE:" test_toolkit.log | cut -d: -f2)
        fail_test "Incomplete debugging toolkit" "Missing critical tools:$missing"
    fi

    docker rm -f "$container_id" 2>/dev/null || true
    rm -f test_toolkit.log
}

# Cleanup function
cleanup() {
    echo "Cleaning up production test resources..."
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-cpu_hog") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-memory_hog") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-network_service") 2>/dev/null || true
    docker rm -f $(docker ps -aq --filter "ancestor=crashcart-crasher") 2>/dev/null || true
    docker rmi crashcart-cpu_hog crashcart-memory_hog crashcart-network_service crashcart-crasher 2>/dev/null || true
    rm -f /tmp/cpu_hog* /tmp/memory_hog* /tmp/network_service* /tmp/crasher* /tmp/Dockerfile.* test_*.log
}
trap cleanup EXIT

# Build test containers
echo "Creating realistic problem containers..."
create_problem_containers

echo "Starting production crisis scenario tests..."
echo

test_cpu_spike_investigation
test_memory_leak_investigation
test_network_debugging_scenario
test_crash_debugging_scenario
test_debugging_toolkit_completeness

echo
echo "=== Production Crisis Scenario Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "✅ All production crisis scenarios PASSED"
    echo "🚀 crashcart is production-ready for real emergencies"
    exit 0
else
    echo "❌ $TESTS_FAILED production scenarios FAILED"
    echo "🚨 Not ready for production emergencies"
    exit 1
fi