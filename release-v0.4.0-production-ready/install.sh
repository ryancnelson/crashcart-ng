#!/bin/bash
# crashcart-ng installation script
set -e

echo "Installing crashcart-ng..."

# Check requirements
if [ "$EUID" -eq 0 ]; then
    echo "❌ Do not run as root - crashcart will request sudo when needed"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker not found - please install Docker first"
    exit 1
fi

# Install binary
sudo cp crashcart /usr/local/bin/
sudo chmod +x /usr/local/bin/crashcart

# Install image
sudo mkdir -p /usr/local/share/crashcart
sudo cp crashcart.img /usr/local/share/crashcart/

echo "✅ crashcart-ng installed successfully!"
echo
echo "Usage: sudo crashcart <container-id>"
echo "Documentation: cat README.md"
