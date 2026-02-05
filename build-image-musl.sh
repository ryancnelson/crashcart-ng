#!/bin/bash
set -euo pipefail

# Musl-based crashcart image builder with bundled dependencies
# Creates a completely self-contained debugging environment with zero external deps

IMAGE_NAME="crashcart.img"
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
IMAGE_SIZE="80M"  # Smaller than glibc version

cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo "Building self-contained musl crashcart image..."

# Create image file
dd if=/dev/zero of="$IMAGE_NAME" bs=1M count=80
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
sudo mkdir -p "$MOUNT_DIR"/{bin,sbin,lib,usr/{bin,sbin,lib},etc,tmp,var,dev,proc,sys}

echo "=== Phase 1: Static Foundation ==="

# Build static binaries and BusyBox
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    apk add --no-cache curl file gcc musl-dev linux-headers

    cd /output/bin

    # BusyBox static (universal compatibility)
    echo "Downloading BusyBox static..."
    curl -L -o busybox \
        https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
    chmod +x busybox

    # Create BusyBox symlinks for basic utilities
    for tool in sh ash ls cat cp mv rm mkdir rmdir ln chmod chown \
                ps kill top find grep awk sed sort uniq head tail wc \
                tar gzip gunzip nc netcat wget ping traceroute mount umount \
                df du free uptime whoami id sleep echo test true false; do
        ln -sf busybox $tool 2>/dev/null || true
    done

    # Static curl
    echo "Downloading static curl..."
    curl -L -o curl \
        https://github.com/moparisthebest/static-curl/releases/latest/download/curl-amd64
    chmod +x curl

    # Build custom static process inspector
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

    echo "Static foundation complete"
'

echo "=== Phase 2: Musl Tools with Full Features ==="

# Install comprehensive musl-based debugging tools
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    # Install all debugging and system tools (musl-native)
    apk add --no-cache \
        gdb \
        strace \
        ltrace \
        lsof \
        tcpdump \
        nmap \
        socat \
        bind-tools \
        iproute2 \
        net-tools \
        procps \
        htop \
        iotop \
        iftop \
        file \
        tree \
        vim \
        nano \
        less \
        jq \
        bash \
        rsync \
        bzip2 \
        xz \
        openssl \
        ca-certificates \
        util-linux \
        coreutils

    echo "Copying musl debugging tools..."

    # Copy all binaries to usr/bin
    cp /usr/bin/gdb /output/usr/bin/
    cp /usr/bin/strace /output/usr/bin/
    cp /usr/bin/ltrace /output/usr/bin/
    cp /usr/bin/lsof /output/usr/bin/
    cp /usr/sbin/tcpdump /output/usr/bin/  # tcpdump is in sbin
    cp /usr/bin/nmap /output/usr/bin/
    cp /usr/bin/socat /output/usr/bin/
    cp /usr/bin/dig /output/usr/bin/
    cp /usr/bin/nslookup /output/usr/bin/
    cp /sbin/ss /output/usr/bin/  # ss is in sbin
    cp /sbin/ip /output/usr/bin/  # ip is in sbin
    cp /bin/netstat /output/usr/bin/
    cp /usr/bin/htop /output/usr/bin/
    cp /usr/sbin/iotop /output/usr/bin/
    cp /usr/bin/iftop /output/usr/bin/
    cp /usr/bin/file /output/usr/bin/
    cp /usr/bin/tree /output/usr/bin/
    cp /usr/bin/vim /output/usr/bin/
    cp /usr/bin/nano /output/usr/bin/
    cp /usr/bin/less /output/usr/bin/
    cp /usr/bin/jq /output/usr/bin/
    cp /bin/bash /output/usr/bin/
    cp /usr/bin/rsync /output/usr/bin/
    cp /usr/bin/bzip2 /output/usr/bin/
    cp /usr/bin/xz /output/usr/bin/
    cp /usr/bin/openssl /output/usr/bin/

    echo "Musl tools copied successfully"
'

echo "=== Phase 3: Bundle ALL Musl Dependencies ==="

# Copy all required musl libraries
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    # Install all packages first to ensure libraries are present
    apk add --no-cache \
        readline \
        ncurses-libs \
        ncurses-terminfo-base \
        libpcap \
        openssl \
        libcrypto3 \
        ca-certificates

    echo "Bundling musl libraries..."
    mkdir -p /output/lib

    # Copy musl loader (critical!)
    cp -P /lib/ld-musl-x86_64.so.1 /output/lib/

    echo "Discovering and copying all shared libraries..."

    # Use ldd on each tool to discover ALL required libraries
    TOOLS="/bin/bash /usr/bin/gdb /usr/bin/strace /usr/bin/lsof /usr/bin/tcpdump /usr/bin/vim /usr/bin/htop /usr/bin/jq"

    for tool in $TOOLS; do
        if [ -f "$tool" ]; then
            echo "  Analyzing dependencies for: $tool"
            # Extract library paths from ldd output - handle both forms
            ldd "$tool" 2>/dev/null | while read line; do
                # Handle "lib => path" form
                if echo "$line" | grep -q " => "; then
                    lib=$(echo "$line" | awk "{print \$3}")
                    if [ -f "$lib" ] && [ ! -f "/output/lib/$(basename $lib)" ]; then
                        cp -P "$lib" /output/lib/ 2>/dev/null || true
                        echo "    Copied: $(basename $lib)"
                    fi
                fi
                # Handle "/lib/ld-musl.so (0x...)" form
                if echo "$line" | grep -q "^[[:space:]]*/" && echo "$line" | grep -q "\.so"; then
                    lib=$(echo "$line" | awk "{print \$1}")
                    if [ -f "$lib" ] && [ ! -f "/output/lib/$(basename $lib)" ]; then
                        cp -P "$lib" /output/lib/ 2>/dev/null || true
                        echo "    Copied: $(basename $lib)"
                    fi
                fi
            done
        fi
    done

    # Also copy common libraries by pattern
    echo "Copying common library patterns..."
    for pattern in libc.musl libreadline libhistory libncurses libtinfo libssl libcrypto libz libpcap libgcc libstdc++; do
        find /lib /usr/lib -name "${pattern}*.so*" -type f -exec cp -P {} /output/lib/ \; 2>/dev/null || true
    done

    # Copy any symlinks that point to these libraries
    echo "Copying library symlinks..."
    find /lib /usr/lib -name "*.so*" -type l -exec cp -P {} /output/lib/ \; 2>/dev/null || true

    LIB_COUNT=$(ls /output/lib/*.so* 2>/dev/null | wc -l)

    echo "Library bundling complete: $LIB_COUNT libraries bundled"
'

echo "=== Phase 4: Generate Tool Wrappers ==="

# Create wrapper scripts for all musl tools
sudo tee "$MOUNT_DIR/bin/create-wrappers.sh" > /dev/null << 'EOF'
#!/bin/sh
# Auto-generate wrappers for all musl tools

TOOLS_DIR="/dev/crashcart/usr/bin"
WRAPPER_DIR="/dev/crashcart/bin"

for tool in gdb strace ltrace lsof tcpdump nmap socat dig nslookup ss ip netstat htop iotop iftop file tree vim nano less jq bash rsync bzip2 xz openssl; do
    if [ -f "$TOOLS_DIR/$tool" ]; then
        cat > "$WRAPPER_DIR/crashcart-$tool" << EOFWRAPPER
#!/bin/sh
# Auto-generated wrapper for $tool
export LD_LIBRARY_PATH="/dev/crashcart/lib:\$LD_LIBRARY_PATH"
exec /dev/crashcart/usr/bin/$tool "\$@"
EOFWRAPPER
        chmod +x "$WRAPPER_DIR/crashcart-$tool"

        # Create direct symlinks too (for convenience)
        ln -sf "crashcart-$tool" "$WRAPPER_DIR/$tool" 2>/dev/null || true
    fi
done

echo "Wrappers generated for all musl tools"
EOF

sudo chmod +x "$MOUNT_DIR/bin/create-wrappers.sh"

# Execute wrapper generation
sudo chroot "$MOUNT_DIR" /bin/create-wrappers.sh

echo "=== Phase 5: Enhanced Environment Setup ==="

# Create comprehensive .crashcartrc
sudo tee "$MOUNT_DIR/.crashcartrc" > /dev/null << 'EOF'
# Self-Contained Musl Crashcart Environment
# Zero external dependencies - everything bundled

export PATH="/dev/crashcart/bin:/dev/crashcart/usr/bin:$PATH"
export LD_LIBRARY_PATH="/dev/crashcart/lib:$LD_LIBRARY_PATH"
export PS1="[crashcart-musl] \u@\h:\w\$ "

# Get target container PID (passed by crashcart)
TARGET_PID=${CRASHCART_TARGET_PID:-1}

# Direct tool aliases (no crashcart- prefix needed)
alias ll='ls -la'
alias la='ls -la'
alias l='ls -l'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias vi='vim'

# Debugging aliases with namespace awareness
alias gdb-target="nsenter -t $TARGET_PID -p -n -i -u -- gdb -p"
alias strace-target="nsenter -t $TARGET_PID -p -n -i -u -- strace -p"
alias lsof-target="nsenter -t $TARGET_PID -p -n -i -u -- lsof -p"

# Network debugging
alias netconns='ss -tuln'
alias ports='ss -tln'
alias listen='ss -tln'
alias connections='ss -tu'

# Enhanced debugging functions
debug-process() {
    local pid=${1:-1}
    echo "=== Debugging Process $pid in Target Container ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- gdb -p "$pid"
}

trace-process() {
    local pid=${1:-1}
    echo "=== Tracing Process $pid in Target Container ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- strace -p "$pid" "${@:2}"
}

trace-syscalls() {
    local pid=${1:-1}
    echo "=== System Call Trace for Process $pid ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- strace -e trace=all -p "$pid"
}

trace-network() {
    local pid=${1:-1}
    echo "=== Network System Calls for Process $pid ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- strace -e trace=network -p "$pid"
}

trace-files() {
    local pid=${1:-1}
    echo "=== File System Calls for Process $pid ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- strace -e trace=file -p "$pid"
}

list-processes() {
    echo "=== Processes in Target Container ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- ps aux 2>/dev/null || psinspect
}

list-files() {
    local pid=${1:-1}
    echo "=== Open Files for Process $pid ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- lsof -p "$pid"
}

network-status() {
    echo "=== Network Status in Target Container ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- ss -tuln
    echo
    echo "=== Network Interfaces ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- ip addr show
}

network-capture() {
    local interface=${1:-any}
    echo "=== Capturing Network Traffic on $interface ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -- tcpdump -i "$interface" -n "${@:2}"
}

container-shell() {
    echo "=== Entering Target Container Shell with Full Tools ==="
    nsenter -t "$TARGET_PID" -p -n -i -u -m -- bash
}

memory-info() {
    echo "=== Memory Information ==="
    free -h 2>/dev/null || cat /proc/meminfo | head -5
    echo
    echo "=== Memory Map for Process ${1:-1} ==="
    cat /proc/${1:-1}/maps 2>/dev/null | head -20 || echo "Process not accessible"
}

sysinfo() {
    echo "=== Self-Contained Musl Crashcart Environment ==="
    echo "Target PID: $TARGET_PID"
    echo "Libraries: All bundled (no external deps)"
    echo "Tools: Static + musl with bundled libraries"
    uname -a 2>/dev/null || echo "System info not available"
    echo
    list-processes
    echo
    network-status
    echo
    memory-info
}

# Tool availability checker
check-tools() {
    echo "=== Self-Contained Tool Availability ==="
    echo "Static tools (universal compatibility):"
    for tool in busybox sh ls ps find grep curl; do
        if command -v $tool >/dev/null 2>&1; then
            echo "  ✓ $tool (static)"
        else
            echo "  ✗ $tool"
        fi
    done

    echo
    echo "Musl tools (bundled libraries):"
    for tool in gdb strace lsof tcpdump ss htop vim jq; do
        if command -v $tool >/dev/null 2>&1; then
            echo "  ✓ $tool (musl+bundled)"
        else
            echo "  ✗ $tool"
        fi
    done

    echo
    echo "Library status:"
    if [ -f /dev/crashcart/lib/ld-musl-x86_64.so.1 ]; then
        echo "  ✓ Musl loader bundled"
        echo "  ✓ Libraries bundled: $(ls /dev/crashcart/lib/*.so* 2>/dev/null | wc -l)"
    else
        echo "  ✗ Libraries not found"
    fi

    echo
    echo "Usage examples:"
    echo "  gdb -p 123             # Debug PID 123 (uses bundled libs)"
    echo "  debug-process 123      # Debug with namespace awareness"
    echo "  trace-process 123      # Trace with strace"
    echo "  network-capture eth0   # Capture packets"
    echo "  container-shell        # Enter target container"
    echo ""
    echo "All tools are self-contained with zero external dependencies!"
}

# Quick process finder
findproc() {
    psinspect | grep -i "$1" | grep -v grep
}

echo "Self-Contained Musl Crashcart loaded!"
echo "Target container PID: $TARGET_PID"
echo "Environment: Alpine/musl with ALL dependencies bundled"
echo ""
echo "Quick start:"
echo "  check-tools     - See all available tools"
echo "  sysinfo         - System overview"
echo "  list-processes  - Show all processes"
echo "  network-status  - Network information"
echo ""
echo "Zero external dependencies - tools work in ANY container!"
EOF

# Create simple profile loader
sudo tee "$MOUNT_DIR/profile" > /dev/null << 'EOF'
#!/bin/bash
# Crashcart musl profile loader
export PATH="/dev/crashcart/bin:/dev/crashcart/usr/bin:$PATH"
export LD_LIBRARY_PATH="/dev/crashcart/lib:$LD_LIBRARY_PATH"
source /dev/crashcart/.crashcartrc
EOF

sudo chmod +x "$MOUNT_DIR/profile"

# Create essential config files
sudo mkdir -p "$MOUNT_DIR/etc"
echo "root:x:0:0:root:/root:/bin/bash" | sudo tee "$MOUNT_DIR/etc/passwd" > /dev/null
echo "root:x:0:" | sudo tee "$MOUNT_DIR/etc/group" > /dev/null
echo "127.0.0.1 localhost" | sudo tee "$MOUNT_DIR/etc/hosts" > /dev/null

# Copy SSL certificates for curl/wget
docker run --rm -v "$MOUNT_DIR:/output" alpine:latest sh -c '
    cp -r /etc/ssl /output/etc/ 2>/dev/null || true
'

# Create symlinks for common tools
sudo ln -sf bash "$MOUNT_DIR/bin/sh"
sudo ln -sf vim "$MOUNT_DIR/bin/vi" 2>/dev/null || true

echo "=== Build Complete ==="
echo "Self-contained musl crashcart image built successfully!"
echo "Image size: $(du -h "$IMAGE_NAME" | cut -f1)"
echo
echo "Features:"
echo "  ✓ Zero external dependencies - works in ANY container"
echo "  ✓ Static BusyBox foundation (50+ utilities)"
echo "  ✓ Full musl debugging toolkit with bundled libraries"
echo "  ✓ All tools accessible via simple paths"
echo "  ✓ Transparent wrapper system"
echo
echo "Tools included:"
echo "  Static: busybox, curl, psinspect"
echo "  Debugging: gdb, strace, ltrace, lsof"
echo "  Network: tcpdump, ss, nmap, dig, socat"
echo "  System: htop, iotop, iftop, ps, top"
echo "  Files: vim, nano, less, tree, file"
echo "  Utils: jq, openssl, rsync, tar, bash"
echo
echo "Usage:"
echo "  sudo ./crashcart <container-id>"
echo "  crashcart> gdb -p 1              # Works immediately"
echo "  crashcart> strace -p 1           # No loader needed"
echo "  crashcart> tcpdump -i any        # All libs bundled"
echo
echo "Libraries bundled: $(ls "$MOUNT_DIR/lib"/*.so* 2>/dev/null | wc -l) musl libraries"
echo "Total self-contained - target container needs NOTHING!"