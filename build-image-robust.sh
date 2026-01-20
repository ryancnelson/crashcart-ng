#!/bin/bash
set -euo pipefail

# Robust crashcart image builder
# Uses multiple base images to get the best tools

IMAGE_NAME="crashcart.img"
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
IMAGE_SIZE="200M"  # Larger for more comprehensive toolset

cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "Building robust crashcart image with multiple tool sources..."

# Create larger image file
dd if=/dev/zero of="$IMAGE_NAME" bs=1M count=200
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
sudo mkdir -p "$MOUNT_DIR"/{bin,sbin,lib,lib64,usr/{bin,sbin,lib,lib64},etc,tmp,var,dev,proc,sys}

echo "=== Phase 1: Alpine tools (musl-based) ==="
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache \
        bash \
        curl \
        wget \
        openssl \
        ca-certificates \
        file \
        jq \
        socat \
        nc-openbsd \
        rsync \
        tree \
        less \
        vim \
        nano \
        bzip2 \
        gzip \
        tar \
        tcpdump \
        nmap \
        bind-tools \
        htop \
        iotop \
        iftop

    # Copy Alpine tools
    cp -a /bin/* /output/bin/ 2>/dev/null || true
    cp -a /sbin/* /output/sbin/ 2>/dev/null || true
    cp -a /usr/bin/* /output/usr/bin/ 2>/dev/null || true
    cp -a /usr/sbin/* /output/usr/sbin/ 2>/dev/null || true
    cp -a /lib/* /output/lib/ 2>/dev/null || true
    cp -a /usr/lib/* /output/usr/lib/ 2>/dev/null || true
    
    # Copy essential config files
    cp -a /etc/passwd /output/etc/ 2>/dev/null || true
    cp -a /etc/group /output/etc/ 2>/dev/null || true
    cp -a /etc/hosts /output/etc/ 2>/dev/null || true
    cp -a /etc/ssl /output/etc/ 2>/dev/null || true
'

echo "=== Phase 2: Ubuntu tools (glibc-based) ==="
# Create glibc subdirectory for compatibility
sudo mkdir -p "$MOUNT_DIR/glibc"/{bin,sbin,lib,lib64}

docker run --rm -v "$MOUNT_DIR:/output" ubuntu:22.04 sh -c '
    apt-get update && apt-get install -y \
        gdb \
        strace \
        ltrace \
        lsof \
        binutils \
        procps \
        psmisc \
        iproute2 \
        iputils-ping \
        net-tools \
        dnsutils \
        telnet \
        netcat-openbsd \
        && apt-get clean

    # Copy glibc-based tools to separate directory
    cp -a /usr/bin/gdb /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/strace /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/ltrace /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/lsof /output/glibc/bin/ 2>/dev/null || true
    cp -a /bin/ps /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/pgrep /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/pkill /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/killall /output/glibc/bin/ 2>/dev/null || true
    cp -a /bin/ss /output/glibc/bin/ 2>/dev/null || true
    cp -a /bin/netstat /output/glibc/bin/ 2>/dev/null || true
    cp -a /usr/bin/dig /output/glibc/bin/ 2>/dev/null || true
    cp -a /bin/ping /output/glibc/bin/ 2>/dev/null || true
    
    # Copy required libraries
    cp -a /lib/x86_64-linux-gnu/* /output/glibc/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/* /output/glibc/lib/ 2>/dev/null || true
    cp -a /lib64/* /output/glibc/lib64/ 2>/dev/null || true
'

echo "=== Phase 3: Static binaries (universal) ==="
# Add some static binaries that work everywhere
sudo mkdir -p "$MOUNT_DIR/static/bin"

# Download some useful static binaries
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache curl
    
    # Download static busybox (fallback for everything)
    curl -L -o /output/static/bin/busybox-static \
        https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
    chmod +x /output/static/bin/busybox-static
    
    # Create busybox symlinks for core utilities
    cd /output/static/bin
    for tool in sh ash ls cat cp mv rm mkdir rmdir ln chmod chown ps kill top find grep awk sed sort uniq head tail wc; do
        ln -sf busybox-static $tool
    done
'

# Create smart wrapper scripts
sudo tee "$MOUNT_DIR/bin/crashcart-gdb" > /dev/null << 'EOF'
#!/bin/bash
# Smart GDB wrapper - tries glibc version first, falls back to Alpine
if [ -f /dev/crashcart/glibc/bin/gdb ]; then
    LD_LIBRARY_PATH=/dev/crashcart/glibc/lib:/dev/crashcart/glibc/lib64:$LD_LIBRARY_PATH \
    /dev/crashcart/glibc/bin/gdb "$@"
else
    /dev/crashcart/bin/gdb "$@"
fi
EOF

sudo tee "$MOUNT_DIR/bin/crashcart-ps" > /dev/null << 'EOF'
#!/bin/bash
# Smart ps wrapper - prefers glibc version for full features
if [ -f /dev/crashcart/glibc/bin/ps ]; then
    LD_LIBRARY_PATH=/dev/crashcart/glibc/lib:/dev/crashcart/glibc/lib64:$LD_LIBRARY_PATH \
    /dev/crashcart/glibc/bin/ps "$@"
else
    /dev/crashcart/bin/ps "$@"
fi
EOF

sudo chmod +x "$MOUNT_DIR/bin/crashcart-"*

# Create enhanced .crashcartrc
sudo tee "$MOUNT_DIR/.crashcartrc" > /dev/null << 'EOF'
# Enhanced Crashcart debugging environment
export PATH="/dev/crashcart/bin:/dev/crashcart/sbin:/dev/crashcart/usr/bin:/dev/crashcart/usr/sbin:/dev/crashcart/glibc/bin:/dev/crashcart/static/bin:$PATH"
export LD_LIBRARY_PATH="/dev/crashcart/lib:/dev/crashcart/lib64:/dev/crashcart/usr/lib:/dev/crashcart/glibc/lib:/dev/crashcart/glibc/lib64:$LD_LIBRARY_PATH"
export PS1="[crashcart] \u@\h:\w\$ "

# Aliases for compatibility
alias gdb='crashcart-gdb'
alias ps='crashcart-ps'
alias ll='ls -la'
alias la='ls -la'
alias l='ls -l'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias netstat='ss -tuln'  # Modern replacement
alias ports='ss -tuln'
alias listen='ss -tln'
alias connections='ss -tu'

# Functions for debugging
pstree() {
    if command -v pstree >/dev/null; then
        command pstree "$@"
    else
        crashcart-ps -eo pid,ppid,cmd --forest
    fi
}

findproc() {
    crashcart-ps aux | grep -i "$1" | grep -v grep
}

netconns() {
    ss -tuln | grep -E "(LISTEN|ESTAB)"
}

diskusage() {
    df -h
}

meminfo() {
    free -h
    echo
    cat /proc/meminfo | head -10
}

sysinfo() {
    echo "=== System Information ==="
    uname -a
    echo
    echo "=== Memory ==="
    free -h
    echo
    echo "=== Disk Usage ==="
    df -h
    echo
    echo "=== Network Interfaces ==="
    ip addr show 2>/dev/null || ifconfig
    echo
    echo "=== Listening Ports ==="
    ss -tln 2>/dev/null || netstat -tln
}

# Tool availability check
check-tools() {
    echo "=== Available Debugging Tools ==="
    echo "Core tools:"
    for tool in bash sh ps kill gdb strace ltrace lsof; do
        if command -v $tool >/dev/null; then
            echo "  ✓ $tool ($(which $tool))"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Network tools:"
    for tool in ss netstat tcpdump nmap dig curl wget; do
        if command -v $tool >/dev/null; then
            echo "  ✓ $tool ($(which $tool))"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "File tools:"
    for tool in vim nano less tar gzip find grep; do
        if command -v $tool >/dev/null; then
            echo "  ✓ $tool ($(which $tool))"
        else
            echo "  ✗ $tool"
        fi
    done
}

echo "Enhanced Crashcart debugging environment loaded!"
echo "Type 'check-tools' to see available tools"
echo "Type 'sysinfo' for system overview"
echo "Available: Alpine (musl), Ubuntu (glibc), and static tools"
EOF

echo "Image build complete!"
echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
echo
echo "Features:"
echo "  - Alpine tools (musl libc) for basic operations"
echo "  - Ubuntu tools (glibc) for advanced debugging"
echo "  - Static binaries as universal fallbacks"
echo "  - Smart wrappers that choose the best tool version"
echo "  - Enhanced environment with compatibility functions"
echo
echo "Usage:"
echo "  sudo ./crashcart <container-id>"
echo "  # Inside crashcart: check-tools, sysinfo, gdb, strace, etc."