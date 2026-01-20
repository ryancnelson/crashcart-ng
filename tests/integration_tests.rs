use std::path::Path;
use crashcart::{ContainerRuntime, ImageManager};

#[tokio::test]
async fn test_container_detection_with_invalid_id() {
    let result = ContainerRuntime::detect("nonexistent-container").await;
    assert!(result.is_err());
}

#[tokio::test]
async fn test_container_detection_with_pid() {
    // Test with current process PID
    let pid = std::process::id();
    let result = ContainerRuntime::detect(&pid.to_string()).await;
    assert!(result.is_ok());
    
    if let Ok(runtime) = result {
        match runtime {
            ContainerRuntime::Pid { pid: detected_pid } => {
                assert_eq!(detected_pid, pid);
            }
            _ => panic!("Expected PID runtime"),
        }
    }
}

#[test]
fn test_image_manager_with_nonexistent_file() {
    let result = ImageManager::new(Path::new("nonexistent.img"));
    assert!(result.is_err());
}

#[test]
fn test_image_manager_creation() {
    // Create a temporary file for testing
    let temp_file = std::env::temp_dir().join("test.img");
    std::fs::write(&temp_file, b"test data").unwrap();
    
    let result = ImageManager::new(&temp_file);
    assert!(result.is_ok());
    
    // Cleanup
    std::fs::remove_file(&temp_file).unwrap();
}