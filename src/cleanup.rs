//! Cleanup utilities for crashcart resources

use anyhow::{Context, Result};
use std::process::Command;
use tracing::{info, warn};

/// Cleanup loop devices associated with crashcart.img
pub fn cleanup_loop_devices() -> Result<()> {
    info!("Cleaning up loop devices...");

    // Find all loop devices with crashcart.img
    let output = Command::new("losetup")
        .args(&["-a"])
        .output()
        .context("Failed to list loop devices")?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut cleaned = 0;

    for line in stdout.lines() {
        if line.contains("crashcart.img") {
            // Extract loop device name (e.g., /dev/loop8)
            if let Some(device) = line.split(':').next() {
                info!("Detaching loop device: {}", device);

                let result = Command::new("losetup")
                    .args(&["-d", device])
                    .status()
                    .context("Failed to detach loop device")?;

                if result.success() {
                    cleaned += 1;
                } else {
                    warn!("Failed to detach loop device: {}", device);
                }
            }
        }
    }

    if cleaned > 0 {
        info!("Cleaned up {} loop device(s)", cleaned);
    }

    Ok(())
}

/// Cleanup on drop guard
pub struct CleanupGuard;

impl Drop for CleanupGuard {
    fn drop(&mut self) {
        if let Err(e) = cleanup_loop_devices() {
            warn!("Cleanup failed: {}", e);
        }
    }
}