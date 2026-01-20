#!/bin/bash
set -euo pipefail

# Static-focused crashcart image builder
# Prioritizes static binaries that work in any container

IMAGE_NAME="crashcart.img"
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
IMAGE_SIZE="150M"

cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "Building static-focused crashcart image..."

# Create image file
dd if=/dev/zero of="$IMAGE_NAME" bs=1M count=150
echo "Created $IMAGE_SIZE image file"

# Setup loop device
LOOP_DEVICE=$(sudo losetup -f --show "$IMAGE_NAME")
echo "Using loop device: $LOOP_DEVICE"

# Create ext4 filesystem
sudo mkfs.ext4 -F "$LOOP_DEVICE"
echo "Created ext4 filesystem"

# Mount the image
mkdir -p "$MOUNT_DIR"
sudo mount "$LOOP_DEVICE" "$MOUNT_DIR"
echo "Mounted image at $MOUNT_DIR"

# Create directory structure
sudo mkdir -p "$MOUNT_DIR"/{bin,sbin,lib,usr/{bin,sbin},etc,tmp,var,static}

echo "=== Phase 1: Static binaries (universal compatibility) ==="

# Use Alpine to build/download static binaries
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache curl file

    cd /output/bin

    # BusyBox static (covers most basic utilities)
    echo "Downloading BusyBox static..."
    curl -L -o busybox-static \
        https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
    chmod +x busybox-static
    
    # Create symlinks for BusyBox tools
    for tool in sh ash bash ls cat cp mv rm mkdir rmdir ln chmod chown \
                ps kill top find grep awk sed sort uniq head tail wc \
                tar gzip gunzip nc netcat wget ping traceroute \
                mount umount df du free uptime whoami id; do
        ln -sf busybox-static $tool 2>/dev/null || true
    done

    # Download other static binaries
    echo "Downloading additional static tools..."
    
    # Static curl
    curl -L -o curl-static \
        https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64
    chmod +x curl-static
    ln -sf curl-static curl
    
    # Note: These would need to be built or found as static binaries
    # For now, we will include some key ones and document the limitation
'

echo "=== Phase 2: Minimal dynamic tools with bundled libraries ==="

# For tools that must be dynamic, bundle their dependencies
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache \
        strace \
        tcpdump \
        lsof \
        file \
        jq \
        socat \
        openssl \
        ca-certificates

    # Copy binaries
    cp /usr/bin/strace /output/bin/
    cp /usr/bin/tcpdump /output/bin/
    cp /usr/bin/lsof /output/bin/
    cp /usr/bin/file /output/bin/
    cp /usr/bin/jq /output/bin/
    cp /usr/bin/socat /output/bin/
    cp /usr/bin/openssl /output/bin/

    # Copy minimal required libraries (musl-based)
    mkdir -p /output/lib/crashcart
    cp /lib/ld-musl-x86_64.so.1 /output/lib/crashcart/ 2>/dev/null || true
    cp /usr/lib/libpcap.so.* /output/lib/crashcart/ 2>/dev/null || true
    cp /usr/lib/libssl.so.* /output/lib/crashcart/ 2>/dev/null || true
    cp /usr/lib/libcrypto.so.* /output/lib/crashcart/ 2>/dev/null || true
    
    # Copy SSL certificates
    cp -r /etc/ssl /output/etc/
'

echo "=== Phase 3: Build custom static tools ==="

# Build some tools as static binaries
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache build-base linux-headers git

    # Build static gdb (simplified version)
    # Note: Full gdb is complex, this is a placeholder for the concept
    echo "Building minimal static debugging tools..."
    
    # Simple static process inspector
    cat > /tmp/psinspect.c << "EOFPROG"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>

int main(int argc, char *argv[]) {
    DIR *proc = opendir("/proc");
    struct dirent *entry;
    
    printf("PID\tCOMMAND\n");
    while ((entry = readdir(proc)) != NULL) {
        if (strspn(entry->d_name, "0123456789") == strlen(entry->d_name)) {
            char path[256], comm[256];
            snprintf(path, sizeof(path), "/proc/%s/comm", entry->d_name);
            FILE *f = fopen(path, "r");
            if (f) {
                if (fgets(comm, sizeof(comm), f)) {
                    comm[strcspn(comm, "\n")] = 0;
                    printf("%s\t%s\n", entry->d_name, comm);
                }
                fclose(f);
            }
        }
    }
    closedir(proc);
    return 0;
}
EOFPROG

    gcc -static -o /output/bin/psinspect /tmp/psinspect.c
    chmod +x /output/bin/psinspect
'

# Create wrapper scripts that handle library paths
sudo tee "$MOUNT_DIR/bin/crashcart-strace" > /dev/null << 'EOF'
#!/bin/sh
# Wrapper for strace with bundled libraries
export LD_LIBRARY_PATH="/dev/crashcart/lib/crashcart:$LD_LIBRARY_PATH"
exec /dev/crashcart/bin/strace "$@"
EOF

sudo tee "$MOUNT_DIR/bin/crashcart-tcpdump" > /dev/null << 'EOF'
#!/bin/sh
# Wrapper for tcpdump with bundled libraries
export LD_LIBRARY_PATH="/dev/crashcart/lib/crashcart:$LD_LIBRARY_PATH"
exec /dev/crashcart/bin/tcpdump "$@"
EOF

sudo tee "$MOUNT_DIR/bin/crashcart-lsof" > /dev/null << 'EOF'
#!/bin/sh
# Wrapper for lsof with bundled libraries
export LD_LIBRARY_PATH="/dev/crashcart/lib/crashcart:$LD_LIBRARY_PATH"
exec /dev/crashcart/bin/lsof "$@"
EOF

sudo chmod +x "$MOUNT_DIR/bin/crashcart-"*

# Create comprehensive .crashcartrc
sudo tee "$MOUNT_DIR/.crashcartrc" > /dev/null << 'EOF'
# Static-focused Crashcart environment
export PATH="/dev/crashcart/bin:/dev/crashcart/sbin:/dev/crashcart/usr/bin:$PATH"
export PS1="[crashcart-static] \u@\h:\w\$ "

# Aliases for wrapped tools
alias strace='crashcart-strace'
alias tcpdump='crashcart-tcpdump'
alias lsof='crashcart-lsof'

# Aliases for static tools
alias ps='psinspect'  # Our custom static ps
alias ll='ls -la'
alias la='ls -la'
alias l='ls -l'
alias ..='cd ..'
alias grep='grep --color=auto'

# Functions using static tools
netconns() {
    echo "=== Network Connections ==="
    if [ -f /proc/net/tcp ]; then
        echo "TCP connections:"
        cat /proc/net/tcp | awk 'NR>1 {print $2, $3, $4}'
    fi
    if [ -f /proc/net/udp ]; then
        echo "UDP connections:"
        cat /proc/net/udp | awk 'NR>1 {print $2, $3, $4}'
    fi
}

procinfo() {
    local pid=${1:-1}
    echo "=== Process Info for PID $pid ==="
    [ -f /proc/$pid/cmdline ] && echo "Command: $(cat /proc/$pid/cmdline | tr '\0' ' ')"
    [ -f /proc/$pid/status ] && echo "Status:" && head -10 /proc/$pid/status
    [ -d /proc/$pid/fd ] && echo "Open FDs: $(ls /proc/$pid/fd 2>/dev/null | wc -l)"
}

sysinfo() {
    echo "=== System Information (Static Tools) ==="
    uname -a 2>/dev/null || echo "uname not available"
    echo
    echo "=== Memory ==="
    free 2>/dev/null || cat /proc/meminfo | head -5
    echo
    echo "=== Disk Usage ==="
    df 2>/dev/null || echo "df not available, check /proc/mounts"
    echo
    echo "=== Processes ==="
    psinspect
}

check-static-tools() {
    echo "=== Static Tool Availability ==="
    echo "Core static tools:"
    for tool in busybox-static sh ls ps kill find grep; do
        if command -v $tool >/dev/null 2>&1; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Dynamic tools with bundled libs:"
    for tool in crashcart-strace crashcart-tcpdump crashcart-lsof; do
        if command -v $tool >/dev/null 2>&1; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Note: This build prioritizes static binaries for maximum compatibility"
    echo "Some advanced features may be limited compared to full dynamic builds"
}

echo "Static-focused Crashcart environment loaded!"
echo "Type 'check-static-tools' to see available tools"
echo "Type 'sysinfo' for system overview using static tools"
echo "Most tools are static and should work in any container"
EOF

echo "Static-focused image build complete!"
echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
echo
echo "Features:"
echo "  - BusyBox static binary (covers 50+ basic utilities)"
echo "  - Custom static debugging tools"
echo "  - Minimal dynamic tools with bundled musl libraries"
echo "  - Maximum compatibility across different container types"
echo
echo "Limitations:"
echo "  - Some advanced debugging features may be limited"
echo "  - GDB not included (complex to build static)"
echo "  - Fewer total tools but higher compatibility"
echo
echo "Usage:"
echo "  sudo ./crashcart <container-id>"