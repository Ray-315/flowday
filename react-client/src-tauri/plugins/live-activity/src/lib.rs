use tauri::{plugin::{Builder, TauriPlugin}, Runtime};
#[cfg(target_os = "ios")]
use tauri::Manager;
#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_live_activity);
#[cfg(target_os = "ios")]
struct Native<R: Runtime>(tauri::plugin::PluginHandle<R>);

fn call<R: Runtime>(app: &tauri::AppHandle<R>, command: &str, data: serde_json::Value) -> Result<serde_json::Value, String> {
    #[cfg(target_os = "ios")]
    { app.state::<Native<R>>().0.run_mobile_plugin(command, data).map_err(|e| e.to_string()) }
    #[cfg(not(target_os = "ios"))]
    { let _ = (app, command, data); Ok(serde_json::json!({"supported": false, "enabled": false, "active": null})) }
}
#[tauri::command]
async fn status<R: Runtime>(app: tauri::AppHandle<R>) -> Result<serde_json::Value, String> {
    call(&app, "status", serde_json::json!({}))
}
#[tauri::command]
async fn start<R: Runtime>(app: tauri::AppHandle<R>, data: serde_json::Value) -> Result<serde_json::Value, String> {
    call(&app, "start", data)
}
#[tauri::command]
async fn end<R: Runtime>(app: tauri::AppHandle<R>) -> Result<serde_json::Value, String> {
    call(&app, "end", serde_json::json!({}))
}
pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("live-activity")
        .invoke_handler(tauri::generate_handler![status, start, end])
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            _app.manage(Native(_api.register_ios_plugin(init_plugin_live_activity)?));
            Ok(())
        }).build()
}
