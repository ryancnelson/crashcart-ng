#!/bin/bash
# Download and validate latest crashcart-ng GitHub release
set -e

VERSION=${1:-"latest"}
REPO="ryancnelson/crashcart-ng"

echo "=== VALIDATING GITHUB RELEASE: $VERSION ==="

if [ "$VERSION" = "latest" ]; then
    echo "Getting latest release info..."
    VERSION=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    echo "Latest version: $VERSION"
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/crashcart-ng-$VERSION.tar.gz"

echo "Downloading: $DOWNLOAD_URL"
curl -L "$DOWNLOAD_URL" -o "test-release-$VERSION.tar.gz"

echo "Extracting release..."
tar -xzf "test-release-$VERSION.tar.gz"
cd "crashcart-ng-$VERSION/"

echo "=== BASIC VALIDATION ==="

# Check required files exist
echo "Checking release contents..."
for file in crashcart crashcart.img README.md; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ MISSING: $file"
        exit 1
    fi
done

# Check binary works
echo "Testing binary execution..."
if ./crashcart --version 2>/dev/null | grep -q "crashcart"; then
    echo "✅ Binary executes and shows version"
else
    echo "❌ Binary execution failed"
    exit 1
fi

# Start test container
echo "Starting test container..."
TEST_CONTAINER=$(docker run -d --name validation-test alpine:latest sleep 60)
echo "Test container: $TEST_CONTAINER"

# Test basic mount
echo "Testing basic mount functionality..."
if echo 'echo "MOUNT_SUCCESS"; exit' | timeout 15 sudo ./crashcart validation-test 2>&1 | grep -q "MOUNT_SUCCESS"; then
    echo "✅ Basic mount and shell work"
else
    echo "❌ Basic mount failed"
    docker rm -f validation-test
    exit 1
fi

# Test function availability
echo "Testing crashcart functions..."
FUNCTION_TEST='
for func in check_tools debug_process list_processes network_status; do
    if type $func >/dev/null 2>&1; then
        echo "FUNCTION_OK: $func"
    else
        echo "FUNCTION_MISSING: $func"
    fi
done
exit
'

FUNCTION_OUTPUT=$(echo "$FUNCTION_TEST" | timeout 15 sudo ./crashcart validation-test 2>&1)

MISSING_FUNCTIONS=$(echo "$FUNCTION_OUTPUT" | grep "FUNCTION_MISSING" || true)
if [ -n "$MISSING_FUNCTIONS" ]; then
    echo "❌ MISSING FUNCTIONS:"
    echo "$MISSING_FUNCTIONS"
    docker rm -f validation-test
    exit 1
else
    echo "✅ All declared functions available"
fi

# Test tools availability
echo "Testing debugging tools..."
TOOLS_TEST='
for tool in gdb strace lsof ps htop; do
    if command -v $tool >/dev/null 2>&1; then
        echo "TOOL_OK: $tool"
    else
        echo "TOOL_MISSING: $tool"
    fi
done
exit
'

TOOLS_OUTPUT=$(echo "$TOOLS_TEST" | timeout 15 sudo ./crashcart validation-test 2>&1)

MISSING_TOOLS=$(echo "$TOOLS_OUTPUT" | grep "TOOL_MISSING" || true)
if [ -n "$MISSING_TOOLS" ]; then
    echo "⚠️  WARNING: Missing tools:"
    echo "$MISSING_TOOLS"
else
    echo "✅ All essential tools available"
fi

# Cleanup
docker rm -f validation-test

echo
echo "=== VALIDATION RESULTS ==="
echo "Version: $VERSION"
echo "Status: ✅ GITHUB RELEASE VALIDATED"
echo "Ready for: Demo and production use"
echo

cd ..
rm -rf "crashcart-ng-$VERSION/" "test-release-$VERSION.tar.gz"

echo "🎉 GitHub release $VERSION is ready for use!"