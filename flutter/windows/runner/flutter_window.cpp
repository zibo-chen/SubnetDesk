#include "flutter_window.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <texture_rgba_renderer/texture_rgba_renderer_plugin_c_api.h>
#include <flutter_gpu_texture_renderer/flutter_gpu_texture_renderer_plugin_c_api.h>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <optional>
#include <memory>

#include "win32_desktop.h"
#include "resource.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  host_channel_ = std::make_unique<flutter::MethodChannel<>>(
    flutter_controller_->engine()->messenger(),
    "org.rustdesk.rustdesk/host",
    &flutter::StandardMethodCodec::GetInstance());

  host_channel_->SetMethodCallHandler(
    [this](const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
      if (call.method_name() == "configureDesktopRuntime") {
        if (!call.arguments() || !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
          result->Error("arguments", "Missing desktop options");
          return;
        }
        if (ConfigureTray(std::get<flutter::EncodableMap>(*call.arguments()))) {
          result->Success(true);
        } else {
          result->Error("tray", "Cannot create notification icon");
        }
      } else if (call.method_name() == "terminate") {
        result->Success();
        DestroyWindow(GetHandle());
      } else if (call.method_name() == "bumpMouse") {
        auto arguments = call.arguments();

        int dx = 0, dy = 0;

        if (std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          auto argsMap = std::get<flutter::EncodableMap>(*arguments);

          auto dxIt = argsMap.find(flutter::EncodableValue("dx"));
          auto dyIt = argsMap.find(flutter::EncodableValue("dy"));

          if ((dxIt != argsMap.end()) && std::holds_alternative<int>(dxIt->second)) {
            dx = std::get<int>(dxIt->second);
          }
          if ((dyIt != argsMap.end()) && std::holds_alternative<int>(dyIt->second)) {
            dy = std::get<int>(dyIt->second);
          }
        } else if (std::holds_alternative<flutter::EncodableList>(*arguments)) {
          auto argsList = std::get<flutter::EncodableList>(*arguments);

          if ((argsList.size() >= 1) && std::holds_alternative<int>(argsList[0])) {
            dx = std::get<int>(argsList[0]);
          }
          if ((argsList.size() >= 2) && std::holds_alternative<int>(argsList[1])) {
            dy = std::get<int>(argsList[1]);
          }
        }

        bool succeeded = Win32Desktop::BumpMouse(dx, dy);

        result->Success(succeeded);
      } else {
        result->NotImplemented();
      }
    });

  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    TextureRgbaRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("TextureRgbaRendererPlugin"));
    FlutterGpuTextureRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("FlutterGpuTextureRendererPluginCApi"));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (tray_visible_) Shell_NotifyIconW(NIM_DELETE, &tray_);
  tray_visible_ = false;
  host_channel_.reset();
  if (flutter_controller_) {
    // CreateAndShow calls Destroy before creating the first window. Only a
    // live Flutter controller owns a window whose teardown should stop the host.
    auto module = GetModuleHandleW(L"librustdesk.dll");
    if (module) {
      auto shutdown = reinterpret_cast<void (*)()>(GetProcAddress(module, "subnetdesk_shutdown"));
      if (shutdown) shutdown();
    }
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == taskbar_created_ && tray_visible_) {
    tray_visible_ = false;
    ConfigureTray(tray_options_);
    return 0;
  }
  if (message == WM_APP + 1) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      host_channel_->InvokeMethod("desktopAction", std::make_unique<flutter::EncodableValue>("open"));
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      HandleTrayMenu();
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

namespace {
std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size);
  return result;
}
std::wstring TrayLabel(const flutter::EncodableMap& options, const char* key, const char* fallback) {
  auto it = options.find(flutter::EncodableValue(key));
  return Utf8ToWide(it != options.end() && std::holds_alternative<std::string>(it->second)
      ? std::get<std::string>(it->second) : fallback);
}
bool TrayChecked(const flutter::EncodableMap& options, const char* key) {
  auto it = options.find(flutter::EncodableValue(key));
  return it != options.end() && std::holds_alternative<bool>(it->second) && std::get<bool>(it->second);
}
}

bool FlutterWindow::ConfigureTray(const flutter::EncodableMap& options) {
  tray_options_ = options;
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = 1;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_.uCallbackMessage = WM_APP + 1;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  const auto tip = TrayLabel(options, "status", "SubnetDesk");
  wcsncpy_s(tray_.szTip, tip.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(tray_visible_ ? NIM_MODIFY : NIM_ADD, &tray_)) return false;
  tray_visible_ = true;
  return true;
}

void FlutterWindow::HandleTrayMenu() {
  auto menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, 1, TrayLabel(tray_options_, "openLabel", "Open").c_str());
  AppendMenuW(menu, MF_STRING | (TrayChecked(tray_options_, "sharing") ? MF_CHECKED : 0), 2,
      TrayLabel(tray_options_, "sharingLabel", "Allow remote connections").c_str());
  AppendMenuW(menu, MF_STRING | (TrayChecked(tray_options_, "autostart") ? MF_CHECKED : 0), 3,
      TrayLabel(tray_options_, "autostartLabel", "Start at login").c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 4, TrayLabel(tray_options_, "dataLabel", "Open data folder").c_str());
  AppendMenuW(menu, MF_STRING, 5, TrayLabel(tray_options_, "quitLabel", "Quit").c_str());
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  const char* actions[] = {"", "open", "sharing", "autostart", "data", "quit"};
  if (command >= 1 && command <= 5 && host_channel_) {
    host_channel_->InvokeMethod("desktopAction", std::make_unique<flutter::EncodableValue>(actions[command]));
  }
}
