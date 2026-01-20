# Getting Started with Modern Crashcart

This guide will help you get up and running with modern crashcart quickly.

## Prerequisites

- Linux system with namespace support
- Root privileges (for namespace manipulation)
- Docker (for building the debugging image)
- Rust toolchain (for building from source)

## Quick Start

### 1. Build Everything

```bash
# Build both the binary and debugging image
make all
```

This will:
- Compile the Rust binary in release mode
- Create a complete Ubuntu 22.04 debugging environment
- Take about 3-5 minutes on first run

### 2. Test with a Container

```bash
# Start a test container
./examples/test-container.sh

# Debug the container
sudo ./crashcart crashcart-test
```

You'll get an interactive bash shell with debugging tools available.

### 3. Explore Available Tools

Once inside the crashcart environment:

```bash
# Check available tools
check-tools

# System information
sysinfo

# Debug a specific process
debug-process 123        # Attach GDB to PID 123
trace-process 123        # Trace system calls for PID 123
trace-network 123        # Trace network calls only
list-files 123           # Show open files for PID 123

# Network debugging
network-status           # Show network configuration
network-capture eth0     # Capture packets on interface

# Get full shell in target container (with all tools available)
container-shell
```

## Common Use Cases

### Debug Network Issues

```bash
# Check what ports are listening
sudo ./crashcart <container> -- ss -tln

# Capture network traffic
sudo ./crashcart <container> -- tcpdump -i any -n

# Test connectivity
sudo ./crashcart <container> -- nc -zv google.com 80
```

### Debug Process Issues

```bash
# Trace system calls
sudo ./crashcart <container> -- strace -p 1

# Debug with GDB
sudo ./crashcart <container> -- gdb -p 1

# Monitor file access
sudo ./crashcart <container> -- lsof -p 1
```

### Debug Performance Issues

```bash
# Interactive process monitor
sudo ./crashcart <container> -- htop

# I/O monitoring
sudo ./crashcart <container> -- iotop

# Network monitoring
sudo ./crashcart <container> -- iftop
```

## Container Runtime Support

### Docker
```bash
sudo ./crashcart my-docker-container
sudo ./crashcart $(docker ps -q | head -1)  # latest container
```

### Podman
```bash
sudo ./crashcart my-podman-container
```

### Raw PID
```bash
# Find the container's main process
docker inspect --format '{{.State.Pid}}' <container>

# Debug by PID
sudo ./crashcart 12345
```

## Advanced Usage

### Mount Only Mode

```bash
# Mount tools without entering shell
sudo ./crashcart -m <container>

# Use tools via container exec
docker exec -it <container> /dev/crashcart/bin/bash
```

### Custom Commands

```bash
# Run specific debugging command
sudo ./crashcart <container> -- strace -e trace=network -p 1

# Run multiple commands
sudo ./crashcart <container> -- bash -c "ps aux && ss -tln"
```

### Verbose Mode

```bash
# See detailed logging
sudo ./crashcart -v <container>
```

## Troubleshooting

### Permission Denied
- Make sure you're running with `sudo`
- Check that your user can access Docker/Podman

### Container Not Found
```bash
# List running containers
docker ps
podman ps

# Use full container ID if short ID doesn't work
sudo ./crashcart $(docker ps --format "{{.ID}}" | head -1)
```

### Image Not Found
```bash
# Build the debugging image
make build-image

# Or manually
./build-image.sh
```

### Mount Failures
- Ensure loop device support: `ls /dev/loop*`
- Check available disk space: `df -h`
- Verify image integrity: `file crashcart.img`

## Tips and Tricks

### 1. Create Aliases
```bash
# Add to your ~/.bashrc
alias debug-container='sudo /path/to/crashcart'
alias debug-latest='sudo /path/to/crashcart $(docker ps -q | head -1)'
```

### 2. Use with Docker Compose
```bash
# Debug a compose service
sudo ./crashcart $(docker-compose ps -q web)
```

### 3. Debugging Init Containers
```bash
# Find init container PID
kubectl get pod <pod> -o jsonpath='{.status.initContainerStatuses[0].containerID}'

# Debug it
sudo ./crashcart <container-id>
```

### 4. Persistent Debugging
```bash
# Mount tools and keep them mounted
sudo ./crashcart -m <container>

# Use multiple terminals
docker exec -it <container> /dev/crashcart/bin/bash  # Terminal 1
docker exec -it <container> /dev/crashcart/bin/htop  # Terminal 2
```

## Next Steps

- Read the [README.md](README.md) for comprehensive documentation
- Check [COMPARISON.md](COMPARISON.md) to see improvements over original
- Explore the [examples/](examples/) directory for more use cases
- Contribute improvements via GitHub issues/PRs

## Getting Help

If you encounter issues:

1. Check the troubleshooting section above
2. Run with `-v` flag for verbose output
3. Verify your setup with the test container
4. Check system requirements and permissions

The modern crashcart maintains the same core functionality as the original while providing better error messages and expanded capabilities.