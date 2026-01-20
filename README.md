# Modern Crashcart

> **⚠️ NOTE**: Please don't struggle deploying this yet - I need to test this a lot more. I just blogged about this, so needed to make the repo public today.

A modern, clean reimplementation of the crashcart container debugging tool. Crashcart allows you to sideload debugging utilities into running containers that don't have debugging tools installed.

## What is Crashcart?

Crashcart solves a common problem: **how do you debug a minimal container that doesn't have debugging tools?** Instead of rebuilding your container with debugging tools, crashcart mounts a filesystem image containing debugging utilities directly into the running container's namespace.

## Features

- **Modern Rust implementation** with async/await and proper error handling
- **Multiple container runtime support**: Docker, Podman, containerd
- **Complete Ubuntu debugging environment** with full glibc compatibility
- **Namespace-aware debugging** - tools run in isolated environment but access target resources
- **40+ debugging and system tools** including gdb, strace, tcpdump, and more
- **No library conflicts** - debugging tools use their own complete environment

## Quick Start

### 1. Build the tool

```bash
./build.sh --release
```

### 2. Build the debugging image

```bash
./build-image.sh
```

This creates a `crashcart.img` file containing a complete Ubuntu debugging environment.

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

# Debug it with crashcart (full Ubuntu environment available)
sudo ./crashcart test

# Inside crashcart, you have access to:
check-tools              # See all available debugging tools
debug-process 1          # Debug the main process with GDB
trace-process 1          # Trace system calls with strace
network-status           # Check network configuration
container-shell          # Get full shell in target container
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
# Debug network issues with full tool compatibility
sudo ./crashcart <container> -- debug-in-ns <pid> tcpdump -i any -n

# Check listening ports using namespace-aware tools
sudo ./crashcart <container>
# Inside: network-status

# Capture network traffic
# Inside: network-capture eth0

# Test connectivity with full glibc tools
# Inside: debug-in-ns <pid> curl -v google.com
```

### Process debugging
```bash
# Trace system calls with full glibc compatibility
sudo ./crashcart <container>
# Inside: trace-process 123

# Debug with GDB (full debugging symbols support)
# Inside: debug-process 123

# Monitor file access with complete lsof functionality
# Inside: list-files 123

# Advanced tracing options
# Inside: trace-network 123    # Network calls only
# Inside: trace-files 123      # File system calls only
```

## Available Tools

The crashcart image includes a complete Ubuntu 22.04 environment with:

### Debugging Tools
- `gdb` - GNU debugger with full symbol support
- `strace` - System call tracer
- `ltrace` - Library call tracer  
- `lsof` - List open files and network connections

### Network Tools
- `tcpdump` - Packet capture and analysis
- `ss`, `netstat` - Network connection information
- `nmap` - Network scanning and discovery
- `dig`, `nslookup` - DNS lookup utilities
- `curl`, `wget` - HTTP clients
- `netcat`, `socat` - Network utilities
- `iftop` - Network bandwidth monitoring

### System Tools
- `ps`, `top`, `htop` - Process monitoring
- `iotop` - I/O monitoring
- `free`, `df`, `du` - Memory and disk usage
- `kill`, `killall`, `pgrep`, `pkill` - Process management

### Development Tools
- `vim`, `nano` - Text editors
- `less`, `more` - File viewers
- `python3`, `perl` - Scripting languages
- `bash`, `zsh` - Advanced shells
- `tmux`, `screen` - Terminal multiplexers

### File Tools
- `tar`, `gzip`, `bzip2`, `zip` - Archive utilities
- `rsync` - File synchronization
- `tree` - Directory tree display
- `find`, `grep`, `awk`, `sed` - Text processing
- `file` - File type detection

### Utilities
- `jq` - JSON processor
- `openssl` - Cryptography tools
- `binutils` - Binary utilities
- `ca-certificates` - SSL certificates

## How It Works

1. **Container Detection**: Automatically detects Docker, Podman, or containerd containers
2. **PID Resolution**: Finds the main process PID of the target container
3. **Image Mounting**: Mounts a complete Ubuntu debugging environment as a loop device
4. **Namespace Management**: Uses Linux namespaces to provide isolated debugging environment
5. **Tool Execution**: Debugging tools run in their own environment but can access target container resources
6. **Library Compatibility**: Full glibc environment ensures all tools work regardless of target container's base image

## Requirements

- Linux with namespace support
- Root privileges (for namespace manipulation)
- One of: Docker, Podman, or containerd
- Loop device support (`/dev/loop*`)

## Architecture

The modern implementation is structured as:

- `src/main.rs` - CLI interface and main logic
- `src/container.rs` - Container runtime detection and interaction
- `src/image.rs` - Image and loop device management
- `src/mount.rs` - Filesystem mounting in namespaces
- `src/namespace.rs` - Linux namespace manipulation

## Differences from Original

This modern version improves on the original crashcart:

- **Complete debugging environment**: Full Ubuntu 22.04 with glibc compatibility
- **No library conflicts**: Tools run in isolated environment
- **Namespace-aware debugging**: Access target container resources without conflicts
- **Expanded toolkit**: 40+ tools vs original's 16
- **Better container support**: Works with multiple runtimes
- **Modern codebase**: Rust 2021 with proper error handling
- **Faster builds**: 3-5 minutes vs 20+ minutes (no Nix dependency)

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