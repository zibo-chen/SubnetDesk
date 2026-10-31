import Cocoa
import AVFoundation
import FlutterMacOS
import Network
import app_links
import desktop_multi_window
// import bitsdojo_window_macos

import desktop_drop
import device_info_plus
import flutter_custom_cursor
import package_info_plus
import path_provider_foundation
import screen_retriever
import sqflite_darwin
// import tray_manager
import url_launcher_macos
import wakelock_plus
import window_manager
import window_size
import texture_rgba_renderer

// Global state for relative mouse mode
// All properties and methods must be accessed on the main thread since they
// interact with NSEvent monitors, CoreGraphics APIs, and Flutter channels.
// Note: We avoid @MainActor because the plugin callback APIs are not actor-isolated.
class RelativeMouseState {
    static let shared = RelativeMouseState()

    var enabled = false
    var eventMonitor: Any?
    var deltaChannel: FlutterMethodChannel?
    var accumulatedDeltaX: CGFloat = 0
    var accumulatedDeltaY: CGFloat = 0

    private init() {}
}

private final class LocalNetworkPermissionProbe {
    private let queue = DispatchQueue(label: "com.zibochen.subnetdesk.local-network-permission")
    private let serviceName = "SubnetDesk-\(UUID().uuidString)"
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var completion: ((String) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var finished = false
    private var browserStarted = false

    func start(completion: @escaping (String) -> Void) {
        queue.async {
            self.completion = completion
            do {
                let parameters = NWParameters.tcp
                parameters.includePeerToPeer = true

                let listener = try NWListener(using: parameters)
                listener.service = NWListener.Service(
                    name: self.serviceName,
                    type: "_subnetdesk._tcp"
                )
                listener.newConnectionHandler = { connection in
                    connection.cancel()
                }
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                self.listener = listener

                let browser = NWBrowser(
                    for: .bonjour(type: "_subnetdesk._tcp", domain: nil),
                    using: parameters
                )
                browser.stateUpdateHandler = { [weak self] state in
                    self?.handleBrowserState(state)
                }
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    guard let self = self else { return }
                    let foundOwnService = results.contains { result in
                        guard case .service(let name, _, _, _) = result.endpoint else {
                            return false
                        }
                        return name == self.serviceName
                    }
                    if foundOwnService {
                        self.finish("authorized")
                    }
                }
                self.browser = browser

                listener.start(queue: self.queue)

                let timeout = DispatchWorkItem { [weak self] in
                    self?.finish("unknown")
                }
                self.timeoutWorkItem = timeout
                self.queue.asyncAfter(deadline: .now() + 30, execute: timeout)
            } catch {
                NSLog("[SubnetDesk] Failed to start the local-network permission probe: %@", error.localizedDescription)
                self.finish("unknown")
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if !browserStarted {
                browserStarted = true
                browser?.start(queue: queue)
            }
        case .waiting(let error), .failed(let error):
            handle(error)
        default:
            break
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error), .failed(let error):
            handle(error)
        default:
            break
        }
    }

    private func handle(_ error: NWError) {
        if Self.isPermissionDenied(error) {
            finish("denied")
        } else {
            NSLog("[SubnetDesk] Local-network permission probe failed: %@", error.debugDescription)
            finish("unknown")
        }
    }

    private static func isPermissionDenied(_ error: NWError) -> Bool {
        switch error {
        case .dns(let code):
            return code == -65570 || code == -65571
        case .posix(let code):
            return code == .EPERM || code == .EACCES
        default:
            return false
        }
    }

    private func finish(_ status: String) {
        guard !finished else { return }
        finished = true
        timeoutWorkItem?.cancel()
        browser?.cancel()
        listener?.cancel()
        browser = nil
        listener = nil
        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(status)
        }
    }
}

class MainFlutterWindow: NSWindow {
    private var localNetworkPermissionProbe: LocalNetworkPermissionProbe?
    private var desktopChannel: FlutterMethodChannel?
    private var statusItem: NSStatusItem?

    private func configureDesktopRuntime(_ options: [String: Any], channel: FlutterMethodChannel) {
        desktopChannel = channel
        if statusItem == nil {
            guard let image = NSImage(named: NSImage.Name("mac-tray-light-x2")) else {
                NSLog("[SubnetDesk] Missing tray icon resource")
                return
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = "SubnetDesk"
            item.button?.setAccessibilityLabel("SubnetDesk")
            statusItem = item
        }
        let menu = NSMenu()
        let status = NSMenuItem(title: options["status"] as? String ?? "SubnetDesk",
                                action: nil, keyEquivalent: "")
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())
        func add(_ key: String, _ fallback: String, _ action: String,
                 checked: Bool? = nil, shortcut: String = "") {
            let item = NSMenuItem(title: options[key] as? String ?? fallback,
                                  action: #selector(desktopMenuAction(_:)), keyEquivalent: shortcut)
            item.target = self
            item.representedObject = action
            if let checked = checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }
        add("openLabel", "Open SubnetDesk", "open")
        add("settingsLabel", "Settings…", "settings", shortcut: ",")
        menu.addItem(NSMenuItem.separator())
        add("sharingLabel", "Allow remote access", "sharing", checked: options["sharing"] as? Bool ?? false)
        add("autostartLabel", "Start at login", "autostart", checked: options["autostart"] as? Bool ?? false)
        menu.addItem(NSMenuItem.separator())
        add("dataLabel", "Open data folder", "data")
        menu.addItem(NSMenuItem.separator())
        add("quitLabel", "Quit SubnetDesk", "quit", shortcut: "q")
        statusItem?.menu = menu
        statusItem?.button?.toolTip = options["status"] as? String ?? "SubnetDesk"
    }

    @objc private func desktopMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        desktopChannel?.invokeMethod("desktopAction", arguments: action)
    }

    func reopenMainWindow() {
        desktopChannel?.invokeMethod("desktopAction", arguments: "open")
    }

    private static let fullscreenWorkAreaSizes = NSMapTable<NSWindow, NSValue>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )
    private static let fullscreenObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willEnterFullScreenNotification,
        object: nil,
        queue: .main
    ) { notification in
        guard let window = notification.object as? NSWindow,
              let screen = window.screen else {
            return
        }
        fullscreenWorkAreaSizes.setObject(
            NSValue(size: screen.visibleFrame.size),
            forKey: window
        )
    }

    override func awakeFromNib() {
        rustdesk_core_main();
        _ = MainFlutterWindow.fullscreenObserver
        let flutterViewController = FlutterViewController.init()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        // register self method handler
        let registrar = flutterViewController.registrar(forPlugin: "RustDeskPlugin")
        setMethodHandler(registrar: registrar)

        RegisterGeneratedPlugins(registry: flutterViewController)

        FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
            // Register the plugin which you want access from other isolate.
            // DesktopLifecyclePlugin.register(with: controller.registrar(forPlugin: "DesktopLifecyclePlugin"))
            // Note: copy below from above RegisterGeneratedPlugins
            self.setMethodHandler(registrar: controller.registrar(forPlugin: "RustDeskPlugin"))
            DesktopDropPlugin.register(with: controller.registrar(forPlugin: "DesktopDropPlugin"))
            DeviceInfoPlusMacosPlugin.register(with: controller.registrar(forPlugin: "DeviceInfoPlusMacosPlugin"))
            FlutterCustomCursorPlugin.register(with: controller.registrar(forPlugin: "FlutterCustomCursorPlugin"))
            FPPPackageInfoPlusPlugin.register(with: controller.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
            PathProviderPlugin.register(with: controller.registrar(forPlugin: "PathProviderPlugin"))
            SqflitePlugin.register(with: controller.registrar(forPlugin: "SqflitePlugin"))
            // TrayManagerPlugin.register(with: controller.registrar(forPlugin: "TrayManagerPlugin"))
            AppLinksMacosPlugin.register(with: controller.registrar(forPlugin: "AppLinksMacosPlugin"))
            UrlLauncherPlugin.register(with: controller.registrar(forPlugin: "UrlLauncherPlugin"))
            WakelockPlusMacosPlugin.register(with: controller.registrar(forPlugin: "WakelockPlusMacosPlugin"))
            WindowSizePlugin.register(with: controller.registrar(forPlugin: "WindowSizePlugin"))
            TextureRgbaRendererPlugin.register(with: controller.registrar(forPlugin: "TextureRgbaRendererPlugin"))
        }

        super.awakeFromNib()
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }

    /// Override window theme.
    public func setWindowInterfaceMode(window: NSWindow, themeName: String) {
        window.appearance = NSAppearance(named: themeName == "light" ? .aqua : .darkAqua)
    }

    private func enableNativeRelativeMouseMode(channel: FlutterMethodChannel) -> Bool {
        assert(Thread.isMainThread, "enableNativeRelativeMouseMode must be called on the main thread")
        let state = RelativeMouseState.shared
        if state.enabled {
            // Already enabled: update the channel so this caller receives deltas.
            state.deltaChannel = channel
            return true
        }

        // Dissociate mouse from cursor position - this locks the cursor in place
        // Do this FIRST before setting any state
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        if result != CGError.success {
            NSLog("[SubnetDesk] Failed to dissociate mouse from cursor position: %d", result.rawValue)
            return false
        }

        // Only set state after CG call succeeds
        state.deltaChannel = channel
        state.accumulatedDeltaX = 0
        state.accumulatedDeltaY = 0

        // Add local event monitor to capture mouse delta.
        // Note: Local event monitors are always called on the main thread,
        // so accessing main-thread-only state is safe here.
        state.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak state] event in
            guard let state = state else { return event }
            // Guard against race: mode may be disabled between weak capture and this check.
            guard state.enabled else { return event }
            let deltaX = event.deltaX
            let deltaY = event.deltaY

            if deltaX != 0 || deltaY != 0 {
                // Accumulate delta (main thread only - NSEvent local monitors always run on main thread)
                state.accumulatedDeltaX += deltaX
                state.accumulatedDeltaY += deltaY

                // Only send if we have integer movement
                let intX = Int(state.accumulatedDeltaX)
                let intY = Int(state.accumulatedDeltaY)

                if intX != 0 || intY != 0 {
                    state.accumulatedDeltaX -= CGFloat(intX)
                    state.accumulatedDeltaY -= CGFloat(intY)

                    // Send delta to Flutter (already on main thread)
                    state.deltaChannel?.invokeMethod("onMouseDelta", arguments: ["dx": intX, "dy": intY])
                }
            }

            return event
        }

        // Check if monitor was created successfully
        if state.eventMonitor == nil {
            NSLog("[SubnetDesk] Failed to create event monitor for relative mouse mode")
            // Re-associate mouse since we failed
            CGAssociateMouseAndMouseCursorPosition(1)
            state.deltaChannel = nil
            return false
        }

        // Set enabled LAST after everything succeeds
        state.enabled = true
        return true
    }

    private func disableNativeRelativeMouseMode() {
        assert(Thread.isMainThread, "disableNativeRelativeMouseMode must be called on the main thread")
        let state = RelativeMouseState.shared
        if !state.enabled { return }

        state.enabled = false

        // Remove event monitor
        if let monitor = state.eventMonitor {
            NSEvent.removeMonitor(monitor)
            state.eventMonitor = nil
        }

        state.deltaChannel = nil
        state.accumulatedDeltaX = 0
        state.accumulatedDeltaY = 0

        // Re-associate mouse with cursor position (non-blocking with async retry)
        let result = CGAssociateMouseAndMouseCursorPosition(1)
        if result != CGError.success {
            NSLog("[SubnetDesk] Failed to re-associate mouse with cursor position: %d, scheduling retry...", result.rawValue)
            // Non-blocking retry after 50ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let retryResult = CGAssociateMouseAndMouseCursorPosition(1)
                if retryResult != CGError.success {
                    NSLog("[SubnetDesk] Retry failed to re-associate mouse: %d. Cursor may remain locked.", retryResult.rawValue)
                }
            }
        }
    }

    public func setMethodHandler(registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.rustdesk.rustdesk/host", binaryMessenger: registrar.messenger)
        channel.setMethodCallHandler({
            (call, result) -> Void in
                switch call.method {
                case "configureDesktopRuntime":
                    guard let options = call.arguments as? [String: Any] else {
                        result(FlutterError(code: "arguments", message: "Missing desktop options", details: nil))
                        return
                    }
                    self.configureDesktopRuntime(options, channel: channel)
                    if self.statusItem == nil {
                        result(FlutterError(code: "tray-icon", message: "Missing SubnetDesk tray icon", details: nil))
                    } else {
                        result(true)
                    }
                case "setWindowTheme":
                    let arg = call.arguments as! [String: Any]
                    let themeName = arg["themeName"] as? String
                    guard let window = registrar.view?.window else {
                        result(nil)
                        return
                    }
                    self.setWindowInterfaceMode(window: window,themeName: themeName ?? "light")
                    result(nil)
                    break;
                case "terminate":
                    NSApplication.shared.terminate(self)
                    result(nil)
                case "canRecordAudio":
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized:
                        result(1)
                        break
                    case .notDetermined:
                        result(0)
                        break
                    default:
                        result(-1)
                        break
                    }
                case "requestRecordAudio":
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                        DispatchQueue.main.async {
                            result(granted)
                        }
                    })
                    break
                case "checkLocalNetworkPermission":
                    if self.localNetworkPermissionProbe != nil {
                        result("checking")
                        break
                    }
                    let probe = LocalNetworkPermissionProbe()
                    self.localNetworkPermissionProbe = probe
                    probe.start { [weak self] status in
                        self?.localNetworkPermissionProbe = nil
                        result(status)
                    }
                case "openLocalNetworkSettings":
                    let urls = [
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"
                    ]
                    let opened = urls.compactMap(URL.init(string:)).contains {
                        NSWorkspace.shared.open($0)
                    }
                    result(opened)
                case "bumpMouse":
                    var dx = 0
                    var dy = 0

                    if let argMap = call.arguments as? [String: Any] {
                        dx = (argMap["dx"] as? Int) ?? 0
                        dy = (argMap["dy"] as? Int) ?? 0
                    }
                    else if let argList = call.arguments as? [Any] {
                        dx = argList.count >= 1 ? (argList[0] as? Int) ?? 0 : 0
                        dy = argList.count >= 2 ? (argList[1] as? Int) ?? 0 : 0
                    }

                    var mouseLoc: CGPoint

                    if let dummyEvent = CGEvent(source: nil) { // can this ever fail?
                        mouseLoc = dummyEvent.location
                    }
                    else if let screenFrame = NSScreen.screens.first?.frame {
                        // NeXTStep: Origin is lower-left of primary screen, positive is up
                        // Cocoa Core Graphics: Origin is upper-left of primary screen, positive is down
                        let nsMouseLoc = NSEvent.mouseLocation

                        mouseLoc = CGPoint(
                            x: nsMouseLoc.x,
                            y: NSHeight(screenFrame) - nsMouseLoc.y)
                    }
                    else {
                        result(false)
                        break
                    }

                    let newLoc = CGPoint(x: mouseLoc.x + CGFloat(dx), y: mouseLoc.y + CGFloat(dy))

                    CGDisplayMoveCursorToPoint(0, newLoc)

                    // By default, Cocoa suppresses mouse events briefly after a call to warp the
                    // cursor to a new location. This is good if you want to draw the user's
                    // attention to the fact that the mouse is now in a particular location, but
                    // it's bad in this case; we get called as part of the handling of edge
                    // scrolling, which means the mouse is typically still in motion, and we want
                    // the cursor to keep moving smoothly uninterrupted.
                    //
                    // This function's main action is to toggle whether the mouse cursor is
                    // associated with the mouse position, but setting it to true when it's
                    // already true has the side-effect of cancelling this motion suppression.
                    //
                    // However, we must NOT call this when relative mouse mode is active,
                    // as it would break the pointer lock established by enableNativeRelativeMouseMode.
                    if !RelativeMouseState.shared.enabled {
                        CGAssociateMouseAndMouseCursorPosition(1 /* true */)
                    }

                    result(true)

                case "enableNativeRelativeMouseMode":
                    let success = self.enableNativeRelativeMouseMode(channel: channel)
                    result(success)

                case "disableNativeRelativeMouseMode":
                    self.disableNativeRelativeMouseMode()
                    result(true)

                case "getMacOSWorkAreaSize":
                    guard Thread.isMainThread,
                          let window = registrar.view?.window,
                          let size = MainFlutterWindow.fullscreenWorkAreaSizes
                            .object(forKey: window)?.sizeValue else {
                        result(nil)
                        break
                    }
                    result([Double(size.width), Double(size.height)])

                default:
                    result(FlutterMethodNotImplemented)
                }
        })
    }
}
