#!/bin/bash
set -euo pipefail

echo "Setting up test container for crashcart demo..."

# Start a minimal test container
CONTAINER_ID=$(docker run -d --name crashcart-test alpine:latest sleep 3600)
echo "Started test container: $CONTAINER_ID"

echo ""
echo "Container is running. You can now test crashcart:"
echo ""
echo "1. Build crashcart and image:"
echo "   make all"
echo ""
echo "2. Debug the container:"
echo "   sudo ./crashcart crashcart-test"
echo ""
echo "3. Or mount tools only:"
echo "   sudo ./crashcart -m crashcart-test"
echo "   docker exec -it crashcart-test /dev/crashcart/bin/bash"
echo ""
echo "4. Clean up when done:"
echo "   docker stop crashcart-test && docker rm crashcart-test"
echo ""
echo "The container will automatically stop after 1 hour."