#[cfg(windows)]
mod platform {
    use windows_sys::Win32::{Foundation::{GetLastError, ERROR_NOT_FOUND}, Security::Credentials::*};
    fn target(key: &str) -> Result<Vec<u16>, String> {
        if key.len() > 200 || key.contains('\0') { return Err("凭据标识无效".into()); }
        Ok(format!("FlowDay.React/{key}").encode_utf16().chain(Some(0)).collect())
    }
    pub fn read(key: &str) -> Result<Option<String>, String> {
        let name = target(key)?;
        let mut pointer: *mut CREDENTIALW = std::ptr::null_mut();
        unsafe {
            if CredReadW(name.as_ptr(), CRED_TYPE_GENERIC, 0, &mut pointer) == 0 {
                return if GetLastError() == ERROR_NOT_FOUND { Ok(None) } else { Err("无法读取系统凭据".into()) };
            }
            let credential = &*pointer;
            let bytes = if credential.CredentialBlobSize == 0 { Vec::new() } else { std::slice::from_raw_parts(credential.CredentialBlob, credential.CredentialBlobSize as usize).to_vec() };
            CredFree(pointer.cast());
            String::from_utf8(bytes).map(Some).map_err(|_| "系统凭据格式无效".into())
        }
    }
    pub fn write(key: &str, value: &str) -> Result<(), String> {
        if value.len() > 2560 { return Err("凭据内容过大".into()); }
        let mut name = target(key)?;
        let mut blob = value.as_bytes().to_vec();
        let credential = CREDENTIALW {
            Type: CRED_TYPE_GENERIC, TargetName: name.as_mut_ptr(),
            CredentialBlobSize: blob.len() as u32, CredentialBlob: blob.as_mut_ptr(),
            Persist: CRED_PERSIST_LOCAL_MACHINE, ..unsafe { std::mem::zeroed() }
        };
        if unsafe { CredWriteW(&credential, 0) } == 0 { Err("无法保存系统凭据".into()) } else { Ok(()) }
    }
    pub fn delete(key: &str) -> Result<(), String> {
        let name = target(key)?;
        if unsafe { CredDeleteW(name.as_ptr(), CRED_TYPE_GENERIC, 0) } == 0 && unsafe { GetLastError() } != ERROR_NOT_FOUND { Err("无法删除系统凭据".into()) } else { Ok(()) }
    }
}
#[cfg(target_os = "macos")]
mod local_session;
#[tauri::command]
pub fn credential_read(app: tauri::AppHandle, key: String) -> Result<Option<String>, String> {
    if std::env::var_os("FLOWDAY_TEST_DATA_DIR").is_some() { return Ok(None); }
    #[cfg(windows)] { let _ = app; platform::read(&key) }
    #[cfg(target_os = "macos")] { local_session::read(&local_session::directory(&app)?, &key) }
    #[cfg(not(any(windows, target_os = "macos")))] { let _ = (app,key); Ok(None) }
}
#[tauri::command]
pub fn credential_write(app: tauri::AppHandle, key: String, value: String) -> Result<(), String> {
    if std::env::var_os("FLOWDAY_TEST_DATA_DIR").is_some() { return Ok(()); }
    #[cfg(windows)] { let _ = app; platform::write(&key, &value) }
    #[cfg(target_os = "macos")] { local_session::write(&local_session::directory(&app)?, &key, &value) }
    #[cfg(not(any(windows, target_os = "macos")))] { let _ = (app,key,value); Err("当前平台尚未配置安全凭据存储".into()) }
}
#[tauri::command]
pub fn credential_delete(app: tauri::AppHandle, key: String) -> Result<(), String> {
    if std::env::var_os("FLOWDAY_TEST_DATA_DIR").is_some() { return Ok(()); }
    #[cfg(windows)] { let _ = app; platform::delete(&key) }
    #[cfg(target_os = "macos")] { local_session::delete(&local_session::directory(&app)?, &key) }
    #[cfg(not(any(windows, target_os = "macos")))] { let _ = (app,key); Ok(()) }
}

#[cfg(all(test, windows))]
mod tests {
    #[test]
    fn system_credential_round_trip_is_isolated_and_removed() {
        let key=format!("test-{}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos());
        super::platform::write(&key,"temporary-test-value").unwrap();
        struct Cleanup(String);
        impl Drop for Cleanup { fn drop(&mut self) { let _ = super::platform::delete(&self.0); } }
        let _cleanup = Cleanup(key.clone());
        assert_eq!(super::platform::read(&key).unwrap().as_deref(), Some("temporary-test-value"));
        super::platform::write(&key,"updated-test-value").unwrap();
        let value=super::platform::read(&key);
        super::platform::delete(&key).unwrap();
        assert_eq!(value.unwrap().as_deref(),Some("updated-test-value"));
        assert!(super::platform::read(&key).unwrap().is_none());
        super::platform::delete(&key).unwrap();
    }
}
