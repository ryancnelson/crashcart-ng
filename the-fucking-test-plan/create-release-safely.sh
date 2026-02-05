#!/bin/bash
# Only create GitHub release after rigorous local validation
set -e

VERSION="$1"
TITLE="$2"
NOTES_FILE="$3"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> <title> [notes-file]"
    echo "Example: $0 v0.4.1-functions-working 'crashcart-ng v0.4.1 - Functions Working' release-notes.md"
    exit 1
fi

echo "=== SAFE RELEASE CREATION FOR $VERSION ==="

# Step 1: Rigorous local validation
echo "Step 1: Local validation..."
if ./tests/minimal-validation.sh; then
    echo "✅ Minimal validation passed (4/4)"
else
    echo "❌ Local validation FAILED - NOT creating release"
    echo "Fix issues before attempting release"
    exit 1
fi

# Step 2: Function validation
echo "Step 2: Function validation..."
TEST_CONTAINER=$(docker run -d --rm alpine:latest sleep 30)

FUNC_TEST='
echo "=== FUNCTION TEST ==="
for func in check_tools debug_process list_processes network_status sysinfo; do
    if type $func >/dev/null 2>&1; then
        echo "FUNC_OK: $func"
    else
        echo "FUNC_FAIL: $func"
        exit 1
    fi
done
echo "ALL_FUNCTIONS_OK"
exit
'

if echo "$FUNC_TEST" | timeout 20 sudo ./target/x86_64-unknown-linux-musl/release/crashcart "$TEST_CONTAINER" 2>&1 | grep -q "ALL_FUNCTIONS_OK"; then
    echo "✅ All functions work correctly"
    docker rm -f "$TEST_CONTAINER"
else
    echo "❌ Function validation FAILED - NOT creating release"
    docker rm -f "$TEST_CONTAINER"
    exit 1
fi

# Step 3: Build release artifacts
echo "Step 3: Building release artifacts..."
if [ ! -f "./prepare-release.sh" ]; then
    echo "❌ prepare-release.sh not found"
    exit 1
fi

# Update version in prepare-release.sh
sed -i "s/VERSION=.*/VERSION=\"$VERSION\"/" prepare-release.sh

if ./prepare-release.sh; then
    echo "✅ Release artifacts created"
else
    echo "❌ Release artifact creation FAILED"
    exit 1
fi

# Step 4: Git tag
echo "Step 4: Creating git tag..."
if git tag "$VERSION" -m "$TITLE" 2>/dev/null; then
    echo "✅ Git tag created: $VERSION"
    git push origin "$VERSION"
else
    echo "⚠️  Tag $VERSION already exists, using existing tag"
fi

# Step 5: Create GitHub release
echo "Step 5: Creating GitHub release..."
TARBALL="crashcart-ng-$VERSION.tar.gz"

if [ ! -f "$TARBALL" ]; then
    echo "❌ Release tarball not found: $TARBALL"
    exit 1
fi

if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    gh release create "$VERSION" "$TARBALL" --title "$TITLE" --notes-file "$NOTES_FILE"
else
    gh release create "$VERSION" "$TARBALL" --title "$TITLE" --notes "Automated release of $VERSION"
fi

echo "✅ GitHub release created: $VERSION"

# Step 6: Immediate validation of GitHub release
echo "Step 6: Validating GitHub release..."
sleep 5  # Allow GitHub to process

if ./validate-github-release.sh "$VERSION"; then
    echo "✅ GitHub release validation PASSED"
else
    echo "❌ GitHub release validation FAILED"
    echo "Release was created but has issues!"
    exit 1
fi

echo
echo "=== RELEASE CREATION SUCCESSFUL ==="
echo "Version: $VERSION"
echo "Status: ✅ SAFE RELEASE COMPLETED"
echo "GitHub: https://github.com/ryancnelson/crashcart-ng/releases/tag/$VERSION"
echo "Ready for: Public announcement and demo"
echo

echo "🎉 Safe release creation complete!"
echo "Users can now download $VERSION from GitHub with confidence."