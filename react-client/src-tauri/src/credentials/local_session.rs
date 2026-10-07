use std::{fs, io::Write, path::{Path, PathBuf}, os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt}, sync::Mutex, time::{SystemTime, UNIX_EPOCH}};
use tauri::Manager;

static LOCK: Mutex<()> = Mutex::new(());

pub fn directory(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app.path().app_data_dir().map_err(|_| "无法读取应用目录")?.join("sessions"))
}

fn prepare(dir: &Path) -> Result<(), String> {
    match fs::symlink_metadata(dir) {
        Ok(meta) if !meta.is_dir() || meta.file_type().is_symlink() => return Err("登录目录无效".into()),
        Ok(_) => {},
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            fs::DirBuilder::new().recursive(true).mode(0o700).create(dir).map_err(|_| "无法创建登录目录")?;
        },
        Err(_) => return Err("无法读取登录目录".into()),
    }
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|_| "无法保护登录目录".into())
}

fn path(dir: &Path, key: &str) -> Result<PathBuf, String> {
    if key.is_empty() || key.len() > 100 || key.contains('\0') { return Err("凭据标识无效".into()); }
    let name: String = key.as_bytes().iter().map(|byte| format!("{byte:02x}")).collect();
    Ok(dir.join(format!("{name}.json")))
}

pub fn read(dir: &Path, key: &str) -> Result<Option<String>, String> {
    let _guard = LOCK.lock().map_err(|_| "登录信息正在使用")?;
    prepare(dir)?;
    let file = path(dir, key)?;
    match fs::symlink_metadata(&file) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Ok(meta) if meta.is_file() && !meta.file_type().is_symlink() && meta.len() <= 2560 => {},
        _ => return Err("本机登录文件无效".into()),
    }
    fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).map_err(|_| "无法保护登录信息")?;
    fs::read_to_string(file).map(Some).map_err(|_| "无法读取本机登录信息".into())
}

pub fn write(dir: &Path, key: &str, value: &str) -> Result<(), String> {
    let _guard = LOCK.lock().map_err(|_| "登录信息正在使用")?;
    if value.len() > 2560 { return Err("凭据内容过大".into()); }
    prepare(dir)?;
    let target = path(dir, key)?;
    let nonce = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "系统时间无效")?.as_nanos();
    let temporary = dir.join(format!(".session-{}-{nonce}.tmp", std::process::id()));
    let result = (|| {
        let mut file = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).map_err(|_| "无法保存本机登录信息")?;
        file.write_all(value.as_bytes()).and_then(|_| file.sync_all()).map_err(|_| "无法完成登录信息写入")?;
        fs::rename(&temporary, target).map_err(|_| "无法替换本机登录信息")?;
        Ok(())
    })();
    if result.is_err() { let _ = fs::remove_file(&temporary); }
    result
}

pub fn delete(dir: &Path, key: &str) -> Result<(), String> {
    let _guard = LOCK.lock().map_err(|_| "登录信息正在使用")?;
    prepare(dir)?;
    match fs::remove_file(path(dir, key)?) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err("无法清除本机登录信息".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Scratch(PathBuf);
    impl Scratch {
        fn new() -> Self {
            Self(std::env::temp_dir().join(format!("flowday-session-test-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos())))
        }
    }
    impl Drop for Scratch { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }

    #[test]
    fn session_survives_reopen_with_private_permissions_and_can_be_removed() {
        let scratch = Scratch::new();
        let dir = &scratch.0;
        assert_eq!(read(dir, "session").unwrap(), None);
        write(dir, "session", "test-session").unwrap();
        assert_eq!(read(dir, "session").unwrap().as_deref(), Some("test-session"));
        assert_eq!(fs::metadata(dir).unwrap().permissions().mode() & 0o777, 0o700);
        assert_eq!(fs::metadata(path(dir, "session").unwrap()).unwrap().permissions().mode() & 0o777, 0o600);
        write(dir, "session", "replacement-session").unwrap();
        assert_eq!(read(dir, "session").unwrap().as_deref(), Some("replacement-session"));
        assert_eq!(fs::read_dir(dir).unwrap().count(), 1);
        delete(dir, "session").unwrap();
        delete(dir, "session").unwrap();
        assert_eq!(read(dir, "session").unwrap(), None);
    }

    #[test]
    fn refuses_symlink_directory_or_file_and_oversized_credentials() {
        let scratch = Scratch::new();
        prepare(&scratch.0).unwrap();
        let other = Scratch::new();
        prepare(&other.0).unwrap();
        let link = scratch.0.join("link");
        std::os::unix::fs::symlink(&other.0, &link).unwrap();
        assert!(write(&link, "session", "test").is_err());
        let token_file = path(&scratch.0, "session").unwrap();
        std::os::unix::fs::symlink(other.0.join("missing"), token_file).unwrap();
        assert!(read(&scratch.0, "session").is_err());
        assert!(write(&scratch.0, "session", &"x".repeat(2561)).is_err());
    }
}
