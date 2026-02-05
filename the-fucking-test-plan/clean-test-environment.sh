#!/bin/bash
# Complete crashcart artifact removal for pristine testing
set -e

echo "=== CLEANING CRASHCART TEST ENVIRONMENT ==="

# Remove all crashcart files
echo "Removing crashcart artifacts..."
sudo rm -rf /tmp/crashcart* /var/tmp/crashcart* || true
rm -rf crashcart-ng-* crashcart*.tar.gz release-v* || true

# Clean loop devices
echo "Cleaning loop devices..."
sudo losetup -D || true

# Clean Docker
echo "Cleaning Docker system..."
docker system prune -f || true

# Remove any test containers
echo "Removing test containers..."
docker rm -f $(docker ps -aq --filter "name=test") 2>/dev/null || true

# Verify clean state
echo "Verifying clean environment..."

MOUNTS=$(mount | grep crashcart || true)
if [ -n "$MOUNTS" ]; then
    echo "❌ WARNING: Lingering crashcart mounts found:"
    echo "$MOUNTS"
else
    echo "✅ No crashcart mounts"
fi

LOOPS=$(losetup -a | grep crashcart || true)
if [ -n "$LOOPS" ]; then
    echo "❌ WARNING: Lingering crashcart loop devices:"
    echo "$LOOPS"
else
    echo "✅ No crashcart loop devices"
fi

FILES=$(find /tmp /var/tmp -name "*crashcart*" 2>/dev/null || true)
if [ -n "$FILES" ]; then
    echo "❌ WARNING: Lingering crashcart files:"
    echo "$FILES"
else
    echo "✅ No crashcart files found"
fi

echo
echo "🧹 Environment cleaned - ready for fresh testing"
echo "Next: Download crashcart-ng from GitHub as new user would"