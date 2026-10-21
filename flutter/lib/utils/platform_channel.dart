import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/common.dart';

enum SystemWindowTheme { light, dark }

enum LocalNetworkPermissionStatus { authorized, denied, checking, unknown }

/// The platform channel for RustDesk.
class RdPlatformChannel {
  RdPlatformChannel._();

  static final RdPlatformChannel _windowUtil = RdPlatformChannel._();

  static RdPlatformChannel get instance => _windowUtil;

  final MethodChannel _hostMethodChannel =
      MethodChannel("org.rustdesk.rustdesk/host");

  /// Bump the position of the mouse cursor, if applicable
  Future<bool> bumpMouse({required int dx, required int dy}) async {
    // No debug output; this call is too chatty.

    bool? result = await _hostMethodChannel
      .invokeMethod("bumpMouse", {"dx": dx, "dy": dy});

    return result ?? false;
  }

  /// Change the theme of the system window
  Future<void> changeSystemWindowTheme(SystemWindowTheme theme) {
    assert(isMacOS);
    if (kDebugMode) {
      print(
          "[Window ${kWindowId ?? 'Main'}] change system window theme to ${theme.name}");
    }
    return _hostMethodChannel
        .invokeMethod("setWindowTheme", {"themeName": theme.name});
  }

  /// Terminate .app manually.
  Future<void> terminate() {
    return _hostMethodChannel.invokeMethod("terminate");
  }

  Future<void> configureDesktopRuntime(
    Map<String, dynamic> options,
    Future<void> Function(String action) onAction,
  ) async {
    _hostMethodChannel.setMethodCallHandler((call) async {
      if (call.method == 'desktopAction' && call.arguments is String) {
        await onAction(call.arguments as String);
      }
    });
    await _hostMethodChannel.invokeMethod('configureDesktopRuntime', options);
  }

  Future<LocalNetworkPermissionStatus> checkLocalNetworkPermission() async {
    assert(isMacOS);
    final status = await _hostMethodChannel.invokeMethod<String>(
      "checkLocalNetworkPermission",
    );
    return LocalNetworkPermissionStatus.values.firstWhere(
      (value) => value.name == status,
      orElse: () => LocalNetworkPermissionStatus.unknown,
    );
  }

  Future<bool> openLocalNetworkSettings() async {
    assert(isMacOS);
    return await _hostMethodChannel.invokeMethod<bool>(
          "openLocalNetworkSettings",
        ) ??
        false;
  }
}
