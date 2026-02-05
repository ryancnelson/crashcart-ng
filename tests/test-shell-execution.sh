#!/bin/bash
# Test that crashcart can start a shell in a container

set -e

echo "Testing shell execution with crashcart..."

# Find a running container
CONTAINER_ID=$(docker ps -q | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP: No running containers found"
    exit 0
fi

echo "Testing with container: $CONTAINER_ID"

# Try to start crashcart and run a simple command
timeout 5 sudo ./crashcart "$CONTAINER_ID" -- /dev/crashcart/bin/busybox echo "test" > /tmp/crashcart-test.out 2>&1

if grep -q "test" /tmp/crashcart-test.out; then
    echo "PASS: Shell command executed successfully"
    rm /tmp/crashcart-test.out
    exit 0
else
    echo "FAIL: Shell command failed"
    cat /tmp/crashcart-test.out
    rm /tmp/crashcart-test.out
    exit 1
fi