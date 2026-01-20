#!/bin/bash
set -euo pipefail

# Containerized debugging approach
# Tools run in their own environment but can access target container's resources

IMAGE_NAME="crashcart.img"
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
IMAGE_SIZE="300M"  # Larger for full container environment

cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "Building containerized crashcart image..."

# Create image file
dd if=/dev/zero of="$IMAGE_NAME" bs=1M count=300
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

# Create full container filesystem
echo "Creating complete debugging environment..."
docker run --rm -v "$MOUNT_DIR:/output" ubuntu:22.04 sh -c '
    # Install comprehensive debugging toolkit
    apt-get update && apt-get install -y \
        gdb \
        strace \
        ltrace \
        lsof \
        tcpdump \
        netcat-openbsd \
        socat \
        curl \
        wget \
        nmap \
        dnsutils \
        iproute2 \
        net-tools \
        procps \
        psmisc \
        binutils \
        file \
        vim \
        nano \
        less \
        tree \
        htop \
        iotop \
        iftop \
        jq \
        python3 \
        python3-pip \
        perl \
        bash \
        zsh \
        tmux \
        screen \
        rsync \
        && apt-get clean

    # Copy entire filesystem
    echo "Copying complete Ubuntu environment..."
    cp -a /bin /output/
    cp -a /sbin /output/
    cp -a /usr /output/
    cp -a /lib /output/
    cp -a /lib64 /output/
    cp -a /etc /output/
    cp -a /var /output/
    
    # Create necessary directories
    mkdir -p /output/{tmp,proc,sys,dev,run}
    
    # Set up minimal /etc files for the debugging environment
    echo "root:x:0:0:root:/root:/bin/bash" > /output/etc/passwd
    echo "root:x:0:" > /output/etc/group
'

# Create namespace debugging scripts
sudo tee "$MOUNT_DIR/bin/debug-in-ns" > /dev/null << 'EOF'
#!/bin/bash
# Run debugging command in crashcart namespace but with access to target
# Usage: debug-in-ns <target-pid> <command>

TARGET_PID=$1
shift
COMMAND="$@"

if [ -z "$TARGET_PID" ] || [ -z "$COMMAND" ]; then
    echo "Usage: debug-in-ns <target-pid> <command>"
    exit 1
fi

# Enter target's PID namespace for process visibility
# but keep our own mount namespace for tools
exec nsenter -t "$TARGET_PID" -p -n -i -u -- \
    chroot /dev/crashcart \
    env PATH=/bin:/sbin:/usr/bin:/usr/sbin \
    LD_LIBRARY_PATH=/lib:/lib64:/usr/lib:/usr/lib64 \
    $COMMAND
EOF

sudo tee "$MOUNT_DIR/bin/gdb-attach" > /dev/null << 'EOF'
#!/bin/bash
# Attach GDB to process in target container
TARGET_PID=${1:-1}
ATTACH_PID=${2:-$TARGET_PID}

echo "Attaching GDB to PID $ATTACH_PID in container PID $TARGET_PID"
debug-in-ns "$TARGET_PID" gdb -p "$ATTACH_PID"
EOF

sudo tee "$MOUNT_DIR/bin/strace-attach" > /dev/null << 'EOF'
#!/bin/bash
# Attach strace to process in target container
TARGET_PID=${1:-1}
ATTACH_PID=${2:-$TARGET_PID}

echo "Tracing PID $ATTACH_PID in container PID $TARGET_PID"
debug-in-ns "$TARGET_PID" strace -p "$ATTACH_PID" "${@:3}"
EOF

sudo tee "$MOUNT_DIR/bin/net-debug" > /dev/null << 'EOF'
#!/bin/bash
# Network debugging in target container's network namespace
TARGET_PID=${1:-1}
shift
COMMAND=${1:-"ss -tuln"}

echo "Running network debug in container PID $TARGET_PID"
debug-in-ns "$TARGET_PID" $COMMAND
EOF

sudo chmod +x "$MOUNT_DIR/bin/"*

# Enhanced .crashcartrc for containerized approach
sudo tee "$MOUNT_DIR/.crashcartrc" > /dev/null << 'EOF'
# Containerized Crashcart Environment
export PATH="/dev/crashcart/bin:/dev/crashcart/sbin:/dev/crashcart/usr/bin:/dev/crashcart/usr/sbin:$PATH"
export LD_LIBRARY_PATH="/dev/crashcart/lib:/dev/crashcart/lib64:/dev/crashcart/usr/lib:/dev/crashcart/usr/lib64"
export PS1="[crashcart-container] \u@\h:\w\$ "

# Get target container PID (passed by crashcart)
TARGET_PID=${CRASHCART_TARGET_PID:-1}

# Aliases for namespace-aware debugging
alias gdb-target="gdb-attach $TARGET_PID"
alias strace-target="strace-attach $TARGET_PID"
alias net-target="net-debug $TARGET_PID"

# Direct debugging functions
debug-process() {
    local pid=${1:-1}
    echo "=== Debugging Process $pid in Target Container ==="
    debug-in-ns "$TARGET_PID" gdb -p "$pid"
}

trace-process() {
    local pid=${1:-1}
    echo "=== Tracing Process $pid in Target Container ==="
    debug-in-ns "$TARGET_PID" strace -p "$pid" "${@:2}"
}

list-processes() {
    echo "=== Processes in Target Container ==="
    debug-in-ns "$TARGET_PID" ps aux
}

network-status() {
    echo "=== Network Status in Target Container ==="
    debug-in-ns "$TARGET_PID" ss -tuln
    echo
    echo "=== Network Interfaces ==="
    debug-in-ns "$TARGET_PID" ip addr show
}

container-shell() {
    echo "=== Entering Target Container Shell with Full Tools ==="
    debug-in-ns "$TARGET_PID" bash
}

sysinfo() {
    echo "=== Target Container System Information ==="
    echo "Target PID: $TARGET_PID"
    echo
    list-processes
    echo
    network-status
    echo
    echo "=== Memory Usage ==="
    debug-in-ns "$TARGET_PID" free -h
}

check-containerized-tools() {
    echo "=== Containerized Tool Availability ==="
    echo "Debugging tools:"
    for tool in gdb strace ltrace lsof tcpdump; do
        if [ -f "/dev/crashcart/usr/bin/$tool" ] || [ -f "/dev/crashcart/bin/$tool" ]; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Network tools:"
    for tool in ss netstat tcpdump nmap dig curl wget; do
        if [ -f "/dev/crashcart/usr/bin/$tool" ] || [ -f "/dev/crashcart/bin/$tool" ]; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Usage examples:"
    echo "  debug-process 123    # Debug PID 123 with GDB"
    echo "  trace-process 123    # Trace PID 123 with strace"
    echo "  network-status       # Show network info"
    echo "  container-shell      # Full shell in target container"
}

echo "Containerized Crashcart environment loaded!"
echo "Target container PID: $TARGET_PID"
echo "Type 'check-containerized-tools' to see available tools"
echo "Type 'sysinfo' for target container overview"
echo "All tools run with full glibc compatibility!"
EOF

echo "Containerized image build complete!"
echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
echo
echo "Features:"
echo "  - Complete Ubuntu debugging environment"
echo "  - Full glibc compatibility"
echo "  - Namespace-aware debugging scripts"
echo "  - Tools run in their own environment but access target resources"
echo "  - Maximum tool compatibility and features"
echo
echo "Trade-offs:"
echo "  - Larger image size (300MB vs 100MB)"
echo "  - More complex namespace handling"
echo "  - Higher memory usage"
echo
echo "Usage:"
echo "  sudo ./crashcart <container-id>"
echo "  # Inside: debug-process 123, trace-process 123, network-status"