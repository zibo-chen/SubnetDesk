use crate::client::translate;
#[cfg(windows)]
use crate::ipc::Data;
#[cfg(windows)]
use hbb_common::tokio;
use hbb_common::{
    allow_err,
    config::{option2bool, Config, LocalConfig, PeerConfig},
    log,
};
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

const TRAY_REFRESH_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Clone, Debug, Eq, PartialEq)]
struct FavoritePeerSource {
    endpoint: String,
    hostname: String,
    alias: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct FavoriteTrayEntry {
    endpoint: String,
    label: String,
}

fn sanitize_menu_text(value: &str) -> String {
    let normalized = value
        .chars()
        .map(|character| {
            if character.is_control() {
                ' '
            } else {
                character
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace('&', "&&");
    let mut characters = normalized.chars();
    let shortened = characters.by_ref().take(64).collect::<String>();
    if characters.next().is_some() {
        format!("{shortened}...")
    } else {
        shortened
    }
}

fn favorite_tray_entries(
    favorites: Vec<String>,
    sources: Vec<FavoritePeerSource>,
) -> Vec<FavoriteTrayEntry> {
    let sources = sources
        .into_iter()
        .fold(HashMap::new(), |mut peers, source| {
            peers.entry(source.endpoint.clone()).or_insert(source);
            peers
        });
    let mut seen = HashSet::new();
    favorites
        .into_iter()
        .filter(|endpoint| seen.insert(endpoint.clone()))
        .filter_map(|endpoint| {
            let safe_endpoint = sanitize_menu_text(&endpoint);
            if safe_endpoint.is_empty() {
                return None;
            }
            let display_name = sources.get(&endpoint).map(|source| {
                if source.alias.trim().is_empty() {
                    source.hostname.as_str()
                } else {
                    source.alias.as_str()
                }
            });
            let display_name = display_name.map(sanitize_menu_text).unwrap_or_default();
            let label = if display_name.is_empty() || display_name == safe_endpoint {
                safe_endpoint
            } else {
                format!("{display_name} - {safe_endpoint}")
            };
            Some(FavoriteTrayEntry { endpoint, label })
        })
        .collect()
}

fn load_favorite_tray_entries() -> Vec<FavoriteTrayEntry> {
    let (favorites, recent) = LocalConfig::load_fav_with_recent_lan_endpoints();
    let mut favorite_endpoints = HashSet::new();
    for endpoint in &favorites {
        if sanitize_menu_text(endpoint).is_empty() {
            continue;
        }
        favorite_endpoints.insert(endpoint.clone());
    }
    let mut loaded_endpoints = HashSet::new();
    let sources = recent
        .into_iter()
        .filter(|peer| {
            favorite_endpoints.contains(&peer.endpoint)
                && loaded_endpoints.insert(peer.endpoint.clone())
        })
        .map(|peer| FavoritePeerSource {
            alias: PeerConfig::load(&peer.endpoint)
                .options
                .get("alias")
                .cloned()
                .unwrap_or_default(),
            endpoint: peer.endpoint,
            hostname: peer.hostname,
        })
        .collect();
    favorite_tray_entries(favorites, sources)
}

fn service_action_translation_key(service_enabled: bool) -> &'static str {
    if service_enabled {
        "Stop service"
    } else {
        "Start service"
    }
}

fn service_enabled_from_disk() -> bool {
    !option2bool(
        "stop-service",
        &Config::get_option_from_file("stop-service"),
    )
}

fn set_service_enabled(enabled: bool) {
    crate::ipc::set_option("stop-service", if enabled { "" } else { "Y" });
}

fn connect_favorite(endpoint: &str) {
    if let Err(err) = crate::run_me(vec!["--connect", endpoint]) {
        log::error!("Failed to connect to favorite peer {endpoint}: {err}");
    }
}

fn native_menu_item(
    text: String,
    enabled: bool,
    native_icon: tray_icon::menu::NativeIcon,
) -> tray_icon::menu::IconMenuItem {
    #[cfg(target_os = "macos")]
    return tray_icon::menu::IconMenuItem::with_native_icon(text, enabled, Some(native_icon), None);
    #[cfg(not(target_os = "macos"))]
    {
        let _ = native_icon;
        tray_icon::menu::IconMenuItem::new(text, enabled, None, None)
    }
}

fn update_service_menu_item(item: &tray_icon::menu::IconMenuItem, service_enabled: bool) {
    use tray_icon::menu::NativeIcon;

    item.set_text(translate(
        service_action_translation_key(service_enabled).to_owned(),
    ));
    #[cfg(target_os = "macos")]
    item.set_native_icon(Some(if service_enabled {
        NativeIcon::StopProgress
    } else {
        NativeIcon::StatusAvailable
    }));
    #[cfg(not(target_os = "macos"))]
    let _ = NativeIcon::StatusAvailable;
}

#[derive(Default)]
struct FavoriteMenuState {
    entries: Option<Vec<FavoriteTrayEntry>>,
    items: Vec<(tray_icon::menu::IconMenuItem, Option<String>)>,
}

impl FavoriteMenuState {
    fn refresh(&mut self, submenu: &tray_icon::menu::Submenu, entries: Vec<FavoriteTrayEntry>) {
        if self.entries.as_ref() == Some(&entries) {
            return;
        }
        while submenu.remove_at(0).is_some() {}
        self.items.clear();

        if entries.is_empty() {
            let item = tray_icon::menu::IconMenuItem::new(
                translate("Empty".to_owned()),
                false,
                None,
                None,
            );
            if let Err(err) = submenu.append(&item) {
                log::error!("Failed to append empty favorites tray item: {err}");
            }
            self.items.push((item, None));
        } else {
            for entry in &entries {
                let item = native_menu_item(
                    entry.label.clone(),
                    true,
                    tray_icon::menu::NativeIcon::Computer,
                );
                if let Err(err) = submenu.append(&item) {
                    log::error!("Failed to append favorite tray item: {err}");
                    continue;
                }
                self.items.push((item, Some(entry.endpoint.clone())));
            }
        }
        self.entries = Some(entries);
    }

    fn endpoint_for_event(&self, event: &tray_icon::menu::MenuEvent) -> Option<&str> {
        self.items.iter().find_map(|(item, endpoint)| {
            if event.id == item.id() {
                endpoint.as_deref()
            } else {
                None
            }
        })
    }
}

pub fn start_tray() {
    if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
        return;
    }

    #[cfg(target_os = "linux")]
    crate::server::check_zombie();

    allow_err!(make_tray(true));
}

#[cfg(target_os = "macos")]
pub fn start_server_event_loop() {
    allow_err!(make_tray(false));
}

fn make_tray(show_icon: bool) -> hbb_common::ResultType<()> {
    // https://github.com/tauri-apps/tray-icon/blob/dev/examples/tao.rs
    use hbb_common::anyhow::Context;
    use tao::event_loop::{ControlFlow, EventLoopBuilder};
    use tray_icon::{
        menu::{Menu, MenuEvent, NativeIcon, PredefinedMenuItem, Submenu},
        TrayIcon, TrayIconBuilder, TrayIconEvent as TrayEvent,
    };
    let icon;
    #[cfg(target_os = "macos")]
    {
        icon = include_bytes!("../res/mac-tray-dark-x2.png"); // use as template, so color is not important
    }
    #[cfg(not(target_os = "macos"))]
    {
        icon = include_bytes!("../res/tray-icon.ico");
    }

    let (icon_rgba, icon_width, icon_height) = {
        let image = load_icon_from_asset()
            .unwrap_or(image::load_from_memory(icon).context("Failed to open icon path")?)
            .into_rgba8();
        let (width, height) = image.dimensions();
        let rgba = image.into_raw();
        (rgba, width, height)
    };
    let icon = tray_icon::Icon::from_rgba(icon_rgba, icon_width, icon_height)
        .context("Failed to open icon")?;

    let mut event_loop = EventLoopBuilder::new().build();

    let tray_menu = Menu::new();
    let hide_stop_service =
        crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_STOP_SERVICE)
            == "Y";
    let open_i = native_menu_item(translate("Open".to_owned()), true, NativeIcon::Computer);
    let favorites_menu = Submenu::new(translate("Favorites".to_owned()), true);
    let mut favorite_menu_state = FavoriteMenuState::default();
    favorite_menu_state.refresh(&favorites_menu, load_favorite_tray_entries());
    let separator_i = PredefinedMenuItem::separator();
    let mut service_enabled = service_enabled_from_disk();
    let service_i = if !hide_stop_service {
        Some(native_menu_item(
            translate(service_action_translation_key(service_enabled).to_owned()),
            true,
            if service_enabled {
                NativeIcon::StopProgress
            } else {
                NativeIcon::StatusAvailable
            },
        ))
    } else {
        None
    };
    let quit_i = native_menu_item(translate("Quit".to_owned()), true, NativeIcon::Remove);
    tray_menu
        .append(&open_i)
        .context("Failed to append open tray item")?;
    tray_menu
        .append(&favorites_menu)
        .context("Failed to append favorites tray menu")?;
    tray_menu
        .append(&separator_i)
        .context("Failed to append tray separator")?;
    if let Some(service_i) = &service_i {
        tray_menu
            .append(service_i)
            .context("Failed to append service tray item")?;
    }
    tray_menu
        .append(&quit_i)
        .context("Failed to append quit tray item")?;

    let tooltip = |enabled: bool, count: usize| {
        if !enabled {
            format!(
                "{} - {}",
                crate::get_app_name(),
                translate("Service is not running".to_owned()),
            )
        } else if count == 0 {
            format!(
                "{} - {}",
                crate::get_app_name(),
                translate("Service is running".to_owned()),
            )
        } else {
            format!(
                "{} - {}\n{}",
                crate::get_app_name(),
                translate("Ready".to_owned()),
                translate("{".to_string() + &format!("{count}") + "} sessions"),
            )
        }
    };
    let mut _tray_icon: Arc<Mutex<Option<TrayIcon>>> = Default::default();
    #[cfg(windows)]
    let mut session_count = 0;
    #[cfg(not(windows))]
    let session_count = 0;
    let mut last_refresh = Instant::now();

    let menu_channel = MenuEvent::receiver();
    let tray_channel = TrayEvent::receiver();
    #[cfg(windows)]
    let (ipc_sender, ipc_receiver) = std::sync::mpsc::channel::<Data>();

    let open_func = move || {
        if cfg!(not(feature = "flutter")) {
            crate::run_me::<&str>(vec![]).ok();
            return;
        }
        #[cfg(target_os = "macos")]
        crate::platform::macos::handle_application_should_open_untitled_file();
        #[cfg(target_os = "windows")]
        {
            // Do not use "start uni link" way, it may not work on some Windows, and pop out error
            // dialog, I found on one user's desktop, but no idea why, Windows is shit.
            // Use `run_me` instead.
            // `allow_multiple_instances` in `flutter/windows/runner/main.cpp` allows only one instance without args.
            crate::run_me::<&str>(vec![]).ok();
        }
        #[cfg(target_os = "linux")]
        {
            // Do not use "xdg-open", it won't read the config.
            if crate::dbus::invoke_new_connection(crate::get_uri_prefix()).is_err() {
                if let Ok(task) = crate::run_me::<&str>(vec![]) {
                    crate::server::CHILD_PROCESS.lock().unwrap().push(task);
                }
            }
        }
    };

    #[cfg(windows)]
    std::thread::spawn(move || {
        start_query_session_count(ipc_sender.clone());
    });
    #[cfg(windows)]
    let mut last_click = std::time::Instant::now();
    #[cfg(target_os = "macos")]
    {
        use tao::platform::macos::EventLoopExtMacOS;
        event_loop.set_activation_policy(tao::platform::macos::ActivationPolicy::Accessory);
    }
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(
            std::time::Instant::now() + std::time::Duration::from_millis(100),
        );

        if let tao::event::Event::NewEvents(tao::event::StartCause::Init) = event {
            // macOS still needs this event loop in the server process for
            // main-thread input dispatch, but only the dedicated --tray
            // process should own a visible status item.
            if !show_icon {
                return;
            }
            // We create the icon once the event loop is actually running
            // to prevent issues like https://github.com/tauri-apps/tray-icon/issues/90
            let mut builder = TrayIconBuilder::new()
                .with_menu(Box::new(tray_menu.clone()))
                .with_tooltip(tooltip(service_enabled, session_count))
                .with_icon(icon.clone());
            #[cfg(target_os = "macos")]
            {
                builder = builder.with_icon_as_template(true);
            }
            #[cfg(target_os = "windows")]
            {
                // Required since tray-icon 0.17
                // Fixes #15215, #15222, #15410
                builder = builder.with_menu_on_left_click(false);
            }
            let tray = builder.build();
            match tray {
                Ok(tray) => _tray_icon = Arc::new(Mutex::new(Some(tray))),
                Err(err) => {
                    log::error!("Failed to create tray icon: {}", err);
                }
            };

            // We have to request a redraw here to have the icon actually show up.
            // Tao only exposes a redraw method on the Window so we use core-foundation directly.
            #[cfg(target_os = "macos")]
            unsafe {
                use core_foundation::runloop::{CFRunLoopGetMain, CFRunLoopWakeUp};

                let rl = CFRunLoopGetMain();
                CFRunLoopWakeUp(rl);
            }
        }

        if let Ok(event) = menu_channel.try_recv() {
            if event.id == open_i.id() {
                open_func();
            } else if event.id == quit_i.id() {
                if let Err(err) = crate::ipc::close_all_instances() {
                    log::debug!("No open Flutter window to close: {err}");
                }
                #[cfg(target_os = "macos")]
                if let Err(err) = crate::ipc::shutdown_background_server() {
                    log::debug!("No background server to stop: {err}");
                }
                *control_flow = ControlFlow::Exit;
            } else if let Some(service_i) = &service_i {
                if event.id == service_i.id() {
                    service_enabled = !service_enabled;
                    set_service_enabled(service_enabled);
                    update_service_menu_item(service_i, service_enabled);
                    if let Ok(mut tray) = _tray_icon.lock() {
                        if let Some(tray) = tray.as_mut() {
                            if let Err(err) =
                                tray.set_tooltip(Some(tooltip(service_enabled, session_count)))
                            {
                                log::error!("Failed to update tray tooltip: {err}");
                            }
                        }
                    }
                }
            }
            if let Some(endpoint) = favorite_menu_state.endpoint_for_event(&event) {
                connect_favorite(endpoint);
            }
        }

        if show_icon && last_refresh.elapsed() >= TRAY_REFRESH_INTERVAL {
            favorite_menu_state.refresh(&favorites_menu, load_favorite_tray_entries());
            let persisted_service_enabled = service_enabled_from_disk();
            if persisted_service_enabled != service_enabled {
                service_enabled = persisted_service_enabled;
                if let Some(service_i) = &service_i {
                    update_service_menu_item(service_i, service_enabled);
                }
                if let Ok(mut tray) = _tray_icon.lock() {
                    if let Some(tray) = tray.as_mut() {
                        if let Err(err) =
                            tray.set_tooltip(Some(tooltip(service_enabled, session_count)))
                        {
                            log::error!("Failed to update tray tooltip: {err}");
                        }
                    }
                }
            }
            last_refresh = Instant::now();
        }

        if let Ok(_event) = tray_channel.try_recv() {
            #[cfg(target_os = "windows")]
            match _event {
                TrayEvent::Click {
                    button,
                    button_state,
                    ..
                } => {
                    if button == tray_icon::MouseButton::Left
                        && button_state == tray_icon::MouseButtonState::Up
                    {
                        if last_click.elapsed() < std::time::Duration::from_secs(1) {
                            return;
                        }
                        open_func();
                        last_click = std::time::Instant::now();
                    }
                }
                _ => {}
            }
        }

        #[cfg(windows)]
        if let Ok(data) = ipc_receiver.try_recv() {
            match data {
                Data::ControlledSessionCount(count) => {
                    session_count = count;
                    if let Ok(mut tray) = _tray_icon.lock() {
                        if let Some(tray) = tray.as_mut() {
                            if let Err(err) =
                                tray.set_tooltip(Some(tooltip(service_enabled, session_count)))
                            {
                                log::error!("Failed to update tray tooltip: {err}");
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    });
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn start_query_session_count(sender: std::sync::mpsc::Sender<Data>) {
    let mut last_count = 0;
    loop {
        if let Ok(mut c) = crate::ipc::connect(1000, "").await {
            let mut timer = crate::rustdesk_interval(tokio::time::interval(Duration::from_secs(1)));
            loop {
                tokio::select! {
                    res = c.next() => {
                        match res {
                            Err(err) => {
                                log::error!("ipc connection closed: {}", err);
                                break;
                            }

                            Ok(Some(Data::ControlledSessionCount(count))) => {
                                if count != last_count {
                                    last_count = count;
                                    sender.send(Data::ControlledSessionCount(count)).ok();
                                }
                            }
                            _ => {}
                        }
                    }

                    _ = timer.tick() => {
                        c.send(&Data::ControlledSessionCount(0)).await.ok();
                    }
                }
            }
        }
        hbb_common::sleep(1.).await;
    }
}

fn load_icon_from_asset() -> Option<image::DynamicImage> {
    let Some(path) = std::env::current_exe().map_or(None, |x| x.parent().map(|x| x.to_path_buf()))
    else {
        return None;
    };
    #[cfg(target_os = "macos")]
    let path = path.join("../Frameworks/App.framework/Resources/flutter_assets/assets/icon.png");
    #[cfg(windows)]
    let path = path.join(r"data\flutter_assets\assets\icon.png");
    #[cfg(target_os = "linux")]
    let path = path.join(r"data/flutter_assets/assets/icon.png");
    if path.exists() {
        if let Ok(image) = image::open(path) {
            return Some(image);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn favorite_entries_keep_favorite_order_and_prefer_aliases() {
        let favorites = vec![
            "192.168.1.12:21118".to_owned(),
            "192.168.1.11:21118".to_owned(),
        ];
        let sources = vec![
            FavoritePeerSource {
                endpoint: "192.168.1.11:21118".to_owned(),
                hostname: "Office Mac".to_owned(),
                alias: "Design Desk".to_owned(),
            },
            FavoritePeerSource {
                endpoint: "192.168.1.12:21118".to_owned(),
                hostname: "Meeting Room".to_owned(),
                alias: String::new(),
            },
        ];

        let entries = favorite_tray_entries(favorites, sources);

        assert_eq!(
            entries,
            vec![
                FavoriteTrayEntry {
                    endpoint: "192.168.1.12:21118".to_owned(),
                    label: "Meeting Room - 192.168.1.12:21118".to_owned(),
                },
                FavoriteTrayEntry {
                    endpoint: "192.168.1.11:21118".to_owned(),
                    label: "Design Desk - 192.168.1.11:21118".to_owned(),
                },
            ]
        );
    }

    #[test]
    fn favorite_entries_sanitize_menu_text_and_include_unknown_peers() {
        let favorites = vec![
            "10.0.0.1:21118".to_owned(),
            "10.0.0.2:21118".to_owned(),
            "10.0.0.3:21118".to_owned(),
        ];
        let sources = vec![FavoritePeerSource {
            endpoint: "10.0.0.1:21118".to_owned(),
            hostname: "  Lab\n& Mac  ".to_owned(),
            alias: String::new(),
        }];

        let entries = favorite_tray_entries(favorites, sources);

        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0].label, "Lab && Mac - 10.0.0.1:21118");
        assert_eq!(entries[1].label, "10.0.0.2:21118");
        assert_eq!(entries[2].label, "10.0.0.3:21118");
    }

    #[test]
    fn service_action_label_describes_the_next_action() {
        assert_eq!(service_action_translation_key(true), "Stop service");
        assert_eq!(service_action_translation_key(false), "Start service");
    }

    #[test]
    fn favorite_entries_keep_the_newest_source_for_a_duplicate_endpoint() {
        let endpoint = "10.0.0.8:21118".to_owned();
        let sources = vec![
            FavoritePeerSource {
                endpoint: endpoint.clone(),
                hostname: "Current Mac".to_owned(),
                alias: String::new(),
            },
            FavoritePeerSource {
                endpoint: endpoint.clone(),
                hostname: "Old Mac".to_owned(),
                alias: String::new(),
            },
        ];

        let entries = favorite_tray_entries(vec![endpoint], sources);

        assert_eq!(entries[0].label, "Current Mac - 10.0.0.8:21118");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn quitting_the_tray_requests_a_clean_background_shutdown() {
        assert!(matches!(
            crate::ipc::background_shutdown_request(),
            crate::ipc::Data::Shutdown
        ));
    }
}
