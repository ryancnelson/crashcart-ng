.PHONY: build build-release build-image clean install test help

# Default target
help:
	@echo "Modern Crashcart Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  build         - Build debug version"
	@echo "  build-release - Build optimized release version"
	@echo "  build-image   - Build the crashcart debugging image"
	@echo "  install       - Install crashcart to /usr/local/bin (requires sudo)"
	@echo "  clean         - Clean build artifacts"
	@echo "  test          - Run tests"
	@echo "  all           - Build both binary and image"
	@echo ""
	@echo "Quick start:"
	@echo "  make all                    # Build everything"
	@echo "  sudo ./crashcart <container-id>  # Debug a container"

# Build debug version
build:
	@echo "Building debug version..."
	cargo build
	cp target/debug/crashcart .
	@echo "Debug build complete: ./crashcart"

# Build release version
build-release:
	@echo "Building release version..."
	cargo build --release
	cp target/release/crashcart .
	@echo "Release build complete: ./crashcart"

# Build the debugging image
build-image:
	@echo "Building crashcart debugging image (Ubuntu-based)..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: Docker is required to build the image"; \
		exit 1; \
	fi
	./build-image.sh
	@echo "Image build complete: crashcart.img (Ubuntu 22.04 environment)"

# Build everything
all: build-release build-image
	@echo ""
	@echo "Build complete!"
	@echo "Binary: ./crashcart"
	@echo "Image:  ./crashcart.img (Ubuntu 22.04 debugging environment)"
	@echo ""
	@echo "Usage: sudo ./crashcart <container-id>"
	@echo "Inside crashcart: check-tools, debug-process 123, trace-process 123"

# Install to system
install: build-release
	@echo "Installing crashcart to /usr/local/bin..."
	sudo cp crashcart /usr/local/bin/
	sudo chmod +x /usr/local/bin/crashcart
	@echo "Installation complete!"
	@echo "You can now run: sudo crashcart <container-id>"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -f crashcart crashcart.img
	rm -rf vol/
	@echo "Clean complete"

# Run tests
test:
	@echo "Running tests..."
	cargo test
	@echo "Tests complete"

# Development helpers
check:
	@echo "Checking code..."
	cargo check
	cargo clippy -- -D warnings
	cargo fmt --check

fmt:
	@echo "Formatting code..."
	cargo fmt

# Quick development cycle
dev: check build
	@echo "Development build ready"