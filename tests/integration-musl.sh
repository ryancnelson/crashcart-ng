#!/bin/bash
# Comprehensive integration test for musl crashcart

set -e

echo "=== Crashcart Musl Integration Test ==="

# Find a running container
CONTAINER_ID=$(docker ps -q | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP: No running containers found"
    exit 0
fi

echo "Testing with container: $CONTAINER_ID"

# Test 1: Mount crashcart
echo -e "\n[Test 1] Mounting crashcart..."
sudo ./crashcart -m "$CONTAINER_ID"
echo "PASS: Mount successful"

# Test 2: Verify mount point exists in container
echo -e "\n[Test 2] Verifying mount point..."
if docker exec "$CONTAINER_ID" test -d /dev/crashcart; then
    echo "PASS: Mount point exists"
else
    echo "FAIL: Mount point not found"
    exit 1
fi

# Test 3: Test static tools work
echo -e "\n[Test 3] Testing static BusyBox tools..."
OUTPUT=$(docker exec "$CONTAINER_ID" /dev/crashcart/bin/busybox echo "hello")
if [ "$OUTPUT" = "hello" ]; then
    echo "PASS: Static BusyBox works"
else
    echo "FAIL: BusyBox failed: $OUTPUT"
    exit 1
fi

# Test 4: Test musl tools with bundled libraries
echo -e "\n[Test 4] Testing musl tools with libraries..."
# Use lsof which has simpler dependencies
if docker exec "$CONTAINER_ID" /dev/crashcart/lib/ld-musl-x86_64.so.1 --library-path /dev/crashcart/lib /dev/crashcart/usr/bin/lsof -v >/dev/null 2>&1; then
    echo "PASS: Musl tool with loader works"
else
    echo "FAIL: Musl tool failed"
    exit 1
fi

# Test 5: Test that tools run in minimal containers
echo -e "\n[Test 5] Testing in minimal Alpine container..."
ALPINE_ID=$(docker run -d alpine:latest sleep 1000)
sleep 2

sudo ./crashcart -m "$ALPINE_ID"

if docker exec "$ALPINE_ID" /dev/crashcart/bin/ps aux >/dev/null 2>&1; then
    echo "PASS: Tools work in minimal Alpine container"
else
    echo "FAIL: Tools failed in Alpine container"
    docker stop "$ALPINE_ID" >/dev/null 2>&1
    docker rm "$ALPINE_ID" >/dev/null 2>&1
    exit 1
fi

# Cleanup Alpine test container
docker stop "$ALPINE_ID" >/dev/null 2>&1
docker rm "$ALPINE_ID" >/dev/null 2>&1

# Test 6: Verify no library dependencies on target
echo -e "\n[Test 6] Verifying zero target dependencies..."
# This should work even in a scratch container
SCRATCH_ID=$(docker run -d busybox sleep 1000)
sleep 2

sudo ./crashcart -m "$SCRATCH_ID"

if docker exec "$SCRATCH_ID" /dev/crashcart/bin/busybox ls /dev/crashcart >/dev/null 2>&1; then
    echo "PASS: Works in busybox (near-scratch) container"
else
    echo "FAIL: Failed in minimal busybox container"
    docker stop "$SCRATCH_ID" >/dev/null 2>&1
    docker rm "$SCRATCH_ID" >/dev/null 2>&1
    exit 1
fi

# Cleanup scratch test container
docker stop "$SCRATCH_ID" >/dev/null 2>&1
docker rm "$SCRATCH_ID" >/dev/null 2>&1

echo -e "\n=== All Integration Tests Passed ==="