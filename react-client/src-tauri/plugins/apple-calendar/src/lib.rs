use tauri::{plugin::{Builder, TauriPlugin}, Runtime};
#[cfg(target_os = "ios")]
use tauri::Manager;
#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_apple_calendar);
#[cfg(target_os = "ios")]
struct Native<R: Runtime>(tauri::plugin::PluginHandle<R>);
#[cfg(target_os = "macos")]
mod macos {
    use std::ffi::{c_char, c_void, CStr, CString};
    use tokio::sync::oneshot;
    extern "C" { fn flow_calendar_run(raw: *const c_char, callback: extern "C" fn(*const c_char, *mut c_void), context: *mut c_void); }
    extern "C" fn receive(raw: *const c_char, context: *mut c_void) {
        let sender = unsafe { Box::from_raw(context as *mut oneshot::Sender<String>) };
        let value = unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned();
        let _ = sender.send(value);
    }
    pub async fn request(data: serde_json::Value) -> Result<serde_json::Value, String> {
        let raw = CString::new(data.to_string()).map_err(|_| "日历参数无效")?;
        let (sender, receiver) = oneshot::channel::<String>();
        unsafe { flow_calendar_run(raw.as_ptr(), receive, Box::into_raw(Box::new(sender)) as *mut c_void); }
        let response = receiver.await.map_err(|_| "日历请求已中断")?;
        serde_json::from_str(&response).map_err(|_| "日历返回无效数据".into())
    }
}
#[tauri::command]
async fn request<R: Runtime>(_app: tauri::AppHandle<R>, data: serde_json::Value) -> Result<serde_json::Value, String> {
    #[cfg(target_os = "macos")]
    let result = macos::request(data).await?;
    #[cfg(target_os = "ios")]
    let result: serde_json::Value = _app.state::<Native<R>>().0.run_mobile_plugin("request", serde_json::json!({"json": data.to_string()})).map_err(|e| e.to_string())?;
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    let result = { let _ = data; serde_json::json!({"supported": false}) };
    if let Some(error) = result.get("error").and_then(|v| v.as_str()) { return Err(error.into()); }
    Ok(result)
}
pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("apple-calendar").invoke_handler(tauri::generate_handler![request])
        .setup(|_app, _api| {
            #[cfg(target_os = "ios")]
            _app.manage(Native(_api.register_ios_plugin(init_plugin_apple_calendar)?));
            Ok(())
        }).build()
}
