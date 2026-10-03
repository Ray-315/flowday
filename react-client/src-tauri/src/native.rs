use std::{fs, io::Write, path::{Path, PathBuf}, sync::Mutex, time::{Duration, SystemTime, UNIX_EPOCH}};
use tauri::Manager;
use base64::Engine;

pub struct FileLock(pub Mutex<()>);

#[tauri::command]
pub fn sync_baseline_read(app:tauri::AppHandle,scope:String,lock:tauri::State<FileLock>)->Result<Option<String>,String>{
    let _guard=lock.0.lock().map_err(|_|"数据文件正在使用")?;
    match fs::read_to_string(directory(&app,&scope)?.join("sync-baseline.json")) {
        Ok(source)=>Ok(Some(source)),
        Err(error) if error.kind()==std::io::ErrorKind::NotFound=>Ok(None),
        Err(_)=>Err("无法读取同步记录".into())
    }
}
#[tauri::command]
pub fn sync_baseline_write(app:tauri::AppHandle,scope:String,source:String,lock:tauri::State<FileLock>)->Result<(),String>{
    let value:serde_json::Value=serde_json::from_str(&source).map_err(|_|"同步记录格式无效")?;
    if value["version"].as_u64().is_none(){return Err("同步版本无效".into());}
    validate(value["json"].as_str().ok_or("同步数据无效")?)?;
    let _guard=lock.0.lock().map_err(|_|"数据文件正在使用")?;
    atomic_write(&directory(&app,&scope)?.join("sync-baseline.json"),&source)
}

fn directory(app: &tauri::AppHandle, scope: &str) -> Result<PathBuf, String> {
    if scope.is_empty() || scope.len() > 512 { return Err("无效的工作区".into()); }
    let key: String = scope.as_bytes().iter().map(|byte| format!("{byte:02x}")).collect();
    let root = match std::env::var_os("FLOWDAY_TEST_DATA_DIR") {
        Some(path) => PathBuf::from(path),
        None => app.path().app_data_dir().map_err(|_| "无法读取应用目录")?,
    };
    let path = root.join("workspaces").join(key);
    fs::create_dir_all(&path).map_err(|_| "无法创建数据目录")?;
    Ok(path)
}

fn validate(source: &str) -> Result<(), String> {
    if source.len() > 20 * 1024 * 1024 { return Err("工作区数据过大".into()); }
    let data: serde_json::Value = serde_json::from_str(source).map_err(|_| "工作区格式无效")?;
    if data["schemaVersion"] != 1 || ["tasks", "events", "projects", "nodes", "edges", "notices", "captures"].iter().any(|key| !data[key].is_array()) {
        return Err("工作区格式无效".into());
    }
    Ok(())
}

fn atomic_write(path: &Path, source: &str) -> Result<(), String> {
    let temporary = path.with_extension("tmp");
    let mut file = fs::File::create(&temporary).map_err(|_| "无法写入数据文件")?;
    file.write_all(source.as_bytes()).and_then(|_| file.sync_all()).map_err(|_| "无法完成数据写入")?;
    fs::rename(&temporary, path).map_err(|_| "无法替换数据文件".into())
}

#[tauri::command]
pub fn workspace_read(app: tauri::AppHandle, scope: String, lock: tauri::State<FileLock>) -> Result<Option<String>, String> {
    let _guard = lock.0.lock().map_err(|_| "数据文件正在使用")?;
    let path = directory(&app, &scope)?.join("workspace.json");
    match fs::read_to_string(path) {
        Ok(source) => Ok(Some(source)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err("无法读取数据文件".into()),
    }
}

#[tauri::command]
pub fn workspace_write(app: tauri::AppHandle, scope: String, source: String, lock: tauri::State<FileLock>) -> Result<(), String> {
    validate(&source)?;
    let _guard = lock.0.lock().map_err(|_| "数据文件正在使用")?;
    let dir = directory(&app, &scope)?;
    let path = dir.join("workspace.json");
    if let Ok(previous) = fs::read_to_string(&path) {
        if validate(&previous).is_ok() {
            atomic_write(&dir.join("previous.json"), &previous)?;
            let day = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "系统时间无效")?.as_secs() / 86400;
            let backup = dir.join(format!("daily-{day}.json"));
            if !backup.exists() { atomic_write(&backup, &previous)?; }
        }
    }
    atomic_write(&path, &source)
}

#[derive(serde::Serialize)]
#[serde(rename_all="camelCase")]
pub struct Backup { id:String, modified_at:u64, size:u64 }
fn backup_name(id:&str)->bool { id=="previous.json" || ((id.starts_with("daily-")||id.starts_with("manual-"))&&id.ends_with(".json")&&id.split('-').nth(1).and_then(|v|v.strip_suffix(".json")).and_then(|v|v.parse::<u64>().ok()).is_some()) }
#[tauri::command]
pub fn workspace_backups(app:tauri::AppHandle,scope:String)->Result<Vec<Backup>,String>{
    let dir=directory(&app,&scope)?;let mut result=Vec::new();
    for entry in fs::read_dir(dir).map_err(|_|"无法读取备份")?.flatten(){
        let id=entry.file_name().to_string_lossy().into_owned();
        if !backup_name(&id){continue;}
        let meta=entry.metadata().map_err(|_|"无法读取备份信息")?;
        let modified_at=meta.modified().unwrap_or(UNIX_EPOCH).duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
        result.push(Backup{id,modified_at,size:meta.len()});
    }
    result.sort_by(|a,b|b.modified_at.cmp(&a.modified_at));Ok(result)
}
#[tauri::command]
pub fn workspace_backup(app:tauri::AppHandle,scope:String,lock:tauri::State<FileLock>)->Result<(),String>{
    let _guard=lock.0.lock().map_err(|_|"数据文件正在使用")?;
    let dir=directory(&app,&scope)?;
    let source=fs::read_to_string(dir.join("workspace.json")).map_err(|_|"工作区尚未保存")?;
    validate(&source)?;
    let now=SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_|"系统时间无效")?.as_millis();
    atomic_write(&dir.join(format!("manual-{now}.json")),&source)
}
#[tauri::command]
pub fn workspace_backup_read(app:tauri::AppHandle,scope:String,id:String)->Result<String,String>{
    if !backup_name(&id){return Err("备份标识无效".into());}
    fs::read_to_string(directory(&app,&scope)?.join(id)).map_err(|_|"无法读取备份".into())
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HttpResult { status: u16, body: String, content_base64: Option<String>, content_type: String }

fn request_url(base: &str, path: &str) -> Result<reqwest::Url, String> {
    let endpoint = reqwest::Url::parse(base).map_err(|_| "服务器地址无效")?;
    let local = matches!(endpoint.host_str(), Some("localhost" | "127.0.0.1" | "[::1]" | "::1"));
    if (endpoint.scheme() != "https" && !(endpoint.scheme() == "http" && local)) || !endpoint.username().is_empty() || endpoint.password().is_some() || endpoint.query().is_some() || endpoint.fragment().is_some() {
        return Err("服务器必须使用 HTTPS".into());
    }
    if !path.starts_with('/') || path.starts_with("//") || path.contains('\\') || path.contains('#') || path.split('/').any(|part| part == "..") {
        return Err("请求地址无效".into());
    }
    let base = base.trim_end_matches('/');
    let prefix = if base.ends_with("/api/v1") { "" } else { "/api/v1" };
    reqwest::Url::parse(&format!("{base}{prefix}{path}")).map_err(|_| "请求地址无效".into())
}

#[tauri::command]
pub async fn http_request(base_url: String, path: String, method: String, token: Option<String>, body: Option<String>) -> Result<HttpResult, String> {
    let url = request_url(&base_url, &path)?;
    let client = reqwest::Client::builder().timeout(Duration::from_secs(18)).redirect(reqwest::redirect::Policy::none()).build().map_err(|_| "无法初始化网络连接")?;
    let method = reqwest::Method::from_bytes(method.as_bytes()).map_err(|_| "请求方式无效")?;
    let mut request = client.request(method, url).header("Accept", "application/json");
    if let Some(token) = token { request = request.bearer_auth(token); }
    if let Some(body) = body {
        if body.len() > 150 * 1024 * 1024 { return Err("请求数据过大".into()); }
        request = request.header("Content-Type", "application/json").body(body);
    }
    let mut response = request.send().await.map_err(|_| "连接失败，请检查网络和服务器地址")?;
    let status = response.status().as_u16();
    let content_type = response.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("").to_owned();
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "响应读取失败")? {
        if bytes.len() + chunk.len() > 150 * 1024 * 1024 { return Err("响应数据过大".into()); }
        bytes.extend_from_slice(&chunk);
    }
    let text = String::from_utf8(bytes.clone()).ok();
    Ok(HttpResult { status, body: text.clone().unwrap_or_default(), content_base64: if text.is_none() { Some(base64::engine::general_purpose::STANDARD.encode(bytes)) } else { None }, content_type })
}

#[tauri::command]
pub async fn http_download(base_url: String, path: String, token: String) -> Result<Vec<u8>, String> {
    let url = request_url(&base_url, &path)?;
    let client = reqwest::Client::builder().timeout(Duration::from_secs(60)).redirect(reqwest::redirect::Policy::none()).build().map_err(|_| "无法初始化网络连接")?;
    let mut response = client.get(url).bearer_auth(token).send().await.map_err(|_| "连接失败")?;
    if !response.status().is_success() { return Err("下载失败，请检查登录状态".into()); }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "下载读取失败")? {
        if bytes.len() + chunk.len() > 150 * 1024 * 1024 { return Err("下载数据过大".into()); }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn requests_require_secure_non_redirected_destinations() {
        assert!(request_url("http://example.com", "/workspace").is_err());
        assert!(request_url("https://flowday.mtrx.pro", "//evil.example").is_err());
        assert_eq!(request_url("http://127.0.0.1:3108/api/v1", "/workspace").unwrap().as_str(), "http://127.0.0.1:3108/api/v1/workspace");
    }
    #[test]
    fn invalid_data_is_rejected_before_write() { assert!(validate("{}").is_err()); }
    #[test]
    fn atomic_replace_can_replace_an_existing_file() {
        let path = std::env::temp_dir().join(format!("flowday-atomic-{}.json", std::process::id()));
        atomic_write(&path, "old").unwrap();
        atomic_write(&path, "new").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), "new");
        fs::remove_file(path).unwrap();
    }
}
