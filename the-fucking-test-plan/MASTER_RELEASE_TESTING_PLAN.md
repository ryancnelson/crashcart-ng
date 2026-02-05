# Master Crashcart-ng Release Testing Plan

**Purpose:** Ensure every GitHub release actually works as claimed, with no false success declarations.

**Core Principle:** Test what users get from GitHub, not what works locally.

---

## 🚨 Critical Rules

### Rule #1: GitHub-First Testing
- **NEVER** test local artifacts after creating GitHub release
- **ALWAYS** download from GitHub for testing
- **NO SHORTCUTS** - no direct binary copying to test systems

### Rule #2: Notice Failures Immediately
- If documented function doesn't work → STOP, FIX, RE-RELEASE
- If claimed tool is missing → STOP, FIX, RE-RELEASE
- If demo shows errors → STOP, FIX, RE-RELEASE

### Rule #3: Pristine Environment
- Start every test from completely clean state
- Simulate fresh user who never heard of crashcart-ng
- No residual artifacts from previous testing

---

## 📋 Testing Methodology

### Phase 1: Local Pre-Release Validation

**Before creating any GitHub release:**

1. **Build and Test Locally**
   ```bash
   cargo build --release --target x86_64-unknown-linux-musl
   ./build-image-musl.sh
   ./tests/minimal-validation.sh  # Must pass 4/4
   ```

2. **Function Validation Test**
   ```bash
   # Test ALL claimed functions work
   echo 'check_tools; debug_process 1; list_processes; network_status; exit' | \
   sudo ./target/x86_64-unknown-linux-musl/release/crashcart test-container
   ```

3. **Documentation Accuracy Check**
   - Every README example must work exactly as written
   - All startup message claims must be true
   - No function should be "not found"

### Phase 2: GitHub Release Creation

**Only after Phase 1 passes 100%:**

1. **Version Management**
   ```
   v0.4.0 - BROKEN (known issues)
   v0.4.1 - Functions fix attempt
   v0.4.2 - Next iteration if needed
   ```

2. **Release Process**
   ```bash
   # Update version
   git tag v0.4.1-functions-working -m "Fix: .crashcartrc functions now load properly"
   git push origin v0.4.1-functions-working

   # Create release artifacts
   ./prepare-release.sh

   # GitHub release with artifacts
   gh release create v0.4.1-functions-working \
     crashcart-ng-v0.4.1-functions-working.tar.gz \
     --title "crashcart-ng v0.4.1 - Functions Working" \
     --notes-file release-notes.md
   ```

### Phase 3: Clean Environment Testing

**Complete environment reset:**

1. **System Cleanup**
   ```bash
   # Remove ALL crashcart artifacts
   sudo rm -rf /tmp/crashcart* /var/tmp/crashcart*
   sudo losetup -D
   docker system prune -f

   # Verify clean state
   mount | grep crashcart  # Should be empty
   losetup -a | grep crashcart  # Should be empty
   ```

2. **Fresh User Simulation**
   - Pretend never heard of crashcart-ng
   - Visit GitHub releases page
   - Download latest release
   - Follow README instructions exactly

### Phase 4: GitHub Release Validation

**Test the actual GitHub release:**

1. **Download and Extract**
   ```bash
   curl -L https://github.com/ryancnelson/crashcart-ng/releases/download/v0.4.1-functions-working/crashcart-ng-v0.4.1-functions-working.tar.gz -o crashcart.tar.gz
   tar -xzf crashcart.tar.gz
   cd crashcart-ng-v0.4.1-functions-working/
   ```

2. **Level 1: Basic Functionality**
   ```bash
   # Binary works
   ./crashcart --version

   # Can mount any container
   docker run -d --name test alpine:latest sleep 30
   sudo ./crashcart test
   ```

3. **Level 2: Documented Features**
   ```bash
   # ALL these must work (no "not found" errors):
   check_tools
   debug_process 1
   trace_process 1
   list_processes
   network_status
   sysinfo
   ```

4. **Level 3: Real Scenarios**
   - Debug actual container problem
   - Use gdb, strace, tcpdump in workflow
   - Verify tools work together
   - Test error handling

---

## 🎯 Validation Checklists

### ✅ Pre-Release Checklist
- [ ] Local build successful
- [ ] All tests pass (4/4 score)
- [ ] Every function in startup message works
- [ ] All claimed tools available (gdb, strace, lsof, etc.)
- [ ] Documentation examples work exactly as written
- [ ] No syntax errors or crashes

### ✅ GitHub Release Checklist
- [ ] Version tagged and pushed
- [ ] Release artifacts created
- [ ] GitHub release published
- [ ] Download URL works
- [ ] Release notes accurate

### ✅ Clean Environment Test Checklist
- [ ] All crashcart artifacts removed
- [ ] No lingering mounts or loop devices
- [ ] Fresh container environment
- [ ] No previous test contamination

### ✅ Function Validation Checklist
- [ ] `check_tools` - Shows available tools
- [ ] `debug_process` - Available and callable
- [ ] `trace_process` - Available and callable
- [ ] `list_processes` - Shows container processes
- [ ] `network_status` - Shows network info
- [ ] `sysinfo` - Comprehensive system overview

### ✅ Demo Excellence Checklist
- [ ] Every command works as documented
- [ ] No error messages during demo
- [ ] Impressive debugging scenario
- [ ] All features showcase properly
- [ ] Professional presentation quality

---

## 🔄 Iteration Protocol

### When Release is Broken:

1. **STOP** - Don't continue demo or make excuses
2. **ACKNOWLEDGE** - Document exact failure clearly
3. **INVESTIGATE** - Find root cause of issue
4. **FIX** - Address underlying problem in code
5. **VERSION BUMP** - Increment to next version
6. **RE-RELEASE** - Create new GitHub release
7. **CLEAN TEST** - Start from pristine environment
8. **VALIDATE** - Ensure fix actually works
9. **ONLY THEN** proceed with demo/claims

### Success Criteria:
- **100%** of documented functions work
- **0** error messages in normal usage
- **All** claimed tools available and functional
- **Perfect** demo execution from GitHub release

---

## 🛠️ Required Automation Scripts

### `clean-test-environment.sh`
```bash
#!/bin/bash
# Complete crashcart artifact removal
sudo rm -rf /tmp/crashcart* /var/tmp/crashcart*
sudo losetup -D
docker system prune -f
echo "Environment cleaned - ready for fresh testing"
```

### `validate-github-release.sh`
```bash
#!/bin/bash
# Download and test latest GitHub release
VERSION=$1
curl -L "https://github.com/ryancnelson/crashcart-ng/releases/download/$VERSION/crashcart-ng-$VERSION.tar.gz" -o test-release.tar.gz
tar -xzf test-release.tar.gz
cd "crashcart-ng-$VERSION/"

# Run complete validation
./tests/validate-functions.sh
echo "GitHub release validation complete"
```

### `create-release-safely.sh`
```bash
#!/bin/bash
# Only create GitHub release after local validation
if ./tests/minimal-validation.sh; then
    echo "✅ Local validation passed - creating GitHub release"
    ./prepare-release.sh
    gh release create "$1" "crashcart-ng-$1.tar.gz" --title "$2" --notes-file "$3"
else
    echo "❌ Local validation failed - NOT creating release"
    exit 1
fi
```

---

## 🎭 Demo Execution Standards

### Pre-Demo Requirements:
- [ ] Clean environment verified
- [ ] Latest GitHub release validated
- [ ] All functions tested and working
- [ ] Interesting container scenario prepared
- [ ] Demo script rehearsed and flawless

### Demo Sequence:
1. **Discovery** - "I found this crashcart-ng tool on GitHub"
2. **Download** - Get latest release using documented method
3. **Basic Usage** - Follow README instructions exactly
4. **Feature Showcase** - Demonstrate key debugging functions
5. **Real Scenario** - Solve actual container problem
6. **Impressive Finish** - Show advanced debugging capabilities

### Quality Standards:
- **Every command works first try**
- **No errors, retries, or "let me try something else"**
- **Professional presentation throughout**
- **Demonstrates clear value proposition**

---

## 📊 Success Metrics

### Release Quality:
- **4/4** validation score maintained
- **100%** function availability
- **0** broken documentation examples
- **Flawless** demo execution

### User Experience:
- **Clear** installation instructions
- **Intuitive** debugging workflows
- **Reliable** operation across container types
- **Professional** error handling and messages

---

**This plan ensures crashcart-ng releases actually work as claimed, with rigorous testing that catches issues before users encounter them.**