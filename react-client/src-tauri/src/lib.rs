#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(windows)]
    let _instance_guard = match instance::acquire().expect("Could not acquire FlowDay instance guard") {
        Some(guard) => guard,
        None => return,
    };
    let mut context = tauri::generate_context!();
    if let Some(directory) = std::env::var_os("FLOWDAY_TEST_DATA_DIR") {
        let directory = std::path::PathBuf::from(directory);
        assert!(directory.is_absolute(), "Test data directory must be absolute");
        for window in &mut context.config_mut().app.windows {
            window.data_directory = Some(directory.join("webview"));
        }
    }
    tauri::Builder::default()
        .manage(native::FileLock(std::sync::Mutex::new(())))
        .invoke_handler(tauri::generate_handler![native::workspace_read, native::sync_baseline_read, native::sync_baseline_write, native::workspace_write, native::workspace_backups, native::workspace_backup, native::workspace_backup_read, native::http_request, native::http_download, credentials::credential_read, credentials::credential_write, credentials::credential_delete])
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .run(context)
        .expect("FlowDay could not start");
}
mod native;
mod credentials;
#[cfg(windows)]
mod instance;
