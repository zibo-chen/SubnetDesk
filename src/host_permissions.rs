//! Passive incoming-control checks. Prompts run only after a local user action.
use hbb_common::ResultType;

pub(crate) fn ready() -> bool {
    #[cfg(target_os = "macos")]
    return crate::platform::macos::is_can_screen_recording(false)
        && crate::platform::macos::is_process_trusted(false);

    #[cfg(target_os = "windows")]
    return crate::platform::is_root()
        || crate::portable_service::client::running()
        || match crate::platform::is_elevated(None) {
            Ok(elevated) => elevated,
            Err(err) => {
                hbb_common::log::warn!("Cannot check administrator access: {err}");
                false
            }
        };

    #[cfg(target_os = "linux")]
    {
        if !crate::platform::linux::current_is_wayland() {
            return true;
        }
        // The portal request holds this mutex while waiting for the user.
        // Passive polling must not block the listener or the settings screen.
        return match scrap::wayland::pipewire::RDP_SESSION_INFO.try_lock() {
            Ok(session) => session.as_ref().is_some_and(|info| !info.streams.is_empty()),
            Err(std::sync::TryLockError::WouldBlock) => false,
            Err(std::sync::TryLockError::Poisoned(err)) => {
                hbb_common::log::error!("Cannot check Wayland authorization: {err}");
                false
            }
        };
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    true
}

/// Runs on the bridge worker pool, including blocking platform permission UI.
pub(crate) fn request() -> ResultType<()> {
    if ready() {
        return Ok(());
    }
    #[cfg(target_os = "macos")]
    {
        crate::platform::macos::is_can_screen_recording(true);
        crate::platform::macos::is_process_trusted(true);
    }
    #[cfg(target_os = "windows")]
    crate::portable_service::client::start_portable_service(
        crate::portable_service::client::StartPara::Direct,
    )?;
    #[cfg(target_os = "linux")]
    if crate::platform::linux::current_is_wayland() {
        // The existing portal path requests screen selection and input consent.
        // Keep its live session; a stored restore token alone is not permission.
        let displays = scrap::Display::all()?;
        if displays.is_empty() || !ready() {
            hbb_common::bail!("Screen sharing and input control were not authorized");
        }
    }
    Ok(())
}
