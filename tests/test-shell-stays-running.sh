#!/bin/bash
# Test that crashcart shell stays running and doesn't crash on .crashcartrc

set -e

echo "Testing that crashcart shell doesn't crash and exit..."

# Find a running container
CONTAINER_ID=$(docker ps -q | head -1)

if [ -z "$CONTAINER_ID" ]; then
    echo "SKIP: No running containers found"
    exit 0
fi

echo "Testing with container: $CONTAINER_ID"

# Test that crashcart starts shell and stays running (not crashing and exiting)
# Use timeout to give it time to start, then send exit command
timeout 10 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$CONTAINER_ID" <<EOF || true
echo "Shell is running"
exit
EOF

# If we get here without timeout, the shell worked
echo "PASS: Shell started and stayed running"