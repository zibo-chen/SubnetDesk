import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/model.dart';
import 'home_page.dart';

class SettingsPage extends StatefulWidget implements PageShape {
  @override
  final title = translate('Settings');

  @override
  final icon = const Icon(Icons.settings);

  @override
  final appBarActions = const <Widget>[];

  @override
  State<SettingsPage> createState() => _SettingsState();
}

enum KeepScreenOn { never, duringControlled, serviceOn }

KeepScreenOn optionToKeepScreenOn(String value) {
  switch (value) {
    case 'never':
      return KeepScreenOn.never;
    case 'service-on':
      return KeepScreenOn.serviceOn;
    default:
      return KeepScreenOn.duringControlled;
  }
}

class _SettingsState extends State<SettingsPage> {
  var _fingerprint = '';
  var _buildDate = '';
  var _preventSleepWhileConnected = true;
  var _showTerminalExtraKeys = false;

  @override
  void initState() {
    super.initState();
    _preventSleepWhileConnected = mainGetLocalBoolOptionSync(
      kOptionKeepAwakeDuringOutgoingSessions,
    );
    _showTerminalExtraKeys = mainGetLocalBoolOptionSync(
      kOptionEnableShowTerminalExtraKeys,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fingerprint = await bind.mainGetFingerprint();
      final buildDate = await bind.mainGetBuildDate();
      if (!mounted) return;
      setState(() {
        _fingerprint = fingerprint;
        _buildDate = buildDate;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return SettingsList(
      sections: [
        SettingsSection(
          title: const Text('LAN'),
          tiles: [
            SettingsTile(
              title: Text(translate('Network')),
              description: Text(
                '${translate('Username')} · ${translate('Local Address')} · ${translate('Port')}',
              ),
              leading: const Icon(Icons.lan),
              onPressed: (context) => showLanSettingsDialog(context),
            ),
          ],
        ),
        SettingsSection(
          title: Text(translate('Settings')),
          tiles: [
            SettingsTile(
              title: Text(translate('Language')),
              leading: const Icon(Icons.translate),
              onPressed: (context) => showLanguageSettings(gFFI.dialogManager),
            ),
            SettingsTile(
              title: Text(
                translate(
                  Theme.of(context).brightness == Brightness.light
                      ? 'Light Theme'
                      : 'Dark Theme',
                ),
              ),
              leading: Icon(
                Theme.of(context).brightness == Brightness.light
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              onPressed: (context) => showThemeSettings(gFFI.dialogManager),
            ),
            if (!bind.isIncomingOnly())
              SettingsTile.switchTile(
                title: Text(
                  translate('keep-awake-during-outgoing-sessions-label'),
                ),
                initialValue: _preventSleepWhileConnected,
                onToggle: (value) async {
                  await mainSetLocalBoolOption(
                    kOptionKeepAwakeDuringOutgoingSessions,
                    value,
                  );
                  if (mounted) {
                    setState(() => _preventSleepWhileConnected = value);
                  }
                },
              ),
            SettingsTile.switchTile(
              title: Text(translate('Show terminal extra keys')),
              initialValue: _showTerminalExtraKeys,
              onToggle: (value) async {
                await mainSetLocalBoolOption(
                  kOptionEnableShowTerminalExtraKeys,
                  value,
                );
                if (mounted) {
                  setState(() => _showTerminalExtraKeys = value);
                }
              },
            ),
          ],
        ),
        if (!bind.isIncomingOnly()) defaultDisplaySection(),
        SettingsSection(
          title: Text(translate('About')),
          tiles: [
            SettingsTile(
              title: Text('${translate('Version')}: $version'),
              leading: const Icon(Icons.info),
            ),
            SettingsTile(
              title: Text(translate('Build Date')),
              value: Text(_buildDate),
              leading: const Icon(Icons.query_builder),
            ),
            SettingsTile(
              title: Text(translate('Fingerprint')),
              value: SelectableText(_fingerprint),
              leading: const Icon(Icons.fingerprint),
            ),
          ],
        ),
      ],
    );
  }

  SettingsSection defaultDisplaySection() => SettingsSection(
        title: Text(translate('Display Settings')),
        tiles: [
          SettingsTile(
            title: Text(translate('Display Settings')),
            leading: const Icon(Icons.desktop_windows_outlined),
            trailing: const Icon(Icons.arrow_forward_ios),
            onPressed: (context) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DesktopSettingPage(
                  initialTabkey: SettingsTabKey.display,
                ),
              ),
            ),
          ),
        ],
      );
}

void showLanguageSettings(OverlayDialogManager dialogManager) async {
  try {
    final languages = json.decode(await bind.mainGetLangs()) as List<dynamic>;
    var language = bind.mainGetLocalOption(key: kCommConfKeyLang);
    dialogManager.show(
      (setState, close, context) {
        void setLanguage(String? value) async {
          if (value == null) return;
          if (language == value) return;
          setState(() => language = value);
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: value);
          HomePage.homeKey.currentState?.refreshPages();
          Future.delayed(const Duration(milliseconds: 200), close);
        }

        final onChanged = isOptionFixed(kCommConfKeyLang) ? null : setLanguage;
        return CustomAlertDialog(
          content: Column(
            children: [
              getRadio<String>(
                Text(translate('Default')),
                defaultOptionLang,
                language,
                onChanged,
              ),
              Divider(color: MyTheme.border),
              ...languages.map((entry) {
                final key = entry[0] as String;
                final name = entry[1] as String;
                return getRadio<String>(
                  Text(translate(name)),
                  key,
                  language,
                  onChanged,
                );
              }),
            ],
          ),
        );
      },
      backDismiss: true,
      clickMaskDismiss: true,
    );
  } catch (_) {}
}

void showThemeSettings(OverlayDialogManager dialogManager) async {
  var themeMode = MyTheme.getThemeModePreference();
  dialogManager.show(
    (setState, close, context) {
      void setTheme(ThemeMode? value) {
        if (value == null) return;
        if (themeMode == value) return;
        setState(() => themeMode = value);
        MyTheme.changeDarkMode(themeMode);
        Future.delayed(const Duration(milliseconds: 200), close);
      }

      final onChanged = isOptionFixed(kCommConfKeyTheme) ? null : setTheme;
      return CustomAlertDialog(
        content: Column(
          children: [
            getRadio<ThemeMode>(Text(translate('Light')), ThemeMode.light,
                themeMode, onChanged),
            getRadio<ThemeMode>(
                Text(translate('Dark')), ThemeMode.dark, themeMode, onChanged),
            getRadio<ThemeMode>(
              Text(translate('Follow System')),
              ThemeMode.system,
              themeMode,
              onChanged,
            ),
          ],
        ),
      );
    },
    backDismiss: true,
    clickMaskDismiss: true,
  );
}
