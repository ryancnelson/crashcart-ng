#!/bin/bash
set -euo pipefail

echo "Building modern crashcart..."

# Build the Rust binary
if [[ "${1:-}" == "--release" ]]; then
    echo "Building release version..."
    cargo build --release
    cp target/release/crashcart .
else
    echo "Building debug version..."
    cargo build
    cp target/debug/crashcart .
fi

echo "Build complete! Binary: ./crashcart"
echo
echo "Next steps:"
echo "1. Build the debugging image: ./build-image.sh"
echo "2. Run crashcart: sudo ./crashcart <container-id>"