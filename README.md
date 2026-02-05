# Modern Crashcart

A modern, clean reimplementation of the crashcart container debugging tool with **musl-based universal compatibility**. Crashcart allows you to sideload debugging utilities into running containers that don't have debugging tools installed.

✅ **Ready for production** - Thoroughly tested with comprehensive integration suite

## What is Crashcart?

Crashcart solves a common problem: **how do you debug a minimal container that doesn't have debugging tools?** Instead of rebuilding your container with debugging tools, crashcart mounts a filesystem image containing debugging utilities directly into the running container's namespace.

## Features

- **Modern Rust implementation** with async/await and proper error handling
- **Multiple container runtime support**: Docker, Podman, containerd
- **Universal musl-based compatibility** - works in ANY container (Alpine, scratch, distroless)
- **Self-contained with zero host dependencies** - complete static + musl environment
- **Comprehensive debugging toolkit** including network, process, and system analysis tools
- **Automatic cleanup** - loop devices and mounts cleaned up automatically on exit
- **Silent operation** - no error noise or cleanup spam
- **Production-ready** - thoroughly tested with comprehensive integration test suite

## Quick Start

### 1. Build the tool

```bash
# Build release version (recommended)
cargo build --release

# Or use the convenience script
./build.sh --release
```

### 2. Build the debugging image

```bash
./build-image-musl.sh
```

This creates a `crashcart.img` file containing a self-contained musl-based debugging environment that works universally across all container types (Alpine, Ubuntu, scratch, distroless).

### 3. Debug a container

```bash
# Interactive debugging session
sudo ./crashcart <container-id>

# Mount tools only (no shell)
sudo ./crashcart -m <container-id>

# Use container runtime exec instead of namespaces
sudo ./crashcart -e <container-id>

# Run specific command
sudo ./crashcart <container-id> -- strace -p 1

# Unmount when done
sudo ./crashcart -u <container-id>
```

## Usage Examples

### Debug a Docker container
```bash
# Start a minimal container
docker run -d --name test alpine:latest sleep 3600

# Debug it with crashcart (musl-based debugging environment)
sudo ./crashcart test

# Inside crashcart, you have access to:
ls /dev/crashcart/bin     # Static BusyBox tools
ls /dev/crashcart/usr/bin # Musl-based debugging tools
gdb -p 1                  # Debug the main process
strace -p 1               # Trace system calls
lsof -p 1                 # List open files
htop                      # Interactive process monitor
```

### Debug a Podman container
```bash
podman run -d --name test alpine:latest sleep 3600
sudo ./crashcart test
```

### Debug by PID
```bash
# Find the container's main process PID
docker inspect --format '{{.State.Pid}}' <container>

# Debug directly by PID
sudo ./crashcart 12345
```

### Network debugging
```bash
# Debug network issues with musl-compatible tools
sudo ./crashcart <container>

# Inside crashcart:
tcpdump -i any -n           # Capture packets
ss -tuln                    # Show listening sockets
lsof -i                     # Network connections by process
nmap -sT localhost          # Port scanning
curl -v google.com          # HTTP connectivity test
socat -                     # Advanced network relay
```

### Process debugging
```bash
# Debug processes with musl-based tools
sudo ./crashcart <container>

# Inside crashcart:
gdb -p 123                  # Attach debugger to process
strace -p 123               # Trace system calls
ltrace -p 123               # Trace library calls
lsof -p 123                 # Show open files for process
htop                        # Interactive process monitor
psinspect                   # Custom static process inspector
kill -USR1 123              # Send signals to processes
```

## Available Tools

The crashcart musl image includes a self-contained debugging environment with:

### Static Foundation (BusyBox)
- `ash`, `sh` - POSIX shell
- `ps`, `top`, `kill` - Process management
- `ls`, `cat`, `cp`, `mv`, `rm`, `find`, `grep` - File operations
- `tar`, `gzip`, `gunzip` - Archive utilities
- `mount`, `umount` - Filesystem operations
- `ping`, `traceroute`, `nc`, `wget` - Basic network tools

### Musl-based Debugging Tools
- `gdb` - GNU debugger with musl compatibility
- `strace` - System call tracer
- `ltrace` - Library call tracer
- `lsof` - List open files and network connections

### Network Analysis
- `tcpdump` - Packet capture and analysis with libpcap
- `nmap` - Network scanning and discovery
- `socat` - Advanced network relay
- `ss`, `netstat` - Network connection information
- `ip` - Advanced IP routing utilities
- `dig`, `nslookup` - DNS lookup utilities
- `curl` - Static HTTP client

### System Monitoring
- `htop` - Interactive process viewer
- `iotop` - I/O monitoring
- `iftop` - Network bandwidth monitoring

### Development Tools
- `vim`, `nano` - Text editors with musl compatibility
- `less` - Advanced file viewer
- `bash` - Advanced shell (ash recommended)
- `jq` - JSON processor
- `file` - File type detection
- `tree` - Directory tree display

### File Tools
- `rsync` - File synchronization
- `bzip2`, `xz` - Compression utilities
- `openssl` - Cryptography and SSL tools

### Custom Tools
- `psinspect` - Custom static process inspector

All tools are either statically linked or use bundled musl libraries for universal compatibility.

## How It Works

1. **Container Detection**: Automatically detects Docker, Podman, or containerd containers
2. **PID Resolution**: Finds the main process PID of the target container
3. **Self-Contained Mounting**: Mounts a musl-based debugging environment with bundled libraries
4. **Universal Compatibility**: Static BusyBox + musl tools work in any container (Alpine, scratch, distroless)
5. **Automatic Cleanup**: Loop devices and mount points cleaned up automatically on exit
6. **Zero Dependencies**: No host library dependencies - works even in containers with no libraries at all

### The Musl Advantage

- **Universal compatibility**: Works in Alpine, Ubuntu, scratch, distroless - any container type
- **No glibc conflicts**: Musl-based tools don't conflict with container's libc
- **Self-contained**: All required libraries bundled using ldd dependency discovery
- **Smaller footprint**: More efficient than full Ubuntu environment
- **Faster builds**: Alpine-based builds complete in minutes, not hours

## Requirements

- Linux with namespace support
- Root privileges (for namespace manipulation)
- One of: Docker, Podman, or containerd
- Loop device support (`/dev/loop*`)

## Testing

Crashcart includes a comprehensive test suite to ensure reliability:

### Test Suite
```bash
# Run individual tests
./tests/test-library-bundling.sh     # Verify 15+ libraries bundled
./tests/test-shell-execution.sh      # Test BusyBox command execution
./tests/test-cleanup.sh              # Verify loop device cleanup
./tests/test-quiet-cleanup.sh        # Ensure no error noise
./tests/integration-musl.sh          # Full 6-test integration suite

# The integration suite tests:
# 1. Mount crashcart successfully
# 2. Verify mount point in container
# 3. Test static BusyBox functionality
# 4. Test musl tools with bundled libraries
# 5. Verify compatibility in minimal Alpine containers
# 6. Confirm zero dependencies in scratch/busybox containers
```

### Test-Driven Development
This project follows TDD methodology:
- ✅ Write failing tests first
- ✅ Implement minimal fix
- ✅ Verify tests pass
- ✅ Git commit after each success
- ✅ Integration tests with real containers

### Production Validation
Successfully tested in:
- AWS ECS container hosts
- Docker containers (Alpine, Ubuntu, busybox)
- Minimal/scratch containers
- Real production workloads (gemstash, etc.)

## Architecture

The modern implementation is structured as:

- `src/main.rs` - CLI interface and main logic
- `src/container.rs` - Container runtime detection and interaction
- `src/image.rs` - Image and loop device management
- `src/mount.rs` - Filesystem mounting in namespaces
- `src/namespace.rs` - Linux namespace manipulation

## Differences from Original

This modern version improves on the original crashcart:

- **Universal musl compatibility**: Works in ANY container type (Alpine, scratch, distroless)
- **Self-contained design**: Zero host dependencies, bundled libraries
- **Automatic cleanup**: Loop devices and mounts cleaned up on exit
- **Silent operation**: No error noise or cleanup spam
- **Comprehensive testing**: Full integration test suite with real containers
- **Production-ready**: Thoroughly tested and deployed
- **Modern codebase**: Rust 2021 with async/await and proper error handling
- **Faster builds**: 3-5 minutes vs 20+ minutes (Alpine-based, no Nix dependency)
- **Better container support**: Docker, Podman, containerd detection
- **Proven compatibility**: Successfully tested in AWS ECS, Alpine, Ubuntu containers

## Credits and History

This project is a **reimplementation from specifications** inspired by the original [crashcart](https://github.com/oracle/crashcart) created by **TJ Fontaine** and **Vish Abrams** at Oracle Cloud Infrastructure (circa 2015-2017). This is not a fork - it's a fresh implementation built from the ground up using modern tools and practices. (I don't know if this qualifies legally as a "clean room" reimplementation, but it was built by studying the original tool's behavior and creating new specifications from that understanding.)

### The Origin Story

**TJ Fontaine** and **Vish Abrams** created and built the original crashcart at Oracle Cloud Infrastructure. The tool elegantly solved a real problem: how to debug minimal containers without rebuilding them with debugging tools.

The name "crashcart" comes from the physical crash carts used in datacenters - wheeled toolkits containing monitors, keyboards, serial terminals, voltmeters, and other diagnostic equipment that technicians would roll up to server racks for troubleshooting. Like crash carts in hospital emergency rooms, these are mobile collections of resuscitative tools to bring systems back to life.

According to my recollection, I was present during early lunch discussions at Joyent (with TJ and others) where we talked about the need for container debugging toolkits, and the datacenter crash cart analogy may have come up in those conversations. But the actual crashcart tool - the brilliant implementation and execution - that was all TJ and Vish.

### Why a Reimplementation?

The original crashcart served its purpose well, but became difficult to maintain:
- Nix-based builds (Ubuntu 16.04, Nix 1.11.15 from 2017) no longer build cleanly
- Package sources and dependencies became unavailable over time
- Build times exceeded 20 minutes
- Limited to 16 basic tools

This reimplementation preserves the core concept and CLI interface while:
- Adopting modern Rust practices (Rust 2021, async/await, proper error handling)
- Expanding to 40+ debugging tools with multi-runtime support
- Simplifying builds using containerized approaches (3-5 minutes)
- Improving developer experience with comprehensive documentation

Much of the reimplementation work was accomplished with AI-assisted development.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

Licensed under either of:
- Apache License, Version 2.0
- MIT License

at your option.

Original crashcart project by Oracle: [UPL 1.0](https://opensource.org/licenses/UPL) / Apache 2.0