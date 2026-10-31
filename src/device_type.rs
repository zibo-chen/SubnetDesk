//! Cosmetic hardware metadata. Unknown hardware falls back to a desktop;
//! running in a service or without DISPLAY does not make a machine a server.

use hbb_common::log;

pub(crate) fn normalize(value: &str) -> &'static str {
    match value {
        "phone" => "phone",
        "tablet" => "tablet",
        "laptop" => "laptop",
        "desktop" => "desktop",
        "all-in-one" => "all-in-one",
        "server" => "server",
        _ => "",
    }
}

pub(crate) fn local() -> &'static str {
    lazy_static::lazy_static! {
        static ref DETECTED: &'static str = detect();
    }
    *DETECTED
}

// SMBIOS Type 3, Chassis Type. Bit 7 is the chassis-lock flag.
// https://learn.microsoft.com/windows/win32/cimwin32prov/win32-systemenclosure
#[cfg(any(target_os = "windows", target_os = "linux", test))]
fn from_chassis(value: u8) -> Option<&'static str> {
    match value & 0x7f {
        8..=10 | 14 => Some("laptop"),
        11 => Some("phone"),
        30..=32 => Some("tablet"),
        17 | 23 | 28 | 29 => Some("server"),
        13 => Some("all-in-one"),
        3..=7 | 15 | 16 | 24 | 35 | 36 => Some("desktop"),
        _ => None,
    }
}

#[cfg(any(target_os = "macos", target_os = "android"))]
fn command_output(program: &str, args: &[&str]) -> String {
    match std::process::Command::new(program).args(args).output() {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).trim().to_owned()
        }
        Ok(output) => {
            log::debug!("Device type probe {program} exited with {}", output.status);
            String::new()
        }
        Err(err) => {
            log::debug!("Device type probe {program} unavailable: {err}");
            String::new()
        }
    }
}

#[cfg(target_os = "macos")]
fn detect() -> &'static str {
    let model = command_output("/usr/sbin/sysctl", &["-n", "hw.model"]).to_lowercase();
    // Apple Silicon model identifiers do not always contain "MacBook".
    let battery = command_output("/usr/sbin/ioreg", &["-r", "-c", "AppleSmartBattery"]);
    if model.contains("macbook") || battery.contains("AppleSmartBattery") {
        "laptop"
    } else if model.contains("imac") {
        "all-in-one"
    } else {
        "desktop"
    }
}

#[cfg(target_os = "linux")]
fn detect() -> &'static str {
    let chassis = match std::fs::read_to_string("/sys/class/dmi/id/chassis_type") {
        Ok(value) => value.trim().parse::<u8>().ok().and_then(from_chassis),
        Err(err) => {
            log::debug!("DMI chassis type unavailable: {err}");
            None
        }
    };
    if let Some(kind @ ("laptop" | "tablet" | "phone" | "server" | "all-in-one")) = chassis {
        return kind;
    }
    // This also covers ARM machines and VMs without DMI data. Only an explicit
    // server distribution is evidence; an unset desktop session is not.
    match std::fs::read_to_string("/etc/os-release") {
        Ok(value)
            if value.lines().any(|line| {
                (line.starts_with("VARIANT=")
                    || line.starts_with("VARIANT_ID=")
                    || line.starts_with("PRETTY_NAME="))
                    && line.to_ascii_lowercase().contains("server")
            }) =>
        {
            return "server"
        }
        Err(err) => log::debug!("OS variant unavailable: {err}"),
        _ => {}
    }
    for path in [
        "/etc/systemd/system/default.target",
        "/usr/lib/systemd/system/default.target",
    ] {
        match std::fs::read_link(path) {
            Ok(target) => {
                return if target.ends_with("multi-user.target") {
                    "server"
                } else {
                    "desktop"
                }
            }
            Err(err) => log::debug!("Default system target unavailable at {path}: {err}"),
        }
    }
    chassis.unwrap_or("desktop")
}

#[cfg(target_os = "windows")]
fn detect() -> &'static str {
    #[link(name = "kernel32")]
    extern "system" {
        fn GetSystemFirmwareTable(provider: u32, id: u32, buffer: *mut u8, size: u32) -> u32;
    }
    // Read the raw SMBIOS table using the API available since Windows XP SP3.
    let provider = u32::from_be_bytes(*b"RSMB");
    let size = unsafe { GetSystemFirmwareTable(provider, 0, std::ptr::null_mut(), 0) };
    if !(8..=1_048_576).contains(&size) {
        log::debug!(
            "SMBIOS size unavailable: {}",
            std::io::Error::last_os_error()
        );
        return "desktop";
    }
    let mut data = vec![0; size as usize];
    let written = unsafe { GetSystemFirmwareTable(provider, 0, data.as_mut_ptr(), size) };
    if written < 8 || written > size {
        log::debug!(
            "SMBIOS read unavailable: {}",
            std::io::Error::last_os_error()
        );
        return "desktop";
    }
    smbios_chassis(&data[8..written as usize])
        .and_then(from_chassis)
        .unwrap_or("desktop")
}

#[cfg(any(target_os = "windows", test))]
fn smbios_chassis(mut data: &[u8]) -> Option<u8> {
    while data.len() >= 4 {
        let len = data[1] as usize;
        if len < 4 || len > data.len() {
            return None;
        }
        if data[0] == 3 && len > 5 {
            return Some(data[5]);
        }
        if data[0] == 127 {
            return None;
        }
        let strings_end = data[len..].windows(2).position(|pair| pair == [0, 0])?;
        data = &data[len + strings_end + 2..];
    }
    None
}

#[cfg(target_os = "android")]
fn detect() -> &'static str {
    let characteristics = command_output("/system/bin/getprop", &["ro.build.characteristics"]);
    if characteristics
        .split(',')
        .any(|value| value.trim() == "tablet")
    {
        "tablet"
    } else {
        "phone"
    }
}

#[cfg(target_os = "ios")]
fn detect() -> &'static str {
    if crate::hostname().to_ascii_lowercase().starts_with("ipad") {
        "tablet"
    } else {
        "phone"
    }
}

#[cfg(not(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "linux",
    target_os = "android",
    target_os = "ios"
)))]
fn detect() -> &'static str {
    "desktop"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chassis_distinguishes_linux_desktops_servers_and_mobile_hardware() {
        assert_eq!(from_chassis(3), Some("desktop"));
        assert_eq!(from_chassis(9 | 0x80), Some("laptop"));
        assert_eq!(from_chassis(13), Some("all-in-one"));
        assert_eq!(from_chassis(23), Some("server"));
        assert_eq!(from_chassis(30), Some("tablet"));
        assert_eq!(from_chassis(1), None);
    }

    #[test]
    fn smbios_skips_strings_and_rejects_truncated_tables() {
        let table = [1, 4, 0, 0, b'a', 0, 0, 3, 6, 0, 0, 0, 9, 0, 0];
        assert_eq!(smbios_chassis(&table), Some(9));
        for table in [
            &[][..],
            &[3, 6, 0, 0, 0][..],
            &[1, 0, 0, 0][..],
            &[1, 4, 0, 0, b'a'][..],
        ] {
            assert_eq!(smbios_chassis(table), None);
        }
    }

    #[test]
    fn unknown_wire_values_do_not_become_asset_paths() {
        assert_eq!(normalize("server"), "server");
        assert_eq!(normalize("../../asset"), "");
        assert_eq!(normalize("future-device"), "");
    }
}
