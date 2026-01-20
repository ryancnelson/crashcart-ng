use anyhow::{anyhow, Context, Result};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use tracing::{debug, info};

// Make ImageManager cloneable for async operations
#[derive(Clone)]
pub struct ImageManager {
    image_path: PathBuf,
    loop_device: Option<String>,
}

impl ImageManager {
    pub fn new(image_path: &Path) -> Result<Self> {
        if !image_path.exists() {
            return Err(anyhow!("Image file does not exist: {}", image_path.display()));
        }

        Ok(Self {
            image_path: image_path.to_path_buf(),
            loop_device: None,
        })
    }

    pub async fn setup_loop_device(&mut self) -> Result<String> {
        if let Some(ref device) = self.loop_device {
            return Ok(device.clone());
        }

        // Get a free loop device
        let device = self.get_free_loop_device().await?;
        
        // Associate the image with the loop device
        self.associate_loop_device(&device).await?;
        
        self.loop_device = Some(device.clone());
        info!("Associated {} with {}", self.image_path.display(), device);
        
        Ok(device)
    }

    async fn get_free_loop_device(&self) -> Result<String> {
        use tokio::process::Command;

        let output = Command::new("losetup")
            .args(["-f"])
            .output()
            .await
            .context("Failed to find free loop device")?;

        if !output.status.success() {
            return Err(anyhow!("losetup -f failed"));
        }

        let device = String::from_utf8(output.stdout)?
            .trim()
            .to_string();

        debug!("Found free loop device: {}", device);
        Ok(device)
    }

    async fn associate_loop_device(&self, device: &str) -> Result<()> {
        use tokio::process::Command;

        let status = Command::new("losetup")
            .args([device, &self.image_path.to_string_lossy()])
            .status()
            .await
            .context("Failed to associate loop device")?;

        if !status.success() {
            return Err(anyhow!("Failed to associate {} with {}", device, self.image_path.display()));
        }

        Ok(())
    }

    pub async fn cleanup_loop_device(&mut self) -> Result<()> {
        if let Some(ref device) = self.loop_device {
            use tokio::process::Command;

            let status = Command::new("losetup")
                .args(["-d", device])
                .status()
                .await
                .context("Failed to detach loop device")?;

            if !status.success() {
                return Err(anyhow!("Failed to detach loop device {}", device));
            }

            info!("Detached loop device {}", device);
            self.loop_device = None;
        }

        Ok(())
    }

    pub fn get_loop_device(&self) -> Option<&str> {
        self.loop_device.as_deref()
    }

    pub fn image_path(&self) -> &Path {
        &self.image_path
    }

    /// Verify the image is a valid filesystem image
    pub fn verify_image(&self) -> Result<()> {
        let mut file = File::open(&self.image_path)
            .context("Failed to open image file")?;

        // Check file size
        let metadata = file.metadata()
            .context("Failed to get image metadata")?;
        
        if metadata.len() < 1024 {
            return Err(anyhow!("Image file too small"));
        }

        // Try to read the beginning to see if it looks like a filesystem
        let mut buffer = [0u8; 1024];
        file.read_exact(&mut buffer)
            .context("Failed to read image header")?;

        // Basic check for ext2/3/4 magic number at offset 1080
        file.seek(SeekFrom::Start(1080))
            .context("Failed to seek to ext magic")?;
        
        let mut magic = [0u8; 2];
        if file.read_exact(&mut magic).is_ok() {
            if magic == [0x53, 0xEF] {
                debug!("Detected ext2/3/4 filesystem in image");
                return Ok(());
            }
        }

        // If not ext, assume it's a tar.gz or other archive format
        debug!("Image appears to be an archive format");
        Ok(())
    }
}

impl Drop for ImageManager {
    fn drop(&mut self) {
        if self.loop_device.is_some() {
            // Note: In a real implementation, you might want to use a runtime
            // to properly clean up async resources
            tracing::warn!("Loop device not properly cleaned up");
        }
    }
}