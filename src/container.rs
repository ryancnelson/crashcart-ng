use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use std::process::Stdio;
use tokio::process::Command;
use tracing::{debug, info};

#[derive(Debug, Clone)]
pub enum ContainerRuntime {
    Docker { id: String },
    Containerd { id: String },
    Podman { id: String },
    Pid { pid: u32 },
}

impl ContainerRuntime {
    pub async fn detect(target: &str) -> Result<Self> {
        // First try to parse as PID
        if let Ok(pid) = target.parse::<u32>() {
            return Ok(ContainerRuntime::Pid { pid });
        }

        // Try Docker first
        if let Ok(runtime) = Self::try_docker(target).await {
            return Ok(runtime);
        }

        // Try Podman
        if let Ok(runtime) = Self::try_podman(target).await {
            return Ok(runtime);
        }

        // Try containerd
        if let Ok(runtime) = Self::try_containerd(target).await {
            return Ok(runtime);
        }

        Err(anyhow!("Could not find container or process with ID: {}", target))
    }

    async fn try_docker(id: &str) -> Result<Self> {
        let output = Command::new("docker")
            .args(["inspect", id])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await?;

        if output.status.success() {
            info!("Detected Docker container: {}", id);
            Ok(ContainerRuntime::Docker { id: id.to_string() })
        } else {
            Err(anyhow!("Docker container not found"))
        }
    }

    async fn try_podman(id: &str) -> Result<Self> {
        let output = Command::new("podman")
            .args(["inspect", id])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await?;

        if output.status.success() {
            info!("Detected Podman container: {}", id);
            Ok(ContainerRuntime::Podman { id: id.to_string() })
        } else {
            Err(anyhow!("Podman container not found"))
        }
    }

    async fn try_containerd(id: &str) -> Result<Self> {
        let output = Command::new("ctr")
            .args(["container", "info", id])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await?;

        if output.status.success() {
            info!("Detected containerd container: {}", id);
            Ok(ContainerRuntime::Containerd { id: id.to_string() })
        } else {
            Err(anyhow!("Containerd container not found"))
        }
    }

    pub async fn get_pid(&self) -> Result<u32> {
        match self {
            ContainerRuntime::Pid { pid } => Ok(*pid),
            ContainerRuntime::Docker { id } => self.get_docker_pid(id).await,
            ContainerRuntime::Podman { id } => self.get_podman_pid(id).await,
            ContainerRuntime::Containerd { id } => self.get_containerd_pid(id).await,
        }
    }

    async fn get_docker_pid(&self, id: &str) -> Result<u32> {
        let output = Command::new("docker")
            .args(["inspect", "--format", "{{.State.Pid}}", id])
            .output()
            .await
            .context("Failed to get Docker container PID")?;

        let pid_str = String::from_utf8(output.stdout)?;
        let pid = pid_str.trim().parse::<u32>()
            .context("Failed to parse Docker PID")?;

        debug!("Docker container {} has PID {}", id, pid);
        Ok(pid)
    }

    async fn get_podman_pid(&self, id: &str) -> Result<u32> {
        let output = Command::new("podman")
            .args(["inspect", "--format", "{{.State.Pid}}", id])
            .output()
            .await
            .context("Failed to get Podman container PID")?;

        let pid_str = String::from_utf8(output.stdout)?;
        let pid = pid_str.trim().parse::<u32>()
            .context("Failed to parse Podman PID")?;

        debug!("Podman container {} has PID {}", id, pid);
        Ok(pid)
    }

    async fn get_containerd_pid(&self, id: &str) -> Result<u32> {
        let output = Command::new("ctr")
            .args(["task", "list", "--format", "json"])
            .output()
            .await
            .context("Failed to list containerd tasks")?;

        let tasks: Vec<Value> = serde_json::from_slice(&output.stdout)?;
        
        for task in tasks {
            if let Some(task_id) = task.get("ID").and_then(|v| v.as_str()) {
                if task_id.starts_with(id) {
                    if let Some(pid) = task.get("Pid").and_then(|v| v.as_u64()) {
                        debug!("Containerd container {} has PID {}", id, pid);
                        return Ok(pid as u32);
                    }
                }
            }
        }

        Err(anyhow!("Could not find PID for containerd container {}", id))
    }

    pub async fn exec_command(&self, command: &[String]) -> Result<i32> {
        let cmd = if command.is_empty() {
            vec![
                "/dev/crashcart/bin/bash".to_string(),
                "--rcfile".to_string(),
                "/dev/crashcart/.crashcartrc".to_string(),
                "-i".to_string(),
            ]
        } else {
            command.to_vec()
        };

        match self {
            ContainerRuntime::Docker { id } => {
                let mut args = vec!["exec".to_string(), "-it".to_string(), id.clone()];
                args.extend(cmd);
                
                let status = Command::new("docker")
                    .args(&args)
                    .status()
                    .await
                    .context("Failed to execute docker exec")?;

                Ok(status.code().unwrap_or(-1))
            }
            ContainerRuntime::Podman { id } => {
                let mut args = vec!["exec".to_string(), "-it".to_string(), id.clone()];
                args.extend(cmd);
                
                let status = Command::new("podman")
                    .args(&args)
                    .status()
                    .await
                    .context("Failed to execute podman exec")?;

                Ok(status.code().unwrap_or(-1))
            }
            ContainerRuntime::Containerd { id } => {
                let mut args = vec!["task".to_string(), "exec".to_string(), "--exec-id".to_string(), 
                                   format!("crashcart-{}", std::process::id()), id.clone()];
                args.extend(cmd);
                
                let status = Command::new("ctr")
                    .args(&args)
                    .status()
                    .await
                    .context("Failed to execute ctr task exec")?;

                Ok(status.code().unwrap_or(-1))
            }
            ContainerRuntime::Pid { .. } => {
                Err(anyhow!("Cannot use exec mode with raw PID"))
            }
        }
    }
}