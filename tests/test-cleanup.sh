#!/bin/bash
# Test that loop devices are properly cleaned up

set -e

echo "Testing loop device cleanup..."

# Record initial loop devices
INITIAL_LOOPS=$(losetup -a | grep crashcart.img | wc -l)
echo "Initial crashcart loop devices: $INITIAL_LOOPS"

# Find a running container
CONTAINER_ID=$(docker ps -q | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP: No running containers found"
    exit 0
fi

# Run crashcart mount-only mode
sudo ./crashcart -m "$CONTAINER_ID"

# Give it a moment to settle
sleep 2

# Run crashcart unmount
sudo ./crashcart -u "$CONTAINER_ID" 2>/dev/null || true

# Check loop devices after
FINAL_LOOPS=$(losetup -a | grep crashcart.img | wc -l)
echo "Final crashcart loop devices: $FINAL_LOOPS"

if [ "$FINAL_LOOPS" -le "$INITIAL_LOOPS" ]; then
    echo "PASS: Loop devices cleaned up properly"
    exit 0
else
    echo "FAIL: Loop devices leaked ($INITIAL_LOOPS -> $FINAL_LOOPS)"
    losetup -a | grep crashcart.img
    exit 1
fi