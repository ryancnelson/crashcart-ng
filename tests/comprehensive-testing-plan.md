# Comprehensive Production Testing Plan for crashcart-ng

**Goal:** Ensure crashcart-ng is production-ready for public release, demonstrating operational excellence.

## Testing Categories (In Priority Order)

### A. Command Validation Testing
Every usage example must work exactly as documented.

### B. Real Environment Testing
Test across different container runtimes, host environments, and container types.

### C. End-to-End Workflow Testing
Complete user debugging journeys from crisis to resolution.

### D. Instruction Verification Testing
Reproduce exact user experience following documentation.

## Critical Production Scenarios

### Crisis Debugging Scenarios

1. **Container Hanging/Deadlocked**
   - Symptoms: Container stops responding to health checks
   - Workflow: crashcart → ps → gdb attach → thread backtraces
   - Success: Identify deadlock location

2. **Memory Leak Investigation**
   - Symptoms: Container memory climbing steadily
   - Workflow: crashcart → htop → /proc/maps → gdb heap analysis
   - Success: Find memory allocation source

3. **Network Connectivity Failure**
   - Symptoms: App can't reach external services
   - Workflow: crashcart → tcpdump → ss → dig → route analysis
   - Success: Identify network blockage

4. **CPU Spike Investigation**
   - Symptoms: Container using 100% CPU
   - Workflow: crashcart → htop → gdb hot attach → stack traces
   - Success: Find tight loop or blocking code

5. **Container Startup Failure**
   - Symptoms: Container crashes immediately on start
   - Workflow: crashcart → ps history → dmesg → strace init
   - Success: Identify startup failure cause

6. **File Descriptor Exhaustion**
   - Symptoms: "Too many open files" errors
   - Workflow: crashcart → lsof → /proc/PID/fd analysis
   - Success: Find FD leak source

## Container Environment Matrix

### Container Types (Must Work With All)
- [ ] Distroless containers (no shell/utils)
- [ ] Scratch containers (empty)
- [ ] Alpine Linux (musl libc)
- [ ] Ubuntu/Debian (glibc)
- [ ] RHEL/CentOS variants
- [ ] Multi-stage builds (minimal final stage)
- [ ] Custom minimal images
- [ ] AWS ECS agent container (proven hardest case)

### Container Runtimes
- [ ] Docker (standard)
- [ ] Podman
- [ ] containerd (direct)
- [ ] CRI-O (Kubernetes)
- [ ] AWS ECS tasks
- [ ] AWS Fargate

### Host Environments
- [ ] Ubuntu 20.04, 22.04, 24.04
- [ ] RHEL 8, 9
- [ ] Amazon Linux 2023
- [ ] Different kernel versions
- [ ] Different glibc versions
- [ ] SELinux enabled/disabled
- [ ] AppArmor enabled/disabled

## Critical Failure Modes to Test

### Permission/Security Issues
- [ ] SELinux blocking mount operations
- [ ] AppArmor restrictions
- [ ] User namespace isolation
- [ ] Seccomp filters blocking syscalls
- [ ] Read-only root filesystems
- [ ] Non-root container users

### Resource Constraints
- [ ] No available disk space
- [ ] Memory-limited containers
- [ ] PID namespace exhaustion
- [ ] Loop device limits reached
- [ ] /tmp filesystem full

### Container State Edge Cases
- [ ] Container restarting in loop
- [ ] Container in zombie state
- [ ] Multi-process containers (PID selection)
- [ ] Custom init systems (systemd, s6, etc.)
- [ ] Containers that exit on attach

### Tool Compatibility Issues
- [ ] ARM vs x86_64 architecture mismatch
- [ ] Kernel version incompatibilities
- [ ] Missing kernel modules (CONFIG_USER_NS, etc.)
- [ ] ptrace restrictions (Yama LSM)
- [ ] ASLR/hardening conflicts

### Environmental Conflicts
- [ ] Existing /dev/crashcart directory
- [ ] Conflicting loop device usage
- [ ] Mount namespace pollution
- [ ] Library version conflicts
- [ ] Busybox vs GNU tool conflicts

## Test Infrastructure Needed

### Test Containers
Need automated creation of:
- Minimal test applications (CPU spike, memory leak, network client)
- Different base images for compatibility testing
- Containers with specific failure modes
- Multi-process containers with realistic workloads

### Test Environments
- Container matrix generation
- Host environment simulation
- Kubernetes pod testing
- AWS ECS task testing
- Network isolation testing

### Automated Validation
- Command success/failure detection
- Expected output verification
- Resource cleanup validation
- Performance regression detection
- Documentation synchronization checks

## Success Criteria

### Reliability
- [ ] 100% of documented examples work
- [ ] Zero syntax/startup errors
- [ ] Clean resource cleanup in all cases
- [ ] Consistent behavior across environments

### User Experience
- [ ] Clear error messages for failures
- [ ] Graceful handling of edge cases
- [ ] Intuitive debugging workflows
- [ ] Fast mount/unmount operations

### Production Readiness
- [ ] Works in real crisis scenarios
- [ ] Handles production security constraints
- [ ] Scales to production workloads
- [ ] Integrates with existing tooling

---

**Started:** 2026-02-05
**Target:** Production release quality