#!/bin/bash
# Test that libraries are properly bundled in crashcart.img

set -e

echo "Testing library bundling in crashcart.img..."

# Mount the image
MOUNT_DIR=$(mktemp -d)
sudo losetup -d /dev/loop50 2>/dev/null || true
sudo losetup /dev/loop50 crashcart.img
sudo mount /dev/loop50 "$MOUNT_DIR"

# Check for musl loader
if [ ! -f "$MOUNT_DIR/lib/ld-musl-x86_64.so.1" ]; then
    echo "FAIL: musl loader not found"
    sudo umount "$MOUNT_DIR"
    sudo losetup -d /dev/loop50
    exit 1
fi
echo "PASS: musl loader found"

# Check for readline (critical for bash)
READLINE_COUNT=$(find "$MOUNT_DIR/lib" -name "libreadline.so.*" | wc -l)
if [ "$READLINE_COUNT" -eq 0 ]; then
    echo "FAIL: readline library not found"
    sudo umount "$MOUNT_DIR"
    sudo losetup -d /dev/loop50
    exit 1
fi
echo "PASS: readline library found ($READLINE_COUNT files)"

# Check for ncurses (needed by many tools)
NCURSES_COUNT=$(find "$MOUNT_DIR/lib" -name "libncurses*.so.*" | wc -l)
if [ "$NCURSES_COUNT" -eq 0 ]; then
    echo "FAIL: ncurses library not found"
    sudo umount "$MOUNT_DIR"
    sudo losetup -d /dev/loop50
    exit 1
fi
echo "PASS: ncurses library found ($NCURSES_COUNT files)"

# Check total library count (should be > 10 for basic functionality)
LIB_COUNT=$(find "$MOUNT_DIR/lib" -name "*.so*" | wc -l)
if [ "$LIB_COUNT" -lt 10 ]; then
    echo "FAIL: Only $LIB_COUNT libraries found (expected > 10)"
    sudo umount "$MOUNT_DIR"
    sudo losetup -d /dev/loop50
    exit 1
fi
echo "PASS: $LIB_COUNT libraries found (sufficient for basic functionality)"

# Cleanup
sudo umount "$MOUNT_DIR"
sudo losetup -d /dev/loop50
rm -rf "$MOUNT_DIR"

echo "All library bundling tests passed!"
