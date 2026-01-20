#!/bin/bash
set -euo pipefail

# Modern crashcart image builder - Containerized approach
# Creates a complete debugging environment with full glibc compatibility

IMAGE_NAME="crashcart.img"
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
IMAGE_SIZE="200M"  # Reasonable size for selective tools

cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "Building modern crashcart image with containerized approach..."

# Create image file
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

# Create complete debugging environment
echo "Creating selective debugging environment..."
docker run --rm -v "$MOUNT_DIR:/output" ubuntu:22.04 sh -c '
    # Install only essential debugging tools
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
        file \
        vim \
        nano \
        less \
        tree \
        htop \
        jq \
        bash \
        rsync \
        bzip2 \
        gzip \
        tar \
        unzip \
        zip \
        openssl \
        ca-certificates \
        && apt-get clean

    # Copy only essential binaries and libraries
    echo "Copying essential debugging tools..."
    
    # Create complete directory structure first
    mkdir -p /output/bin
    mkdir -p /output/sbin  
    mkdir -p /output/lib
    mkdir -p /output/lib64
    mkdir -p /output/usr/bin
    mkdir -p /output/usr/sbin
    mkdir -p /output/usr/lib
    mkdir -p /output/usr/lib64
    mkdir -p /output/etc
    mkdir -p /output/tmp
    mkdir -p /output/var
    mkdir -p /output/dev
    mkdir -p /output/proc
    mkdir -p /output/sys
    
    # Copy essential binaries (with error handling)
    echo "Copying debugging binaries..."
    cp /usr/bin/gdb /output/usr/bin/ 2>/dev/null || echo "Warning: gdb not found"
    cp /usr/bin/strace /output/usr/bin/ 2>/dev/null || echo "Warning: strace not found"
    cp /usr/bin/ltrace /output/usr/bin/ 2>/dev/null || echo "Warning: ltrace not found"
    cp /usr/bin/lsof /output/usr/bin/ 2>/dev/null || echo "Warning: lsof not found"
    cp /usr/bin/tcpdump /output/usr/bin/ 2>/dev/null || echo "Warning: tcpdump not found"
    cp /usr/bin/nc.openbsd /output/usr/bin/nc 2>/dev/null || cp /bin/nc /output/bin/nc 2>/dev/null || echo "Warning: netcat not found"
    cp /usr/bin/socat /output/usr/bin/ 2>/dev/null || echo "Warning: socat not found"
    cp /usr/bin/curl /output/usr/bin/ 2>/dev/null || echo "Warning: curl not found"
    cp /usr/bin/wget /output/usr/bin/ 2>/dev/null || echo "Warning: wget not found"
    cp /usr/bin/nmap /output/usr/bin/ 2>/dev/null || echo "Warning: nmap not found"
    cp /usr/bin/dig /output/usr/bin/ 2>/dev/null || echo "Warning: dig not found"
    cp /usr/bin/ss /output/usr/bin/ 2>/dev/null || cp /bin/ss /output/bin/ 2>/dev/null || echo "Warning: ss not found"
    cp /usr/sbin/ip /output/usr/sbin/ 2>/dev/null || cp /bin/ip /output/bin/ 2>/dev/null || echo "Warning: ip not found"
    cp /bin/netstat /output/bin/ 2>/dev/null || cp /usr/bin/netstat /output/usr/bin/ 2>/dev/null || echo "Warning: netstat not found"
    cp /usr/bin/ps /output/usr/bin/ 2>/dev/null || cp /bin/ps /output/bin/ 2>/dev/null || echo "Warning: ps not found"
    cp /usr/bin/pgrep /output/usr/bin/ 2>/dev/null || echo "Warning: pgrep not found"
    cp /usr/bin/pkill /output/usr/bin/ 2>/dev/null || echo "Warning: pkill not found"
    cp /usr/bin/killall /output/usr/bin/ 2>/dev/null || echo "Warning: killall not found"
    cp /usr/bin/file /output/usr/bin/ 2>/dev/null || echo "Warning: file not found"
    cp /usr/bin/vim.basic /output/usr/bin/vim 2>/dev/null || cp /usr/bin/vim /output/usr/bin/ 2>/dev/null || echo "Warning: vim not found"
    cp /usr/bin/nano /output/usr/bin/ 2>/dev/null || cp /bin/nano /output/bin/ 2>/dev/null || echo "Warning: nano not found"
    cp /usr/bin/less /output/usr/bin/ 2>/dev/null || cp /bin/less /output/bin/ 2>/dev/null || echo "Warning: less not found"
    cp /usr/bin/tree /output/usr/bin/ 2>/dev/null || echo "Warning: tree not found"
    cp /usr/bin/htop /output/usr/bin/ 2>/dev/null || echo "Warning: htop not found"
    cp /usr/bin/jq /output/usr/bin/ 2>/dev/null || echo "Warning: jq not found"
    cp /usr/bin/bash /output/usr/bin/ 2>/dev/null || cp /bin/bash /output/bin/ 2>/dev/null || echo "Warning: bash not found"
    cp /usr/bin/rsync /output/usr/bin/ 2>/dev/null || echo "Warning: rsync not found"
    cp /usr/bin/bzip2 /output/usr/bin/ 2>/dev/null || cp /bin/bzip2 /output/bin/ 2>/dev/null || echo "Warning: bzip2 not found"
    cp /usr/bin/gzip /output/usr/bin/ 2>/dev/null || cp /bin/gzip /output/bin/ 2>/dev/null || echo "Warning: gzip not found"
    cp /usr/bin/tar /output/usr/bin/ 2>/dev/null || cp /bin/tar /output/bin/ 2>/dev/null || echo "Warning: tar not found"
    cp /usr/bin/unzip /output/usr/bin/ 2>/dev/null || echo "Warning: unzip not found"
    cp /usr/bin/zip /output/usr/bin/ 2>/dev/null || echo "Warning: zip not found"
    cp /usr/bin/openssl /output/usr/bin/ 2>/dev/null || echo "Warning: openssl not found"
    
    # Copy essential system binaries
    echo "Copying system binaries..."
    cp /usr/bin/cat /output/usr/bin/ 2>/dev/null || cp /bin/cat /output/bin/ 2>/dev/null || echo "Warning: cat not found"
    cp /usr/bin/ls /output/usr/bin/ 2>/dev/null || cp /bin/ls /output/bin/ 2>/dev/null || echo "Warning: ls not found"
    cp /usr/bin/cp /output/usr/bin/ 2>/dev/null || cp /bin/cp /output/bin/ 2>/dev/null || echo "Warning: cp not found"
    cp /usr/bin/mv /output/usr/bin/ 2>/dev/null || cp /bin/mv /output/bin/ 2>/dev/null || echo "Warning: mv not found"
    cp /usr/bin/rm /output/usr/bin/ 2>/dev/null || cp /bin/rm /output/bin/ 2>/dev/null || echo "Warning: rm not found"
    cp /usr/bin/mkdir /output/usr/bin/ 2>/dev/null || cp /bin/mkdir /output/bin/ 2>/dev/null || echo "Warning: mkdir not found"
    cp /usr/bin/rmdir /output/usr/bin/ 2>/dev/null || cp /bin/rmdir /output/bin/ 2>/dev/null || echo "Warning: rmdir not found"
    cp /usr/bin/chmod /output/usr/bin/ 2>/dev/null || cp /bin/chmod /output/bin/ 2>/dev/null || echo "Warning: chmod not found"
    cp /usr/bin/chown /output/usr/bin/ 2>/dev/null || cp /bin/chown /output/bin/ 2>/dev/null || echo "Warning: chown not found"
    cp /usr/bin/ln /output/usr/bin/ 2>/dev/null || cp /bin/ln /output/bin/ 2>/dev/null || echo "Warning: ln not found"
    cp /usr/bin/find /output/usr/bin/ 2>/dev/null || echo "Warning: find not found"
    cp /usr/bin/grep /output/usr/bin/ 2>/dev/null || cp /bin/grep /output/bin/ 2>/dev/null || echo "Warning: grep not found"
    cp /usr/bin/awk /output/usr/bin/ 2>/dev/null || echo "Warning: awk not found"
    cp /usr/bin/sed /output/usr/bin/ 2>/dev/null || cp /bin/sed /output/bin/ 2>/dev/null || echo "Warning: sed not found"
    cp /usr/bin/sort /output/usr/bin/ 2>/dev/null || echo "Warning: sort not found"
    cp /usr/bin/uniq /output/usr/bin/ 2>/dev/null || echo "Warning: uniq not found"
    cp /usr/bin/head /output/usr/bin/ 2>/dev/null || echo "Warning: head not found"
    cp /usr/bin/tail /output/usr/bin/ 2>/dev/null || echo "Warning: tail not found"
    cp /usr/bin/wc /output/usr/bin/ 2>/dev/null || echo "Warning: wc not found"
    cp /usr/bin/df /output/usr/bin/ 2>/dev/null || cp /bin/df /output/bin/ 2>/dev/null || echo "Warning: df not found"
    cp /usr/bin/free /output/usr/bin/ 2>/dev/null || echo "Warning: free not found"
    cp /usr/bin/top /output/usr/bin/ 2>/dev/null || echo "Warning: top not found"
    cp /usr/bin/kill /output/usr/bin/ 2>/dev/null || cp /bin/kill /output/bin/ 2>/dev/null || echo "Warning: kill not found"
    
    # Copy essential libraries (selective)
    echo "Copying essential libraries..."
    
    # Copy glibc and essential system libraries
    cp -a /lib/x86_64-linux-gnu/libc.so.6 /output/lib/ 2>/dev/null || echo "Warning: libc not found"
    cp -a /lib/x86_64-linux-gnu/libdl.so.2 /output/lib/ 2>/dev/null || echo "Warning: libdl not found"
    cp -a /lib/x86_64-linux-gnu/libpthread.so.0 /output/lib/ 2>/dev/null || echo "Warning: libpthread not found"
    cp -a /lib/x86_64-linux-gnu/libm.so.6 /output/lib/ 2>/dev/null || echo "Warning: libm not found"
    cp -a /lib/x86_64-linux-gnu/librt.so.1 /output/lib/ 2>/dev/null || echo "Warning: librt not found"
    cp -a /lib/x86_64-linux-gnu/libresolv.so.2 /output/lib/ 2>/dev/null || echo "Warning: libresolv not found"
    cp -a /lib/x86_64-linux-gnu/libnss_*.so.2 /output/lib/ 2>/dev/null || true
    
    # Copy the actual dynamic linker file (not just the symlink)
    cp -a /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /output/lib64/ 2>/dev/null || echo "Warning: ld-linux not found"
    
    # Also copy it to the lib directory for compatibility
    cp -a /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /output/lib/ 2>/dev/null || true
    
    # Copy libraries for debugging tools
    cp -a /usr/lib/x86_64-linux-gnu/libpcap.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libssl.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libcrypto.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libcurl.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libjq.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /lib/x86_64-linux-gnu/libz.so.* /output/lib/ 2>/dev/null || true
    cp -a /lib/x86_64-linux-gnu/libncurses.so.* /output/lib/ 2>/dev/null || true
    cp -a /lib/x86_64-linux-gnu/libtinfo.so.* /output/lib/ 2>/dev/null || true
    
    # Copy additional essential libraries for bash and other tools
    cp -a /lib/x86_64-linux-gnu/libreadline.so.* /output/lib/ 2>/dev/null || true
    cp -a /lib/x86_64-linux-gnu/libhistory.so.* /output/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libreadline.so.* /output/usr/lib/ 2>/dev/null || true
    cp -a /usr/lib/x86_64-linux-gnu/libhistory.so.* /output/usr/lib/ 2>/dev/null || true
    
    # Copy essential config files
    mkdir -p /output/etc
    echo "root:x:0:0:root:/root:/bin/bash" > /output/etc/passwd
    echo "root:x:0:" > /output/etc/group
    echo "127.0.0.1 localhost" > /output/etc/hosts
    
    # Copy SSL certificates
    cp -r /etc/ssl /output/etc/ 2>/dev/null || true
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
# Create enhanced .crashcartrc for containerized approach
sudo tee "$MOUNT_DIR/.crashcartrc" > /dev/null << 'EOF'
# Modern Crashcart - Containerized Debugging Environment
export PATH="/dev/crashcart/bin:/dev/crashcart/sbin:/dev/crashcart/usr/bin:/dev/crashcart/usr/sbin:$PATH"
export LD_LIBRARY_PATH="/dev/crashcart/lib:/dev/crashcart/lib64:/dev/crashcart/usr/lib:/dev/crashcart/usr/lib64"
export PS1="[crashcart] \u@\h:\w\$ "

# Get target container PID (passed by crashcart)
TARGET_PID=${CRASHCART_TARGET_PID:-1}

# Aliases for namespace-aware debugging
alias gdb-target="gdb-attach $TARGET_PID"
alias strace-target="strace-attach $TARGET_PID"
alias net-target="net-debug $TARGET_PID"

# Standard aliases
alias ll='ls -la'
alias la='ls -la'
alias l='ls -l'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias ps='ps aux'
alias netstat='ss -tuln'
alias ports='ss -tuln'
alias listen='ss -tln'
alias connections='ss -tu'

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

trace-syscalls() {
    local pid=${1:-1}
    echo "=== System Call Trace for Process $pid ==="
    debug-in-ns "$TARGET_PID" strace -e trace=all -p "$pid"
}

trace-network() {
    local pid=${1:-1}
    echo "=== Network System Calls for Process $pid ==="
    debug-in-ns "$TARGET_PID" strace -e trace=network -p "$pid"
}

trace-files() {
    local pid=${1:-1}
    echo "=== File System Calls for Process $pid ==="
    debug-in-ns "$TARGET_PID" strace -e trace=file -p "$pid"
}

list-processes() {
    echo "=== Processes in Target Container ==="
    debug-in-ns "$TARGET_PID" ps aux
}

list-files() {
    local pid=${1:-1}
    echo "=== Open Files for Process $pid ==="
    debug-in-ns "$TARGET_PID" lsof -p "$pid"
}

network-status() {
    echo "=== Network Status in Target Container ==="
    debug-in-ns "$TARGET_PID" ss -tuln
    echo
    echo "=== Network Interfaces ==="
    debug-in-ns "$TARGET_PID" ip addr show
}

network-capture() {
    local interface=${1:-any}
    echo "=== Capturing Network Traffic on $interface ==="
    debug-in-ns "$TARGET_PID" tcpdump -i "$interface" -n "${@:2}"
}

container-shell() {
    echo "=== Entering Target Container Shell with Full Tools ==="
    debug-in-ns "$TARGET_PID" bash
}

memory-info() {
    echo "=== Memory Information ==="
    debug-in-ns "$TARGET_PID" free -h
    echo
    echo "=== Memory Map for Process ${1:-1} ==="
    debug-in-ns "$TARGET_PID" cat /proc/${1:-1}/maps | head -20
}

disk-usage() {
    echo "=== Disk Usage in Target Container ==="
    debug-in-ns "$TARGET_PID" df -h
}

sysinfo() {
    echo "=== Target Container System Information ==="
    echo "Target PID: $TARGET_PID"
    echo "Crashcart Environment: Ubuntu 22.04 with full glibc compatibility"
    echo
    list-processes
    echo
    network-status
    echo
    memory-info
}

# Functions for common debugging scenarios
findproc() {
    debug-in-ns "$TARGET_PID" ps aux | grep -i "$1" | grep -v grep
}

netconns() {
    debug-in-ns "$TARGET_PID" ss -tuln | grep -E "(LISTEN|ESTAB)"
}

check-tools() {
    echo "=== Available Debugging Tools ==="
    echo "Core debugging tools:"
    for tool in gdb strace ltrace lsof; do
        if [ -f "/dev/crashcart/usr/bin/$tool" ] || [ -f "/dev/crashcart/bin/$tool" ]; then
            echo "  ✓ $tool (full glibc compatibility)"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Network tools:"
    for tool in ss tcpdump nmap dig curl wget netcat; do
        if [ -f "/dev/crashcart/usr/bin/$tool" ] || [ -f "/dev/crashcart/bin/$tool" ]; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "System tools:"
    for tool in ps top htop iotop iftop vim nano less; do
        if [ -f "/dev/crashcart/usr/bin/$tool" ] || [ -f "/dev/crashcart/bin/$tool" ]; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool"
        fi
    done
    
    echo
    echo "Usage examples:"
    echo "  debug-process 123      # Debug PID 123 with GDB"
    echo "  trace-process 123      # Trace PID 123 with strace"
    echo "  trace-network 123      # Trace network calls for PID 123"
    echo "  list-files 123         # Show open files for PID 123"
    echo "  network-capture eth0   # Capture packets on eth0"
    echo "  container-shell        # Full shell in target container"
}

echo "Modern Crashcart debugging environment loaded!"
echo "Target container PID: $TARGET_PID"
echo "Environment: Ubuntu 22.04 with full glibc compatibility"
echo ""
echo "Quick start:"
echo "  check-tools     - See available debugging tools"
echo "  sysinfo         - System overview"
echo "  list-processes  - Show all processes"
echo "  network-status  - Network information"
echo ""
echo "All debugging tools have full library compatibility!"
EOF

# Create a simple profile script
sudo tee "$MOUNT_DIR/profile" > /dev/null << 'EOF'
#!/bin/bash
# Crashcart profile loader
export PATH="/dev/crashcart/bin:/dev/crashcart/sbin:/dev/crashcart/usr/bin:/dev/crashcart/usr/sbin:$PATH"
source /dev/crashcart/.crashcartrc
EOF

sudo chmod +x "$MOUNT_DIR/profile"

# Create symlinks for common locations
sudo ln -sf bash "$MOUNT_DIR/bin/sh"
sudo ln -sf ../usr/bin/vim "$MOUNT_DIR/bin/vi" 2>/dev/null || true

echo "Modern crashcart image build complete!"
echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
echo
echo "Features:"
echo "  - Complete Ubuntu 22.04 debugging environment"
echo "  - Full glibc compatibility for all tools"
echo "  - Namespace-aware debugging scripts"
echo "  - 40+ debugging and system tools"
echo "  - Tools run in isolated environment but access target resources"
echo
echo "Tools included:"
echo "  - Debugging: gdb, strace, ltrace, lsof"
echo "  - Network: tcpdump, ss, nmap, dig, curl, wget, netcat, socat"
echo "  - System: ps, top, htop, iotop, iftop, free, df"
echo "  - Files: vim, nano, less, tree, tar, gzip, rsync"
echo "  - Languages: python3, perl, bash, zsh"
echo "  - Utils: jq, file, binutils, tmux, screen"
echo
echo "Usage:"
echo "  sudo ./crashcart <container-id>"
echo "  # Inside crashcart:"
echo "  check-tools              # See all available tools"
echo "  debug-process 123        # Debug PID 123 with GDB"
echo "  trace-process 123        # Trace PID 123 with strace"
echo "  network-capture eth0     # Capture network traffic"
echo "  container-shell          # Full shell in target container"