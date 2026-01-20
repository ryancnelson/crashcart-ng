# Containerized Debugging Approach

This document explains the containerized approach used in modern crashcart and why it solves the library compatibility issues.

## The Problem with Traditional Approaches

When debugging tools are mounted into a container, they face several challenges:

### 1. Library Incompatibility
```bash
# Alpine container with musl libc
/dev/crashcart/bin/gdb  # Compiled for glibc, won't work

# Ubuntu container with different glibc version
/dev/crashcart/bin/strace  # May fail due to version mismatch
```

### 2. Missing Dependencies
```bash
# Target container missing required libraries
/dev/crashcart/bin/tcpdump  # Needs libpcap, may not be available
```

### 3. Conflicting Environments
```bash
# LD_LIBRARY_PATH conflicts
export LD_LIBRARY_PATH="/dev/crashcart/lib:$LD_LIBRARY_PATH"
# May break target container's own binaries
```

## The Containerized Solution

Modern crashcart uses a **containerized debugging approach** that solves these issues:

### 1. Complete Environment Isolation

The crashcart image contains a **complete Ubuntu 22.04 environment**:
```
/dev/crashcart/
├── bin/           # All Ubuntu binaries
├── sbin/          # System binaries  
├── usr/           # User space tools
├── lib/           # Complete glibc libraries
├── lib64/         # 64-bit libraries
├── etc/           # Configuration files
└── var/           # Variable data
```

### 2. Namespace-Aware Execution

Tools run in **crashcart's environment** but access **target's resources**:

```bash
# debug-in-ns script does:
nsenter -t $TARGET_PID -p -n -i -u -- \
    chroot /dev/crashcart \
    env PATH=/bin:/sbin:/usr/bin:/usr/sbin \
    LD_LIBRARY_PATH=/lib:/lib64:/usr/lib:/usr/lib64 \
    $COMMAND
```

This means:
- **Process namespace**: See target container's processes
- **Network namespace**: Access target container's network
- **Mount namespace**: Use crashcart's filesystem and libraries
- **User/IPC namespaces**: Access target container's resources

### 3. Smart Wrapper Scripts

Crashcart provides intelligent wrappers:

```bash
# gdb-attach script
debug-process() {
    local pid=${1:-1}
    debug-in-ns "$TARGET_PID" gdb -p "$pid"
}

# strace-attach script  
trace-process() {
    local pid=${1:-1}
    debug-in-ns "$TARGET_PID" strace -p "$pid" "${@:2}"
}
```

## How It Works in Practice

### Debugging Scenario
```bash
# 1. Start crashcart
sudo ./crashcart my-alpine-container

# 2. Inside crashcart (Ubuntu environment)
debug-process 123
```

**What happens:**
1. `debug-process` calls `debug-in-ns`
2. `nsenter` enters target container's PID namespace
3. `chroot` switches to crashcart's Ubuntu filesystem
4. `gdb` runs with full glibc support
5. GDB can see and debug PID 123 in the target container

### Network Debugging Scenario
```bash
# Inside crashcart
network-capture eth0
```

**What happens:**
1. `network-capture` calls `debug-in-ns`
2. `nsenter` enters target's network namespace
3. `tcpdump` runs from crashcart's Ubuntu environment
4. Can capture packets on target's network interfaces

## Benefits of This Approach

### ✅ **Full Compatibility**
- All tools work regardless of target container's base image
- No library version conflicts
- Complete debugging capabilities

### ✅ **Isolation**
- Debugging tools don't interfere with target container
- Target container's environment remains unchanged
- No risk of breaking target applications

### ✅ **Comprehensive Toolset**
- Complete Ubuntu 22.04 debugging environment
- 40+ tools with full functionality
- Python, Perl, advanced shells available

### ✅ **Easy to Extend**
- Add new tools by updating the Ubuntu container
- No need to worry about static compilation
- Full package manager available during build

## Trade-offs

### ❌ **Larger Image Size**
- 300MB vs 50-100MB for minimal approaches
- But storage is cheap, debugging capability is valuable

### ❌ **More Complex**
- Requires understanding of namespace manipulation
- More moving parts than simple mounting

### ❌ **Higher Memory Usage**
- Complete environment uses more RAM
- But only during debugging sessions

## Comparison with Alternatives

| Approach | Size | Compatibility | Complexity | Tools |
|----------|------|---------------|------------|-------|
| **Static binaries** | 50MB | High | Low | Limited |
| **Alpine + musl** | 100MB | Medium | Low | Medium |
| **Containerized** | 300MB | **Highest** | Medium | **Complete** |

## Implementation Details

### Image Building
```bash
# Uses complete Ubuntu container
docker run --rm -v "$MOUNT_DIR:/output" ubuntu:22.04 sh -c '
    apt-get update && apt-get install -y [40+ packages]
    cp -a /bin /sbin /usr /lib /lib64 /etc /var /output/
'
```

### Runtime Execution
```bash
# Namespace bridging
nsenter -t $TARGET_PID -p -n -i -u -- \
    chroot /dev/crashcart \
    env [crashcart environment] \
    $DEBUGGING_COMMAND
```

### Environment Variables
```bash
# Crashcart knows about target
export CRASHCART_TARGET_PID=12345

# Tools can reference target PID
debug-process() {
    debug-in-ns "$CRASHCART_TARGET_PID" gdb -p "$1"
}
```

## Conclusion

The containerized approach provides the **best debugging experience** by:

1. **Eliminating library conflicts** through complete environment isolation
2. **Providing full tool compatibility** with glibc-based debugging tools
3. **Maintaining access** to target container resources via namespaces
4. **Enabling easy extension** with new debugging tools

While it uses more disk space and memory, the trade-off is worth it for reliable, comprehensive debugging capabilities that work with any target container.

This approach makes crashcart a **universal debugging solution** that works consistently across different container base images, from Alpine to Ubuntu to custom distributions.