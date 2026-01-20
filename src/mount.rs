use anyhow::{anyhow, Context, Result};
use nix::mount::{mount, umount, MsFlags};
use nix::sys::stat::{mknod, Mode, SFlag};
use std::fs::{create_dir_all, remove_dir_all};
use std::path::Path;
use tracing::{debug, info, warn};

use crate::image::ImageManager;
use crate::namespace::NamespaceManager;

const CRASHCART_MOUNT_PATH: &str = "/dev/crashcart";
const CRASHCART_LOOP_DIR: &str = "/dev/cc-loop";

pub struct MountManager {
    namespace_manager: NamespaceManager,
}

impl MountManager {
    pub fn new() -> Self {
        Self {
            namespace_manager: NamespaceManager::new(),
        }
    }

    pub async fn mount_with_nsenter(&self, pid: u32, image_manager: &ImageManager) -> Result<()> {
        info!("Starting mount_with_nsenter for PID {}", pid);
        
        // Verify image before mounting
        info!("Verifying image...");
        image_manager.verify_image()
            .context("Image verification failed")?;
        info!("Image verification successful");

        // Setup loop device
        info!("Setting up loop device...");
        let mut image_manager = image_manager.clone();
        let loop_device = image_manager.setup_loop_device().await?;
        info!("Loop device setup successful: {}", loop_device);

        // Use nsenter to execute mount commands in the target namespace
        info!("Preparing mount script...");
        let mount_script = format!(
            r#"#!/bin/bash
set -euo pipefail

# Check if already mounted
if mountpoint -q /dev/crashcart 2>/dev/null; then
    echo "Crashcart already mounted"
    exit 0
fi

# Create mount directories
mkdir -p /dev/cc-loop
mkdir -p /dev/crashcart

# Mount tmpfs for loop devices if not already mounted
if ! mountpoint -q /dev/cc-loop 2>/dev/null; then
    mount -t tmpfs tmpfs /dev/cc-loop
fi

# Create device node
mknod /dev/cc-loop/crashcart b 7 {} 2>/dev/null || true

# Mount the filesystem
mount -t ext4 -o ro /dev/cc-loop/crashcart /dev/crashcart

echo "Successfully mounted crashcart image"
"#,
            loop_device.strip_prefix("/dev/loop").unwrap_or("0")
        );

        // Execute the mount script using nsenter
        let mut cmd = tokio::process::Command::new("nsenter");
        cmd.args(["-t", &pid.to_string(), "-m", "--"])
            .args(["bash", "-c", &mount_script]);

        let output = cmd.output().await
            .context("Failed to execute mount script with nsenter")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow!("Mount script failed: {}", stderr));
        }

        info!("Successfully mounted crashcart image using nsenter");
        Ok(())
    }

    pub async fn unmount_with_nsenter(&self, pid: u32, image_manager: &ImageManager) -> Result<()> {
        // Use nsenter to execute unmount commands in the target namespace
        let unmount_script = r#"#!/bin/bash
set -euo pipefail

# Unmount the filesystem
if mountpoint -q /dev/crashcart 2>/dev/null; then
    umount /dev/crashcart
    echo "Unmounted crashcart filesystem"
fi

# Clean up directories
rm -rf /dev/crashcart

# Unmount tmpfs if mounted
if mountpoint -q /dev/cc-loop 2>/dev/null; then
    umount /dev/cc-loop
fi

rm -rf /dev/cc-loop

echo "Successfully cleaned up crashcart mount"
"#;

        // Execute the unmount script using nsenter
        let mut cmd = tokio::process::Command::new("nsenter");
        cmd.args(["-t", &pid.to_string(), "-m", "--"])
            .args(["bash", "-c", unmount_script]);

        let output = cmd.output().await
            .context("Failed to execute unmount script with nsenter")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            warn!("Unmount script failed: {}", stderr);
        }

        // Clean up loop device
        let mut image_manager = image_manager.clone();
        image_manager.cleanup_loop_device().await?;

        info!("Successfully unmounted crashcart using nsenter");
        Ok(())
    }

    pub async fn mount(&self, pid: u32, image_manager: &ImageManager) -> Result<()> {
        // Verify image before mounting
        image_manager.verify_image()
            .context("Image verification failed")?;

        // Setup loop device
        let mut image_manager = image_manager.clone();
        let loop_device = image_manager.setup_loop_device().await?;

        // Enter the target container's mount namespace
        let _guard = self.namespace_manager.enter_mount_namespace(pid)?;

        // Check if already mounted
        if self.is_mounted(CRASHCART_MOUNT_PATH)? {
            info!("Crashcart already mounted at {}", CRASHCART_MOUNT_PATH);
            return Ok(());
        }

        // Create mount directories
        self.setup_mount_directories()?;

        // Create device node in the container's namespace
        let device_path = format!("{}/crashcart", CRASHCART_LOOP_DIR);
        self.create_device_node(&device_path, &loop_device)?;

        // Mount the filesystem
        self.mount_filesystem(&device_path)?;

        // Setup the crashcart environment
        self.setup_crashcart_environment()?;

        info!("Successfully mounted crashcart image at {}", CRASHCART_MOUNT_PATH);
        Ok(())
    }

    pub async fn unmount(&self, pid: u32, image_manager: &ImageManager) -> Result<()> {
        // Enter the target container's mount namespace
        let _guard = self.namespace_manager.enter_mount_namespace(pid)?;

        // Unmount the filesystem
        if self.is_mounted(CRASHCART_MOUNT_PATH)? {
            umount(CRASHCART_MOUNT_PATH)
                .context("Failed to unmount crashcart filesystem")?;
            info!("Unmounted crashcart filesystem");
        }

        // Clean up directories
        self.cleanup_mount_directories()?;

        // Clean up loop device
        let mut image_manager = image_manager.clone();
        image_manager.cleanup_loop_device().await?;

        info!("Successfully unmounted crashcart");
        Ok(())
    }

    fn setup_mount_directories(&self) -> Result<()> {
        // Create the loop device directory
        create_dir_all(CRASHCART_LOOP_DIR)
            .context("Failed to create loop device directory")?;

        // Create the mount point
        create_dir_all(CRASHCART_MOUNT_PATH)
            .context("Failed to create mount point")?;

        // Mount tmpfs for loop devices (needed for user namespaces)
        if !self.is_mounted(CRASHCART_LOOP_DIR)? {
            mount(
                Some("tmpfs"),
                CRASHCART_LOOP_DIR,
                Some("tmpfs"),
                MsFlags::empty(),
                None::<&str>,
            ).context("Failed to mount tmpfs for loop devices")?;
        }

        Ok(())
    }

    fn cleanup_mount_directories(&self) -> Result<()> {
        // Remove mount point
        if Path::new(CRASHCART_MOUNT_PATH).exists() {
            if let Err(e) = remove_dir_all(CRASHCART_MOUNT_PATH) {
                warn!("Failed to remove mount point: {}", e);
            }
        }

        // Unmount and remove loop device directory
        if self.is_mounted(CRASHCART_LOOP_DIR).unwrap_or(false) {
            if let Err(e) = umount(CRASHCART_LOOP_DIR) {
                warn!("Failed to unmount loop device tmpfs: {}", e);
            }
        }

        if Path::new(CRASHCART_LOOP_DIR).exists() {
            if let Err(e) = remove_dir_all(CRASHCART_LOOP_DIR) {
                warn!("Failed to remove loop device directory: {}", e);
            }
        }

        Ok(())
    }

    fn create_device_node(&self, device_path: &str, loop_device: &str) -> Result<()> {
        // Extract device number from loop device path (e.g., /dev/loop0 -> 0)
        let device_num = loop_device
            .strip_prefix("/dev/loop")
            .and_then(|s| s.parse::<u32>().ok())
            .ok_or_else(|| anyhow!("Invalid loop device path: {}", loop_device))?;

        // Create device node
        let dev_t = nix::sys::stat::makedev(7, device_num.into()); // Loop devices are major 7
        
        if let Err(e) = mknod(
            device_path,
            SFlag::S_IFBLK,
            Mode::from_bits_truncate(0o660),
            dev_t,
        ) {
            if e != nix::errno::Errno::EEXIST {
                return Err(anyhow!("Failed to create device node: {}", e));
            }
        }

        debug!("Created device node at {}", device_path);
        Ok(())
    }

    fn mount_filesystem(&self, device_path: &str) -> Result<()> {
        // Try different filesystem types
        let fs_types = ["ext4", "ext3", "ext2"];
        
        for fs_type in &fs_types {
            match mount(
                Some(device_path),
                CRASHCART_MOUNT_PATH,
                Some(*fs_type),
                MsFlags::MS_RDONLY,
                None::<&str>,
            ) {
                Ok(()) => {
                    debug!("Mounted {} as {}", device_path, fs_type);
                    return Ok(());
                }
                Err(e) => {
                    debug!("Failed to mount as {}: {}", fs_type, e);
                    continue;
                }
            }
        }

        Err(anyhow!("Failed to mount filesystem with any supported type"))
    }

    fn setup_crashcart_environment(&self) -> Result<()> {
        use std::fs::write;

        // Create .crashcartrc file
        let rcfile_path = format!("{}/.crashcartrc", CRASHCART_MOUNT_PATH);
        let rcfile_content = format!(
            r#"# Crashcart environment setup
export PATH="{}:$PATH"
export PS1="[crashcart] \u@\h:\w\$ "
echo "Crashcart debugging environment loaded"
echo "Available tools in {}/bin and {}/sbin"
"#,
            format!("{}/bin", CRASHCART_MOUNT_PATH),
            CRASHCART_MOUNT_PATH,
            CRASHCART_MOUNT_PATH
        );

        write(&rcfile_path, rcfile_content)
            .context("Failed to create .crashcartrc")?;

        debug!("Created crashcart environment file");
        Ok(())
    }

    fn is_mounted(&self, path: &str) -> Result<bool> {
        use std::fs::File;
        use std::io::{BufRead, BufReader};

        let mounts_file = File::open("/proc/mounts")
            .context("Failed to open /proc/mounts")?;

        for line in BufReader::new(mounts_file).lines() {
            let line = line.context("Failed to read /proc/mounts line")?;
            let fields: Vec<&str> = line.split_whitespace().collect();
            
            if fields.len() >= 2 && fields[1] == path {
                return Ok(true);
            }
        }

        Ok(false)
    }
}