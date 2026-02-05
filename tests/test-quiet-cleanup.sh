#!/bin/bash
# Test that crashcart unmount is quiet (no error spam)

set -e

echo "Testing quiet cleanup during unmount..."

# Find a running container
CONTAINER_ID=$(docker ps -q | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP: No running containers found"
    exit 0
fi

echo "Testing with container: $CONTAINER_ID"

# Test interactive session termination (where the noise happens)
# Start crashcart and immediately send Ctrl+C to exit
timeout 3 sudo ./crashcart "$CONTAINER_ID" 2>/tmp/cleanup-errors.log >/dev/null || true

# Check if there are "can't remove" errors in both stdout and stderr
ERROR_COUNT=$(grep -c "can't remove" /tmp/cleanup-errors.log 2>/dev/null || true)

# Also check if timeout captured the output correctly
if [ ! -s /tmp/cleanup-errors.log ]; then
    # Fallback: try mount-only and let cleanup happen automatically
    sudo ./crashcart -m "$CONTAINER_ID" >/dev/null 2>/tmp/cleanup-errors.log
    ERROR_COUNT=$(grep -c "can't remove" /tmp/cleanup-errors.log 2>/dev/null || true)
fi

if [ "$ERROR_COUNT" -gt 0 ]; then
    echo "FAIL: Found $ERROR_COUNT 'can't remove' error messages"
    echo "Sample errors:"
    head -5 /tmp/cleanup-errors.log
    rm /tmp/cleanup-errors.log
    exit 1
else
    echo "PASS: Clean unmount with no error messages"
    rm /tmp/cleanup-errors.log
    exit 0
fi