use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;
use tracing::info;

mod container;
mod image;
mod mount;
mod namespace;

use container::ContainerRuntime;
use image::ImageManager;
use mount::MountManager;

#[derive(Parser)]
#[command(name = "crashcart")]
#[command(about = "A modern container debugging tool")]
#[command(version)]
struct Cli {
    /// Container ID or process PID to attach to
    target: String,

    /// Path to crashcart image file
    #[arg(short, long, default_value = "crashcart.img")]
    image: PathBuf,

    /// Only mount the image, don't execute command
    #[arg(short, long)]
    mount_only: bool,

    /// Only unmount the image
    #[arg(short, long)]
    unmount: bool,

    /// Use container runtime exec instead of namespace manipulation
    #[arg(short, long)]
    exec: bool,

    /// Verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Command to run (defaults to interactive bash)
    command: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize logging
    let log_level = if cli.verbose { "debug" } else { "info" };
    tracing_subscriber::fmt()
        .with_env_filter(format!("crashcart={}", log_level))
        .init();

    info!("Starting crashcart v{}", env!("CARGO_PKG_VERSION"));

    // Detect container runtime and get PID
    info!("Detecting container runtime...");
    let runtime = ContainerRuntime::detect(&cli.target).await?;
    let pid = runtime.get_pid().await?;
    
    info!("Target PID: {}", pid);

    info!("Creating image manager...");
    let image_manager = ImageManager::new(&cli.image)?;
    info!("Creating mount manager...");
    let mount_manager = MountManager::new();

    // Handle unmount-only case
    if cli.unmount {
        info!("Unmount-only mode");
        mount_manager.unmount_with_nsenter(pid, &image_manager).await?;
        info!("Successfully unmounted crashcart from PID {}", pid);
        return Ok(());
    }

    // Mount the image using nsenter approach
    info!("Starting mount operation...");
    mount_manager.mount_with_nsenter(pid, &image_manager).await?;
    info!("Successfully mounted crashcart image");

    if cli.mount_only {
        info!("Mount-only mode: crashcart image is now available at /dev/crashcart");
        return Ok(());
    }

    // Execute command
    let exit_code = if cli.exec {
        runtime.exec_command(&cli.command).await?
    } else {
        namespace::exec_in_namespace(pid, &cli.command, Some(("CRASHCART_TARGET_PID", &pid.to_string()))).await?
    };

    // Cleanup
    if !cli.mount_only {
        mount_manager.unmount_with_nsenter(pid, &image_manager).await?;
    }

    std::process::exit(exit_code);
}