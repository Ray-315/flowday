use std::{
    collections::hash_map::DefaultHasher,
    ffi::OsStr,
    hash::{Hash, Hasher},
    io,
};
use windows_sys::Win32::{
    Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HANDLE},
    System::Threading::CreateMutexW,
};

pub struct InstanceGuard(HANDLE);

impl Drop for InstanceGuard {
    fn drop(&mut self) {
        unsafe {
            CloseHandle(self.0);
        }
    }
}

fn mutex_name(profile: Option<&OsStr>, test_directory: Option<&OsStr>) -> String {
    let fingerprint = |value: Option<&OsStr>| {
        let mut hash = DefaultHasher::new();
        value
            .map(|v| v.to_string_lossy().replace('/', "\\").to_lowercase())
            .hash(&mut hash);
        hash.finish()
    };
    let mut name = format!("Global\\FlowDay.React.{:016x}", fingerprint(profile));
    if test_directory.is_some() {
        name.push_str(&format!(".Test.{:016x}", fingerprint(test_directory)));
    }
    name
}

pub fn acquire() -> io::Result<Option<InstanceGuard>> {
    acquire_named(&mutex_name(
        std::env::var_os("USERPROFILE").as_deref(),
        std::env::var_os("FLOWDAY_TEST_DATA_DIR").as_deref(),
    ))
}

fn acquire_named(name: &str) -> io::Result<Option<InstanceGuard>> {
    let name: Vec<u16> = name.encode_utf16().chain(Some(0)).collect();
    // Keeping the handle open reserves the name without thread ownership.
    let handle = unsafe { CreateMutexW(std::ptr::null(), 0, name.as_ptr()) };
    if handle.is_null() {
        return Err(io::Error::last_os_error());
    }
    let guard = InstanceGuard(handle);
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        drop(guard);
        return Ok(None);
    }
    Ok(Some(guard))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_instance_is_rejected_until_the_guard_is_dropped() {
        let name = format!(
            "Local\\FlowDay.React.UnitTest.{}.{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let first = acquire_named(&name).unwrap().expect("first instance");
        assert!(acquire_named(&name).unwrap().is_none());
        drop(first);
        assert!(acquire_named(&name).unwrap().is_some());
    }

    #[test]
    fn test_directories_and_windows_users_have_separate_names() {
        let user = Some(OsStr::new("C:\\Users\\UnitTest"));
        let production = mutex_name(user, None);
        let first = mutex_name(user, Some(OsStr::new("D:\\UnitTest\\one")));
        assert_ne!(production, first);
        assert_ne!(
            first,
            mutex_name(user, Some(OsStr::new("D:\\UnitTest\\two")))
        );
        assert_ne!(
            production,
            mutex_name(Some(OsStr::new("C:\\Users\\OtherTest")), None)
        );
        assert_eq!(first, mutex_name(user, Some(OsStr::new("d:/unittest/ONE"))));
    }
}
