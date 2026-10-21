import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import 'app_language.dart';
import '../consts.dart';
import '../desktop/pages/desktop_setting_page.dart';
import '../models/platform_model.dart';
import '../utils/multi_window_manager.dart';
import '../utils/platform_channel.dart';

Map<String, dynamic> _runtimeState = const {};

// Settings builds read the last snapshot. Filesystem and platform account checks
// must run on the bridge worker pool, not on the Flutter UI isolate.
Map<String, dynamic> desktopRuntimeState() => _runtimeState;

Future<Map<String, dynamic>> _refreshDesktopRuntimeState() async {
  final value = await bind.mainGetOption(key: 'desktop-runtime');
  _runtimeState = value.isEmpty ? {} : jsonDecode(value) as Map<String, dynamic>;
  return _runtimeState;
}

Future<String> setDesktopAutostart(bool enabled) async {
  await bind.mainSetLocalOption(
    key: 'start-on-boot',
    value: enabled ? 'Y' : 'N',
  );
  final state = await _refreshDesktopRuntimeState();
  return state['error'] as String? ?? '';
}

Timer? _trayTimer;
bool _updatingTray = false;
String _lastTrayOptions = '';
bool _trayUnavailableReported = false;

Future<void> _handleDesktopAction(String action) async {
  switch (action) {
    case 'open':
    case 'settings':
      await windowManager.show();
      await windowManager.focus();
      await rustDeskWinManager.registerActiveWindow(kMainWindowId);
      if (action == 'settings') {
        DesktopSettingPage.switch2page(SettingsTabKey.general);
      }
      break;
    case 'sharing':
      await start_service(bind.mainGetOptionSync(key: 'stop-service') == 'Y');
      break;
    case 'autostart':
      final state = await _refreshDesktopRuntimeState();
      final error = await setDesktopAutostart(state['autostart'] != true);
      if (error.isNotEmpty) {
        await windowManager.show();
        BotToast.showText(text: error);
      }
      break;
    case 'data':
      final state = await _refreshDesktopRuntimeState();
      final path = state['data_dir'] as String?;
      if (path != null && path.isNotEmpty) await launchUrl(Uri.directory(path));
      break;
    case 'quit':
      _trayTimer?.cancel();
      await quitDesktopApp();
      break;
  }
}

Future<void> initializeDesktopRuntime() async {
  if (!isDesktop) return;
  Future<void> update() async {
    if (_updatingTray) return;
    _updatingTray = true;
    try {
      final state = await _refreshDesktopRuntimeState();
      final sharing = bind.mainGetOptionSync(key: 'stop-service') != 'Y';
      final language = bind.mainGetLocalOption(key: kCommConfKeyLang);
      final effectiveLanguage = resolveAppLanguage(language, localeName);
      String text(String english, String chineseText, String traditional) =>
          appText(
            effectiveLanguage,
            chineseText,
            english,
            traditional: traditional,
            translate: translate,
          );
      final status = !sharing
          ? text('Remote access is off', '远程访问已关闭', '遠端存取已關閉')
          : state['configured'] != true
          ? text('Set an access password first', '请先设置访问密码', '請先設定存取密碼')
          : state['listening'] == true
          ? text('Ready for remote connections', '可接收远程连接', '可接受遠端連線')
          : text('Remote access is not ready', '远程访问尚未就绪', '遠端存取尚未就緒');
      final options = {
        'openLabel': '${text('Open', '打开', '開啟')} SubnetDesk',
        'settingsLabel': '${text('Settings', '设置', '設定')}…',
        'sharingLabel': text('Allow remote access', '允许远程访问', '允許遠端存取'),
        'autostartLabel': text('Start at login', '登录时自动启动', '登入時自動啟動'),
        'dataLabel': text('Open data folder', '打开数据文件夹', '開啟資料夾'),
        'quitLabel': '${text('Quit', '退出', '結束')} SubnetDesk',
        'sharing': sharing,
        'autostart': state['autostart'] == true,
        'status': 'SubnetDesk — $status',
      };
      final serialized = jsonEncode(options);
      if (serialized == _lastTrayOptions && desktopTrayAvailable) return;
      await RdPlatformChannel.instance.configureDesktopRuntime(
        options,
        _handleDesktopAction,
      );
      _lastTrayOptions = serialized;
      desktopTrayAvailable = true;
      _trayUnavailableReported = false;
    } catch (error, stack) {
      desktopTrayAvailable = false;
      if (!_trayUnavailableReported) {
        _trayUnavailableReported = true;
        debugPrint('Desktop tray failed: $error\n$stack');
        await windowManager.show();
      }
    } finally {
      _updatingTray = false;
    }
  }

  await update();
  _trayTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => update());
}
