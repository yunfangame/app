#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
use crate::service::hub::run_service;
#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
use tokio::runtime::Runtime;

mod service;

#[cfg(all(feature = "windows-service", target_os = "windows"))]
pub fn main() {
    if let Err(error) = service::windows::main() {
        eprintln!("{error:#}");
        std::process::exit(service::windows::command_exit_code(&error));
    }
}

#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
fn main() {
    if let Ok(rt) = Runtime::new() {
        rt.block_on(async {
            let _ = run_service().await;
        });
    }
}
