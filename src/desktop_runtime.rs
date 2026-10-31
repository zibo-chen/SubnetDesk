//! The interactive application owns the host runtime. No OS service is required.
#[cfg(windows)]
use hbb_common::anyhow::anyhow;
use hbb_common::{
    anyhow::Context,
    config::{Config, LocalConfig},
    log, ResultType,
};
#[cfg(windows)]
use std::process::Command;
use std::{
    fs,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};

static HOST: AtomicBool = AtomicBool::new(false);
static STOPPING: AtomicBool = AtomicBool::new(false);
static AUTOSTART_OPERATION: Mutex<()> = Mutex::new(());
static AUTOSTART_ERROR: Mutex<String> = Mutex::new(String::new());

pub fn is_host() -> bool {
    HOST.load(Ordering::Acquire)
}
pub fn is_stopping() -> bool {
    STOPPING.load(Ordering::Acquire)
}

pub fn claim() -> ResultType<bool> {
    #[cfg(unix)]
    {
        use std::os::fd::AsRawFd;
        static LOCK: Mutex<Option<fs::File>> = Mutex::new(None);
        let paths = hbb_common::app_paths::get().context("Desktop paths are not initialized")?;
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(paths.cache().join("runtime.lock"))?;
        if unsafe {
            hbb_common::libc::flock(
                file.as_raw_fd(),
                hbb_common::libc::LOCK_EX | hbb_common::libc::LOCK_NB,
            )
        } != 0
        {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::WouldBlock {
                return Ok(false);
            }
            return Err(err.into());
        }
        *LOCK.lock().unwrap() = Some(file);
    }
    #[cfg(windows)]
    {
        use winapi::um::{errhandlingapi::GetLastError, synchapi::CreateMutexW};
        let name = crate::platform::wide_string("Local\\SubnetDesk-InteractiveRuntime");
        let handle = unsafe { CreateMutexW(std::ptr::null_mut(), 0, name.as_ptr()) };
        if handle.is_null() {
            return Err(std::io::Error::last_os_error().into());
        }
        if unsafe { GetLastError() } == winapi::shared::winerror::ERROR_ALREADY_EXISTS {
            unsafe {
                winapi::um::handleapi::CloseHandle(handle);
            }
            return Ok(false);
        }
    }
    HOST.store(true, Ordering::Release);
    Ok(true)
}

pub fn shutdown() {
    if !is_host() || STOPPING.swap(true, Ordering::AcqRel) {
        return;
    }
    crate::lan_server::LanServer::restart();
    crate::server::input_service::fix_key_down_timeout_at_exit();
    #[cfg(windows)]
    crate::portable_service::client::drop_portable_service_shared_memory();
    for child in crate::server::CHILD_PROCESS.lock().unwrap().iter_mut() {
        match child.try_wait() {
            Ok(None) => {
                if let Err(err) = child.kill() {
                    log::warn!("Failed to stop child: {err}");
                }
            }
            Ok(Some(_)) => {}
            Err(err) => log::warn!("Failed to inspect child: {err}"),
        }
    }
}

pub fn state() -> String {
    let paths = hbb_common::app_paths::get();
    serde_json::json!({
        "resident": is_host(),
        "configured": Config::lan_credentials_configured(),
        "listening": crate::lan_server::LanServer::is_running(),
        "portable": paths.is_some_and(|paths| paths.portable),
        "data_dir": paths.map(|paths| paths.root.to_string_lossy().into_owned()).unwrap_or_default(),
        "autostart": autostart_path().and_then(|path| Ok(fs::read_to_string(path)?))
            .and_then(|actual| Ok(actual.trim_end() == autostart_contents(&launch_arguments()?, &startup_user()?).trim_end()))
            .unwrap_or(false),
        "error": AUTOSTART_ERROR.lock().unwrap().clone(),
    }).to_string()
}

fn xml(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn autostart_path() -> ResultType<PathBuf> {
    #[cfg(target_os = "macos")]
    return Ok(Config::get_home().join("Library/LaunchAgents/com.zibochen.subnetdesk.login.plist"));
    #[cfg(target_os = "linux")]
    return Ok(Config::get_home().join(".config/autostart/subnetdesk.desktop"));
    #[cfg(windows)]
    return Ok(hbb_common::app_paths::get()
        .context("Desktop paths are not initialized")?
        .config()
        .join("autostart.xml"));
}

fn launch_arguments() -> ResultType<Vec<String>> {
    let exe = std::env::current_exe()?;
    let paths = hbb_common::app_paths::get().context("Desktop paths are not initialized")?;
    Ok(vec![
        exe.to_string_lossy().into_owned(),
        "--background".into(),
        format!("--data-dir={}", paths.root.display()),
    ])
}

#[cfg(target_os = "macos")]
fn autostart_contents(args: &[String], _user: &str) -> String {
    let arguments = args
        .iter()
        .map(|arg| format!("<string>{}</string>", xml(arg)))
        .collect::<String>();
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.zibochen.subnetdesk.login</string>
<key>ProgramArguments</key><array>{arguments}</array>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
"#
    )
}

#[cfg(target_os = "linux")]
fn autostart_contents(args: &[String], _user: &str) -> String {
    let arguments = args
        .iter()
        .map(|arg| {
            format!(
                "\"{}\"",
                arg.replace('\\', "\\\\")
                    .replace('"', "\\\"")
                    .replace('`', "\\`")
                    .replace('$', "\\$")
                    .replace('%', "%%")
            )
        })
        .collect::<Vec<_>>()
        .join(" ");
    format!("[Desktop Entry]\nType=Application\nName=SubnetDesk\nExec={arguments}\nTerminal=false\nX-GNOME-Autostart-enabled=true\n")
}

fn startup_user() -> ResultType<String> {
    #[cfg(windows)]
    return crate::platform::windows::current_process_user_sid_string();
    #[cfg(not(windows))]
    Ok(String::new())
}

#[cfg(windows)]
fn autostart_contents(args: &[String], user: &str) -> String {
    let arguments = args[1..]
        .iter()
        .map(|arg| format!("\"{}\"", arg))
        .collect::<Vec<_>>()
        .join(" ");
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers><LogonTrigger><Enabled>true</Enabled><UserId>{user}</UserId></LogonTrigger></Triggers>
<Principals><Principal id="User"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></Settings>
<Actions Context="User"><Exec><Command>{exe}</Command><Arguments>{arguments}</Arguments><WorkingDirectory>{directory}</WorkingDirectory></Exec></Actions></Task>
"#,
        user = xml(user),
        exe = xml(&args[0]),
        arguments = xml(&arguments),
        directory = xml(&std::path::Path::new(&args[0])
            .parent()
            .unwrap_or_else(|| std::path::Path::new(""))
            .to_string_lossy()),
    )
}

pub fn set_autostart(enabled: bool) {
    let _operation = AUTOSTART_OPERATION.lock().unwrap();
    let result = configure_autostart(enabled);
    *AUTOSTART_ERROR.lock().unwrap() = match result {
        Ok(()) => {
            LocalConfig::set_option(
                "start-on-boot".into(),
                if enabled { "Y" } else { "N" }.into(),
            );
            String::new()
        }
        Err(err) => {
            log::error!("Failed to configure login startup: {err:#}");
            format!("{err:#}")
        }
    };
}

fn configure_autostart(enabled: bool) -> ResultType<()> {
    let path = autostart_path()?;
    if enabled {
        let arguments = launch_arguments()?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let user = startup_user()?;
        let pending = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4().simple()));
        let result = (|| -> ResultType<()> {
            fs::write(&pending, autostart_contents(&arguments, &user))?;
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                let task = format!("SubnetDesk Login {user}");
                let output = Command::new("schtasks.exe")
                    .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
                    .args(["/Create", "/TN", &task, "/XML"])
                    .arg(&pending)
                    .arg("/F")
                    .output()?;
                if !output.status.success() {
                    return Err(anyhow!(
                        "Task Scheduler: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }
            }
            fs::rename(&pending, &path)?;
            Ok(())
        })();
        if result.is_err() {
            match fs::remove_file(&pending) {
                Ok(()) => {}
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
                Err(err) => log::warn!("Cannot remove failed startup configuration: {err}"),
            }
        }
        result?;
    } else {
        #[cfg(windows)]
        if path.exists() {
            use std::os::windows::process::CommandExt;
            let task = format!("SubnetDesk Login {}", startup_user()?);
            let output = Command::new("schtasks.exe")
                .creation_flags(winapi::um::winbase::CREATE_NO_WINDOW)
                .args(["/Delete", "/TN", &task, "/F"])
                .output()?;
            if !output.status.success() {
                return Err(anyhow!(
                    "Task Scheduler: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
        }
        match fs::remove_file(&path) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => return Err(err.into()),
        }
    }
    Ok(())
}

#[no_mangle]
pub extern "C" fn subnetdesk_shutdown() {
    shutdown();
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn startup_escapes_paths_without_a_shell_or_service() {
        let args = vec![
            "/tmp/A & B/SubnetDesk.app/Contents/MacOS/SubnetDesk".into(),
            "--background".into(),
            "--data-dir=/tmp/A & B/userdata".into(),
        ];
        let contents = autostart_contents(&args, "S-1-5-21-test");
        assert!(contents.contains("--background"));
        #[cfg(target_os = "macos")]
        {
            assert!(contents.contains("A &amp; B"));
            assert!(!contents.contains("KeepAlive"));
            assert!(!contents.contains("LaunchDaemons"));
        }
    }
}
