import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
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
  var _enableWebrtc = true;

  @override
  void initState() {
    super.initState();
    _preventSleepWhileConnected = mainGetLocalBoolOptionSync(
      kOptionKeepAwakeDuringOutgoingSessions,
    );
    _showTerminalExtraKeys = mainGetLocalBoolOptionSync(
      kOptionEnableShowTerminalExtraKeys,
    );
    _enableWebrtc = mainGetLocalBoolOptionSync(kOptionEnableWebrtc);
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
            if (!bind.isIncomingOnly())
              SettingsTile.switchTile(
                title: Text(translate('Enable WebRTC P2P connection')),
                initialValue: _enableWebrtc,
                onToggle: (value) async {
                  await mainSetLocalBoolOption(kOptionEnableWebrtc, value);
                  if (mounted) {
                    setState(() => _enableWebrtc = value);
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
                builder: (context) => const MobileDisplaySettingsPage(),
              ),
            ),
          ),
        ],
      );
}

class MobileDisplaySettingsPage extends StatefulWidget {
  const MobileDisplaySettingsPage({super.key});

  @override
  State<MobileDisplaySettingsPage> createState() =>
      _MobileDisplaySettingsPageState();
}

class _MobileDisplaySettingsPageState
    extends State<MobileDisplaySettingsPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    final codecList = [
      _RadioEntry('Auto', 'auto'),
      _RadioEntry('VP8', 'vp8'),
      _RadioEntry('VP9', 'vp9'),
      _RadioEntry('AV1', 'av1'),
      if (h264) _RadioEntry('H264', 'h264'),
      if (h265) _RadioEntry('H265', 'h265'),
    ];
    final showCustomImageQuality = false.obs;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios),
        ),
        title: Text(translate('Display Settings'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: SettingsList(sections: [
        SettingsSection(tiles: [
          _getPopupDialogRadioEntry(
            title: 'Default View Style',
            list: [
              _RadioEntry('Scale original', kRemoteViewStyleOriginal),
              _RadioEntry('Scale adaptive', kRemoteViewStyleAdaptive),
            ],
            getter: () =>
                bind.mainGetUserDefaultOption(key: kOptionViewStyle),
            asyncSetter: isOptionFixed(kOptionViewStyle)
                ? null
                : (value) => bind.mainSetUserDefaultOption(
                    key: kOptionViewStyle, value: value),
          ),
          _getPopupDialogRadioEntry(
            title: 'Default Image Quality',
            list: [
              _RadioEntry('Good image quality', kRemoteImageQualityBest),
              _RadioEntry('Balanced', kRemoteImageQualityBalanced),
              _RadioEntry('Optimize reaction time', kRemoteImageQualityLow),
              _RadioEntry('Custom', kRemoteImageQualityCustom),
            ],
            getter: () {
              final value =
                  bind.mainGetUserDefaultOption(key: kOptionImageQuality);
              showCustomImageQuality.value =
                  value == kRemoteImageQualityCustom;
              return value;
            },
            asyncSetter: isOptionFixed(kOptionImageQuality)
                ? null
                : (value) async {
                    await bind.mainSetUserDefaultOption(
                        key: kOptionImageQuality, value: value);
                    showCustomImageQuality.value =
                        value == kRemoteImageQualityCustom;
                  },
            tail: customImageQualitySetting(),
            showTail: showCustomImageQuality,
            notCloseValue: kRemoteImageQualityCustom,
          ),
          _getPopupDialogRadioEntry(
            title: 'Default Codec',
            list: codecList,
            getter: () =>
                bind.mainGetUserDefaultOption(key: kOptionCodecPreference),
            asyncSetter: isOptionFixed(kOptionCodecPreference)
                ? null
                : (value) => bind.mainSetUserDefaultOption(
                    key: kOptionCodecPreference, value: value),
          ),
        ]),
        SettingsSection(
          title: Text(translate('Other Default Options')),
          tiles: otherDefaultSettings()
              .map((entry) => _buildBooleanSetting(entry.$1, entry.$2))
              .toList(),
        ),
      ]),
    );
  }

  SettingsTile _buildBooleanSetting(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    return SettingsTile.switchTile(
      initialValue: value,
      title: Text(translate(label)),
      onToggle: isOptionFixed(key)
          ? null
          : (enabled) async {
              await bind.mainSetUserDefaultOption(
                  key: key, value: enabled ? 'Y' : defaultOptionNo);
              if (mounted) setState(() {});
            },
    );
  }
}

class _RadioEntry {
  const _RadioEntry(this.label, this.value);

  final String label;
  final String value;
}

typedef _RadioEntryGetter = String Function();
typedef _RadioEntrySetter = Future<void> Function(String);

SettingsTile _getPopupDialogRadioEntry({
  required String title,
  required List<_RadioEntry> list,
  required _RadioEntryGetter getter,
  required _RadioEntrySetter? asyncSetter,
  Widget? tail,
  RxBool? showTail,
  String? notCloseValue,
}) {
  final groupValue = getter().obs;
  final valueText =
      (list.firstWhereOrNull((entry) => entry.value == groupValue.value)?.label ??
              groupValue.value)
          .obs;

  void refreshValue() {
    groupValue.value = getter();
    valueText.value = list
            .firstWhereOrNull((entry) => entry.value == groupValue.value)
            ?.label ??
        groupValue.value;
  }

  void showSelectionDialog() {
    gFFI.dialogManager.show(
      (setState, close, context) => CustomAlertDialog(
        content: Obx(() => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...list.map((entry) => getRadio<String>(
                      Text(translate(entry.label)),
                      entry.value,
                      groupValue.value,
                      asyncSetter == null
                          ? null
                          : (value) async {
                              if (value == null) return;
                              await asyncSetter(value);
                              refreshValue();
                              if (value != notCloseValue) close();
                            },
                    )),
                if (tail != null && showTail != null)
                  Obx(() => Offstage(
                        offstage: !showTail.value,
                        child: tail,
                      )),
              ],
            )),
      ),
      backDismiss: true,
      clickMaskDismiss: true,
    );
  }

  return SettingsTile(
    title: Text(translate(title)),
    onPressed: asyncSetter == null ? null : (_) => showSelectionDialog(),
    value: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Obx(() => Text(translate(valueText.value),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    ),
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
