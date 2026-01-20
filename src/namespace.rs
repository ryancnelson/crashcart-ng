use anyhow::{anyhow, Context, Result};
use nix::fcntl::{open, OFlag};
use nix::sched::{setns, CloneFlags};
use nix::sys::stat::Mode;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use tokio::process::Command;
use tracing::{debug, info};

pub struct NamespaceManager;

impl NamespaceManager {
    pub fn new() -> Self {
        Self
    }

    /// Enter the mount namespace of the target process
    pub fn enter_mount_namespace(&self, pid: u32) -> Result<NamespaceGuard> {
        let current_ns = self.open_current_namespace("mnt")?;
        let target_ns = self.open_target_namespace(pid, "mnt")?;

        // Check if we're already in the same namespace
        if self.same_namespace(&current_ns, &target_ns)? {
            return Ok(NamespaceGuard::new(None));
        }

        // Enter the target namespace
        setns(&target_ns, CloneFlags::CLONE_NEWNS)
            .context("Failed to enter mount namespace")?;

        debug!("Entered mount namespace of PID {}", pid);

        Ok(NamespaceGuard::new(Some(current_ns)))
    }

    fn open_current_namespace(&self, ns_type: &str) -> Result<OwnedFd> {
        let path = format!("/proc/self/ns/{}", ns_type);
        let fd = open(&*path, OFlag::O_RDONLY, Mode::empty())
            .context("Failed to open current namespace")?;
        Ok(unsafe { OwnedFd::from_raw_fd(fd) })
    }

    fn open_target_namespace(&self, pid: u32, ns_type: &str) -> Result<OwnedFd> {
        let path = format!("/proc/{}/ns/{}", pid, ns_type);
        let fd = open(&*path, OFlag::O_RDONLY, Mode::empty())
            .context("Failed to open target namespace")?;
        Ok(unsafe { OwnedFd::from_raw_fd(fd) })
    }

    fn same_namespace(&self, fd1: &OwnedFd, fd2: &OwnedFd) -> Result<bool> {
        use nix::sys::stat::fstat;

        let stat1 = fstat(fd1.as_raw_fd()).context("Failed to stat namespace fd1")?;
        let stat2 = fstat(fd2.as_raw_fd()).context("Failed to stat namespace fd2")?;

        Ok(stat1.st_dev == stat2.st_dev && stat1.st_ino == stat2.st_ino)
    }
}

pub struct NamespaceGuard {
    original_ns: Option<OwnedFd>,
}

impl NamespaceGuard {
    fn new(original_ns: Option<OwnedFd>) -> Self {
        Self { original_ns }
    }
}

impl Drop for NamespaceGuard {
    fn drop(&mut self) {
        if let Some(ref fd) = self.original_ns {
            if let Err(e) = setns(fd, CloneFlags::CLONE_NEWNS) {
                tracing::warn!("Failed to restore original namespace: {}", e);
            }
        }
    }
}

/// Execute a command in the target process's namespaces
pub async fn exec_in_namespace(pid: u32, command: &[String], env_var: Option<(&str, &str)>) -> Result<i32> {
    let cmd = if command.is_empty() {
        vec![
            "/dev/crashcart/lib64/ld-linux-x86-64.so.2".to_string(),
            "--library-path".to_string(),
            "/dev/crashcart/lib:/dev/crashcart/lib64:/dev/crashcart/usr/lib:/dev/crashcart/usr/lib64".to_string(),
            "/dev/crashcart/usr/bin/bash".to_string(),
            "--rcfile".to_string(),
            "/dev/crashcart/.crashcartrc".to_string(),
            "-i".to_string(),
        ]
    } else {
        // For custom commands, also use the dynamic linker
        let mut cmd_vec = vec![
            "/dev/crashcart/lib64/ld-linux-x86-64.so.2".to_string(),
            "--library-path".to_string(),
            "/dev/crashcart/lib:/dev/crashcart/lib64:/dev/crashcart/usr/lib:/dev/crashcart/usr/lib64".to_string(),
        ];
        cmd_vec.extend(command.iter().cloned());
        cmd_vec
    };

    // Use nsenter to execute the command in all namespaces
    let mut nsenter_cmd = Command::new("nsenter");
    nsenter_cmd
        .args([
            "-t", &pid.to_string(),
            "-m", "-u", "-i", "-n", "-p",
            "--"
        ])
        .args(&cmd);

    // Add environment variable if provided
    if let Some((key, value)) = env_var {
        nsenter_cmd.env(key, value);
    }

    let status = nsenter_cmd
        .status()
        .await
        .context("Failed to execute nsenter")?;

    Ok(status.code().unwrap_or(-1))
}

/// Enter all namespaces of the target process (for more complex operations)
pub fn enter_all_namespaces(pid: u32) -> Result<Vec<NamespaceGuard>> {
    let namespaces = ["mnt", "uts", "ipc", "net", "pid", "cgroup"];
    let mut guards = Vec::new();

    for ns_type in &namespaces {
        match enter_single_namespace(pid, ns_type) {
            Ok(guard) => guards.push(guard),
            Err(e) => {
                debug!("Failed to enter {} namespace: {}", ns_type, e);
                // Some namespaces might not exist or be accessible
                guards.push(NamespaceGuard::new(None));
            }
        }
    }

    info!("Entered namespaces for PID {}", pid);
    Ok(guards)
}

fn enter_single_namespace(pid: u32, ns_type: &str) -> Result<NamespaceGuard> {
    let current_path = format!("/proc/self/ns/{}", ns_type);
    let target_path = format!("/proc/{}/ns/{}", pid, ns_type);

    let current_fd_raw = open(&*current_path, OFlag::O_RDONLY, Mode::empty())
        .context("Failed to open current namespace")?;
    let current_fd = unsafe { OwnedFd::from_raw_fd(current_fd_raw) };

    let target_fd_raw = open(&*target_path, OFlag::O_RDONLY, Mode::empty())
        .context("Failed to open target namespace")?;
    let target_fd = unsafe { OwnedFd::from_raw_fd(target_fd_raw) };

    // Check if already in the same namespace
    use nix::sys::stat::fstat;
    let current_stat = fstat(current_fd.as_raw_fd())?;
    let target_stat = fstat(target_fd.as_raw_fd())?;

    if current_stat.st_dev == target_stat.st_dev && current_stat.st_ino == target_stat.st_ino {
        return Ok(NamespaceGuard::new(None));
    }

    // Enter the namespace
    let clone_flag = match ns_type {
        "mnt" => CloneFlags::CLONE_NEWNS,
        "uts" => CloneFlags::CLONE_NEWUTS,
        "ipc" => CloneFlags::CLONE_NEWIPC,
        "net" => CloneFlags::CLONE_NEWNET,
        "pid" => CloneFlags::CLONE_NEWPID,
        "cgroup" => CloneFlags::CLONE_NEWCGROUP,
        "user" => CloneFlags::CLONE_NEWUSER,
        _ => return Err(anyhow!("Unknown namespace type: {}", ns_type)),
    };

    setns(&target_fd, clone_flag)
        .context(format!("Failed to enter {} namespace", ns_type))?;

    // Handle user namespace special case
    if ns_type == "user" {
        // Set uid/gid to root in the new namespace
        unsafe {
            libc::setresgid(0, 0, 0);
            libc::setresuid(0, 0, 0);
        }
    }

    Ok(NamespaceGuard::new(Some(current_fd)))
}