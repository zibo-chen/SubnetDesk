/// Url handler based on dbus
///
/// Note:
/// On linux, we use dbus to communicate between multiple rustdesk processes.
/// [Flutter]: handle uni links for linux
use dbus::blocking::Connection;
#[cfg(target_os = "linux")]
use dbus::blocking::stdintf::org_freedesktop_dbus::Properties;
use dbus_crossroads::{Crossroads, IfaceBuilder};
use hbb_common::log;
#[cfg(feature = "flutter")]
use std::collections::HashMap;
#[cfg(target_os = "linux")]
use std::io::Write;
use std::{error::Error, fmt, time::Duration};

const DBUS_NAME: &str = "org.rustdesk.rustdesk";
const DBUS_PREFIX: &str = "/dbus";
const DBUS_METHOD_NEW_CONNECTION: &str = "NewConnection";
const DBUS_METHOD_NEW_CONNECTION_ID: &str = "id";
const DBUS_METHOD_RETURN: &str = "ret";
const DBUS_METHOD_RETURN_SUCCESS: &str = "ok";
const DBUS_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug)]
struct DbusError(String);

impl fmt::Display for DbusError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "SubnetDesk DBus Error: {}", self.0)
    }
}

impl Error for DbusError {}

/// invoke new connection from dbus
///
/// [Tips]:
/// How to test by CLI:
/// - use dbus-send command:
/// `dbus-send --session --print-reply --dest=org.rustdesk.rustdesk /dbus org.rustdesk.rustdesk.NewConnection string:'PEER_ID'`
pub fn invoke_new_connection(uni_links: String) -> Result<(), Box<dyn Error>> {
    log::info!("Starting dbus service for uni");
    let conn = Connection::new_session()?;
    let proxy = conn.with_proxy(DBUS_NAME, DBUS_PREFIX, DBUS_TIMEOUT);
    let (ret,): (String,) =
        proxy.method_call(DBUS_NAME, DBUS_METHOD_NEW_CONNECTION, (uni_links,))?;
    if ret != DBUS_METHOD_RETURN_SUCCESS {
        log::error!("error on call new connection to dbus server");
        return Err(Box::new(DbusError("not success".to_string())));
    }
    Ok(())
}

/// start dbus server
///
/// [Blocking]:
/// The function will block current thread to serve dbus server.
/// So it's suitable to spawn a new thread dedicated to dbus server.
pub fn start_dbus_server() -> Result<(), Box<dyn Error>> {
    let conn: Connection = Connection::new_session()?;
    let _ = conn.request_name(DBUS_NAME, false, true, false)?;
    let mut cr = Crossroads::new();
    let token = cr.register(DBUS_NAME, handle_client_message);
    cr.insert(DBUS_PREFIX, &[token], ());
    cr.serve(&conn)?;
    Ok(())
}

// TODO(upstream window_manager): `rustdesk-org/window_manager`'s Linux plugin
// raises the main window via a bare `gtk_window_present(get_window(self))`
// (linux/window_manager_plugin.cc), i.e. with no timestamp, so GTK treats it
// as GDK_CURRENT_TIME. Every modern WM's focus-stealing prevention (Mutter,
// KWin) distrusts an activation request with no timestamp tied to a real,
// recent input event -- and there IS no such event here: this handler runs
// on the dbus-crossroads server thread in response to an IPC call from the
// tray process (`tray.rs`'s `open_func` -> `invoke_new_connection`), not from
// a live GTK event, so `gtk_window_present()` gets silently deferred or
// ignored. Observed as: clicking "Open" (or a favorite) in the tray menu
// takes up to ~30s to actually show the window, but immediately succeeds if
// the user right-clicks the tray icon again right after -- that fresh, truly
// timestamped input event is apparently what lets the WM reconcile the
// pending activation. `xdotool windowactivate` sends a proper EWMH
// `_NET_ACTIVE_WINDOW` client message (source_indication=2, "pager"), which
// WMs are specced to honor from an external tool without the same
// timestamp scrutiny -- so it reliably raises the window where the bare
// `gtk_window_present()` call does not.
//
// This is a best-effort workaround, not a proper fix: it shells out to the
// optional `xdotool` CLI (not a hard dependency; failure here is silently
// swallowed and just leaves the pre-existing behavior) and targets "any
// window belonging to this process" rather than a specific window handle.
// Remove this call (and this function) once `window_manager`'s Linux plugin
// calls `gtk_window_present_with_time()` with a real server timestamp
// (e.g. via `gdk_x11_get_server_time()`) instead of `gtk_window_present()`.
//
// Runs on a detached thread and retries for about a second: if the main
// window is currently hidden (e.g. minimized to tray), `xdotool` can only
// activate it once it is actually mapped, and that mapping happens
// asynchronously on the Dart side (windowOnTop() -> windowManager.show())
// in response to the very `on_url_scheme_received` event pushed right after
// this function is called -- so the window may well not exist yet the
// moment we'd otherwise try. A single immediate attempt raced that and
// mostly lost. `run_cmds` only returns captured stdout and swallows the
// child's exit status, so there is no clean way to detect "no window found
// yet" versus "activated" -- retrying a few times is crude but harmless
// (xdotool no-ops instantly when nothing matches) and covers the real
// window-creation latency the single-shot version did not.
// KWin (KDE Plasma's compositor/WM) applies a stricter focus-stealing-
// prevention policy than GNOME/Mutter to an externally-sourced EWMH
// _NET_ACTIVE_WINDOW request -- the same xdotool call below that activates
// a window within ~0.3s under Mutter has been observed (live-tested,
// 2026-09-12) taking several seconds under KWin, until some unrelated fresh
// user input event (e.g. right-clicking the tray again) happens to make
// KWin finally honor the pending request. KWin exposes its own scripting
// D-Bus interface (org.kde.KWin, /Scripting) that can set
// `workspace.activeWindow` directly -- an internal, privileged KWin
// mechanism, not an external activation *request* -- which sidesteps that
// policy entirely. Verified live: the same PID-based lookup activated a
// backgrounded window instantly under KWin 6.7.4 via this path, where
// xdotool alone was unreliable.
//
// Best-effort and KDE-specific: on any other desktop (no org.kde.KWin on
// the session bus) the very first D-Bus call fails immediately and this
// silently falls through, changing nothing. Kept alongside the xdotool
// attempt below (not as a replacement) since that one already works fine
// on GNOME and other WMs.
#[cfg(target_os = "linux")]
fn activate_via_kwin_script(pid: u32) -> Result<(), Box<dyn Error>> {
    let script_path = std::env::temp_dir().join(format!("subnetdesk-kwin-activate-{pid}.js"));
    // `workspace.windowList()` (KWin 5) was renamed to the `workspace.windows`
    // property in KWin 6's scripting API; support either.
    //
    // Setting `activeWindow` alone is not enough: live-tested (2026-09-12),
    // the main window ends up in KWin's window list with `minimized: true`
    // (window_manager's `.show()` on Linux doesn't restore a minimized
    // window itself), and `workspace.activeWindow = win` silently does
    // nothing for a still-minimized window. Explicitly clearing `minimized`
    // first is what actually brings it on screen.
    let script = format!(
        "var wins = (typeof workspace.windowList === 'function') ? workspace.windowList() : workspace.windows;\n\
         for (var i = 0; i < wins.length; i++) {{\n\
         \tif (wins[i].pid == {pid}) {{\n\
         \t\twins[i].minimized = false;\n\
         \t\tworkspace.activeWindow = wins[i];\n\
         \t}}\n\
         }}\n"
    );
    std::fs::File::create(&script_path)?.write_all(script.as_bytes())?;
    let plugin_name = format!("subnetdesk-activate-{pid}");

    let conn = Connection::new_session()?;
    let proxy = conn.with_proxy("org.kde.KWin", "/Scripting", DBUS_TIMEOUT);
    let (script_id,): (i32,) = proxy.method_call(
        "org.kde.kwin.Scripting",
        "loadScript",
        (script_path.to_string_lossy().to_string(), plugin_name.clone()),
    )?;
    let script_obj_path = format!("/Scripting/Script{script_id}");
    let script_proxy = conn.with_proxy("org.kde.KWin", script_obj_path, DBUS_TIMEOUT);
    let _: () = script_proxy.method_call("org.kde.kwin.Script", "run", ())?;
    let _: (bool,) =
        proxy.method_call("org.kde.kwin.Scripting", "unloadScript", (plugin_name,))?;
    let _ = std::fs::remove_file(&script_path);
    Ok(())
}

#[cfg(target_os = "linux")]
fn activate_main_window_workaround() {
    let pid = std::process::id();
    std::thread::spawn(move || {
        for _ in 0..5 {
            std::thread::sleep(Duration::from_millis(200));
            if let Err(err) = activate_via_kwin_script(pid) {
                log::debug!("KWin scripting activation unavailable/failed: {err}");
            }
            if let Err(err) =
                crate::platform::run_cmds(&format!("xdotool search --pid {pid} windowactivate"))
            {
                log::debug!("xdotool windowactivate workaround failed (xdotool missing?): {err}");
                return;
            }
        }
    });
}

fn handle_client_message(builder: &mut IfaceBuilder<()>) {
    // register new connection dbus
    builder.method(
        DBUS_METHOD_NEW_CONNECTION,
        (DBUS_METHOD_NEW_CONNECTION_ID,),
        (DBUS_METHOD_RETURN,),
        move |_, _, (_uni_links,): (String,)| {
            #[cfg(target_os = "linux")]
            activate_main_window_workaround();
            #[cfg(feature = "flutter")]
            {
                use crate::flutter;
                let data = HashMap::from([
                    ("name", "on_url_scheme_received"),
                    ("url", _uni_links.as_str()),
                ]);
                let event = serde_json::ser::to_string(&data).unwrap_or("".to_string());
                match crate::flutter::push_global_event(flutter::APP_TYPE_MAIN, event) {
                    None => log::error!("failed to find main event stream"),
                    Some(false) => {
                        log::error!("failed to add dbus message to flutter global dbus stream.")
                    }
                    Some(true) => {}
                }
            }
            return Ok((DBUS_METHOD_RETURN_SUCCESS.to_string(),));
        },
    );
}

// A host may run its own screen-locking power-save script that powers the
// physical monitor off (via org.gnome.Mutter.DisplayConfig's PowerSaveMode
// property) when the session locks, to save power/wear on an unattended
// machine. On GNOME, an incoming SubnetDesk connection while the screen is
// in that state can capture a monitor that's powered off (no frames ever
// arrive -- "Connection successful, waiting for image..." forever), and
// the user's own script has no way to know a remote viewer just connected,
// so it never wakes the display back up. Real fix: SubnetDesk wakes the
// display itself on a new connection (mirroring the exact D-Bus call such
// a script would use), and re-blanks it after the last viewer disconnects
// if the screen is still locked, so the power-saving behavior isn't lost.
//
// Best-effort and silent: this only matters on GNOME (org.gnome.ScreenSaver
// / org.gnome.Mutter.DisplayConfig on the session bus); on any other
// desktop, or one where the screen isn't locked, the very first check
// below is a no-op.
#[cfg(target_os = "linux")]
fn is_screen_locked(conn: &Connection) -> Result<bool, Box<dyn Error>> {
    let screensaver = conn.with_proxy(
        "org.gnome.ScreenSaver",
        "/org/gnome/ScreenSaver",
        DBUS_TIMEOUT,
    );
    let (locked,): (bool,) =
        screensaver.method_call("org.gnome.ScreenSaver", "GetActive", ())?;
    Ok(locked)
}

#[cfg(target_os = "linux")]
fn set_display_power_save_mode(conn: &Connection, mode: i32) -> Result<(), Box<dyn Error>> {
    let display_config = conn.with_proxy(
        "org.gnome.Mutter.DisplayConfig",
        "/org/gnome/Mutter/DisplayConfig",
        DBUS_TIMEOUT,
    );
    display_config.set("org.gnome.Mutter.DisplayConfig", "PowerSaveMode", mode)?;
    Ok(())
}

/// Wake the display if the screen is currently locked and powered down.
/// Called when a new monitor/screen viewer connection is accepted.
#[cfg(target_os = "linux")]
pub fn wake_display_if_locked() {
    std::thread::spawn(|| {
        let run = || -> Result<(), Box<dyn Error>> {
            let conn = Connection::new_session()?;
            if is_screen_locked(&conn)? {
                set_display_power_save_mode(&conn, 0)?;
            }
            Ok(())
        };
        if let Err(err) = run() {
            log::debug!("wake_display_if_locked unavailable/failed (not GNOME?): {err}");
        }
    });
}

/// Re-blank the display after the last viewer disconnects, if the screen
/// is still locked -- restoring the power-saving behavior that
/// [`wake_display_if_locked`] temporarily overrode. Only call this once
/// the connection count has actually reached zero.
#[cfg(target_os = "linux")]
pub fn reblank_display_if_still_locked() {
    std::thread::spawn(|| {
        // Short grace period in case of a near-immediate reconnect, similar
        // in spirit to a user power-save script's own debounce.
        std::thread::sleep(Duration::from_secs(5));
        let run = || -> Result<(), Box<dyn Error>> {
            let conn = Connection::new_session()?;
            if is_screen_locked(&conn)? {
                set_display_power_save_mode(&conn, 3)?;
            }
            Ok(())
        };
        if let Err(err) = run() {
            log::debug!("reblank_display_if_still_locked unavailable/failed (not GNOME?): {err}");
        }
    });
}
