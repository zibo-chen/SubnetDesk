import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/printer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/manager.dart';
import 'package:flutter_hbb/plugin/widgets/desktop_settings.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common/widgets/dialog.dart';

const double _kTabWidth = 200;
const double _kTabHeight = 42;
const double _kCardFixedWidth = 540;
const double _kCardLeftMargin = 15;
const double _kContentHMargin = 15;
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kCheckBoxLeftMargin = 10;
const double _kRadioLeftMargin = 10;
const double _kListViewBottomMargin = 15;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _accentColor = MyTheme.accent;
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';

class _TabInfo {
  late final SettingsTabKey key;
  late final String label;
  late final IconData unselected;
  late final IconData selected;
  _TabInfo(this.key, this.label, this.unselected, this.selected);
}

enum SettingsTabKey { general, display, printer, about }

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;
  static final List<SettingsTabKey> tabKeys = [
    SettingsTabKey.general,
    if (!bind.isIncomingOnly()) SettingsTabKey.display,
    if (isWindows &&
        bind.mainGetBuildinOption(key: kOptionHideRemotePrinterSetting) != 'Y')
      SettingsTabKey.printer,
    SettingsTabKey.about,
  ];

  DesktopSettingPage({Key? key, required this.initialTabkey}) : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller = Get.find<PageController>(
          tag: _kSettingPageControllerTag,
        );
        Rx<SettingsTabKey> selected = Get.find<Rx<SettingsTabKey>>(
          tag: _kSettingPageTabKeyTag,
        );
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;

  _DesktopSettingPageState(SettingsTabKey initialTabkey) {
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
    controller = PageController(initialPage: initialIndex);
    Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoConnTimer = periodic_immediate(
      Duration(milliseconds: 1000),
      () async {
        if (!mounted) {
          return;
        }
        _canBeBlocked.value = await canBeBlocked();
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
    Get.delete<PageController>(tag: _kSettingPageControllerTag);
    Get.delete<RxInt>(tag: _kSettingPageTabKeyTag);
    WidgetsBinding.instance.removeObserver(this);
    _videoConnTimer?.cancel();
  }

  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          settingTabs.add(
            _TabInfo(tab, 'General', Icons.settings_outlined, Icons.settings),
          );
          break;
        case SettingsTabKey.display:
          settingTabs.add(
            _TabInfo(
              tab,
              'Display',
              Icons.desktop_windows_outlined,
              Icons.desktop_windows,
            ),
          );
          break;
        case SettingsTabKey.printer:
          settingTabs.add(
            _TabInfo(tab, 'Printer', Icons.print_outlined, Icons.print),
          );
          break;
        case SettingsTabKey.about:
          settingTabs.add(
            _TabInfo(tab, 'About', Icons.info_outline, Icons.info),
          );
          break;
      }
    }
    return settingTabs;
  }

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.printer:
          children.add(const _Printer());
          break;
        case SettingsTabKey.about:
          children.add(const _About());
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(
        children: [
          buildRemoteBlock(
            block: _block,
            mask: false,
            use: canBeBlocked,
            child: preventMouseKeyBuilder(
              child: Row(children: children),
              block: videoConnBlock,
            ),
          ),
          if (videoConnBlock) Container(color: Colors.black.withOpacity(0.5)),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: _buildBlock(
        children: <Widget>[
          SizedBox(
            width: _kTabWidth,
            child: Column(
              children: [
                _header(context),
                Flexible(child: _listView(tabs: _settingTabs())),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: PageView(
                controller: controller,
                physics: NeverScrollableScrollPhysics(),
                children: _children(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final settingsText = Text(
      translate('Settings'),
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: _accentColor,
        fontSize: _kTitleFontSize,
        fontWeight: FontWeight.w400,
      ),
    );
    return Row(
      children: [
        if (isWeb)
          IconButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            icon: Icon(Icons.arrow_back),
          ).marginOnly(left: 5),
        if (isWeb)
          SizedBox(
            height: 62,
            child: Align(alignment: Alignment.center, child: settingsText),
          ).marginOnly(left: 20),
        if (!isWeb)
          SizedBox(
            height: 62,
            child: settingsText,
          ).marginOnly(left: 20, top: 10),
        const Spacer(),
      ],
    );
  }

  Widget _listView({required List<_TabInfo> tabs}) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: tabs.map((tab) => _listItem(tab: tab)).toList(),
    );
  }

  Widget _listItem({required _TabInfo tab}) {
    return Obx(() {
      bool selected = tab.key == selectedTab.value;
      return SizedBox(
        width: _kTabWidth,
        height: _kTabHeight,
        child: InkWell(
          onTap: () {
            if (selectedTab.value != tab.key) {
              int index = DesktopSettingPage.tabKeys.indexOf(tab.key);
              if (index == -1) {
                return;
              }
              controller.jumpToPage(index);
            }
            selectedTab.value = tab.key;
          },
          child: Row(
            children: [
              Container(
                width: 4,
                height: _kTabHeight * 0.7,
                color: selected ? _accentColor : null,
              ),
              Icon(
                selected ? tab.selected : tab.unselected,
                color: selected ? _accentColor : null,
                size: 20,
              ).marginOnly(left: 13, right: 10),
              Text(
                translate(tab.label),
                style: TextStyle(
                  color: selected ? _accentColor : null,
                  fontWeight: FontWeight.w400,
                  fontSize: _kContentFontSize,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

//#region pages

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  final RxBool serviceStop = isWeb
      ? RxBool(false)
      : Get.find<RxBool>(tag: 'stop-service');
  RxBool serviceBtnEnabled = true.obs;
  final GlobalKey _minToolbarOptionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        if (!isWeb) service(),
        theme(),
        _Card(title: 'Language', children: [language()]),
        if (!isWeb) hwcodec(),
        if (!isWeb) audio(context),
        if (!isWeb) record(context),
        if (!isWeb) WaylandCard(),
        other(),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget theme() {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _Card(
      title: 'Theme',
      children: [
        _Radio<String>(
          context,
          value: 'light',
          groupValue: current,
          label: 'Light',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio<String>(
          context,
          value: 'dark',
          groupValue: current,
          label: 'Dark',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio<String>(
          context,
          value: 'system',
          groupValue: current,
          label: 'Follow System',
          onChanged: isOptFixed ? null : onChanged,
        ),
      ],
    );
  }

  Widget service() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    final hideStopService =
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';

    return Obx(() {
      if (hideStopService && !serviceStop.value) {
        return const Offstage();
      }

      return _Card(
        title: 'Service',
        children: [
          _Button(serviceStop.value ? 'Start' : 'Stop', () {
            () async {
              serviceBtnEnabled.value = false;
              await start_service(serviceStop.value);
              // enable the button after 1 second
              Future.delayed(const Duration(seconds: 1), () {
                serviceBtnEnabled.value = true;
              });
            }();
          }, enabled: serviceBtnEnabled.value),
        ],
      );
    });
  }

  Widget other() {
    final incomingOnly = bind.isIncomingOnly();
    final outgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isWeb && !incomingOnly)
        _OptionCheckBox(
          context,
          'Confirm before closing multiple tabs',
          kOptionEnableConfirmClosingTabs,
          isServer: false,
        ),
      if (!incomingOnly)
        _OptionCheckBox(
          context,
          'allow-remote-toolbar-docking-any-edge',
          kOptionAllowMultiEdgeToolbarDock,
          isServer: false,
          update: (_) {
            reloadAllWindows();
          },
        ),
      if (!isWeb && !outgoingOnly)
        _OptionCheckBox(context, 'Adaptive bitrate', kOptionEnableAbr),
      if (!isWeb) wallpaper(),
      if (!isWeb && !incomingOnly) ...[
        _OptionCheckBox(
          context,
          'Open connection in new tab',
          kOptionOpenNewConnInTabs,
          isServer: false,
        ),
        // though this is related to GUI, but opengl problem affects all users, so put in config rather than local
        if (isLinux)
          Tooltip(
            message: translate('software_render_tip'),
            child: _OptionCheckBox(
              context,
              "Always use software rendering",
              kOptionAllowAlwaysSoftwareRender,
            ),
          ),
        if (!isWeb)
          Tooltip(
            message: translate('texture_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use texture rendering",
              kOptionTextureRender,
              optGetter: bind.mainGetUseTextureRender,
              optSetter: (k, v) async =>
                  await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
            ),
          ),
        if (isWindows)
          Tooltip(
            message: translate('d3d_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use D3D rendering",
              kOptionD3DRender,
              isServer: false,
            ),
          ),
      ],
      if (isWindows && !outgoingOnly)
        _OptionCheckBox(
          context,
          'Capture screen using DirectX',
          kOptionDirectxCapture,
        ),
    ];

    // Add client-side wakelock option for desktop platforms
    if (!bind.isIncomingOnly()) {
      children.add(
        _OptionCheckBox(
          context,
          'keep-awake-during-outgoing-sessions-label',
          kOptionKeepAwakeDuringOutgoingSessions,
          isServer: false,
        ),
      );
    }

    if (!isWeb && bind.mainShowOption(key: kOptionAllowLinuxHeadless)) {
      children.add(
        _OptionCheckBox(
          context,
          'Allow linux headless',
          kOptionAllowLinuxHeadless,
        ),
      );
    }
    children.add(
      _OptionCheckBox(
        context,
        'Show monitor switch button on the main toolbar',
        kOptionAllowMonitorSwitchMainToolbar,
        isServer: false,
        update: (enabled) async {
          if (!enabled) {
            await mainSetLocalBoolOption(
              kOptionAllowMonitorSwitchMinToolbar,
              false,
            );
          }
          if (mounted) setState(() {});
          reloadAllWindows();
          if (enabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _minToolbarOptionKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              }
            });
          }
        },
      ),
    );
    if (mainGetLocalBoolOptionSync(kOptionAllowMonitorSwitchMainToolbar)) {
      children.add(
        KeyedSubtree(
          key: _minToolbarOptionKey,
          child: _OptionCheckBox(
            context,
            'Show on the minimized toolbar',
            kOptionAllowMonitorSwitchMinToolbar,
            isServer: false,
            update: (_) {
              reloadAllWindows();
            },
          ).marginOnly(left: _kCheckBoxLeftMargin * 3),
        ),
      );
    }
    return _Card(title: 'Other', children: children);
  }

  Widget wallpaper() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    return futureBuilder(
      future: () async {
        final support = await bind.mainSupportRemoveWallpaper();
        return support;
      }(),
      hasData: (data) {
        if (data is bool && data == true) {
          bool value = mainGetBoolOptionSync(kOptionAllowRemoveWallpaper);
          return Row(
            children: [
              Flexible(
                child: _OptionCheckBox(
                  context,
                  'Remove wallpaper during incoming sessions',
                  kOptionAllowRemoveWallpaper,
                  update: (bool v) {
                    setState(() {});
                  },
                ),
              ),
              if (value)
                _CountDownButton(
                  text: 'Test',
                  second: 5,
                  onPressed: () {
                    bind.mainTestWallpaper(second: 5);
                  },
                ),
            ],
          );
        }

        return Offstage();
      },
    );
  }

  Widget hwcodec() {
    final hwcodec = bind.mainHasHwcodec();
    final vram = bind.mainHasVram();
    return Offstage(
      offstage: !(hwcodec || vram),
      child: _Card(
        title: 'Hardware Codec',
        children: [
          _OptionCheckBox(
            context,
            'Enable hardware codec',
            kOptionEnableHwcodec,
            update: (bool v) {
              if (v) {
                bind.mainCheckHwcodec();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = ComboBox(
        keys: devices,
        values: devices,
        initialKey: currentDevice,
        onChanged: (key) async {
          setDevice(key);
          setState(() {});
        },
      ).marginOnly(left: _kContentHMargin);
      return _Card(title: 'Audio Input Device', children: [child]);
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget record(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(
      future: () async {
        String user_dir = bind.mainVideoSaveDirectory(root: false);
        String root_dir = showRootDir
            ? bind.mainVideoSaveDirectory(root: true)
            : '';
        bool user_dir_exists = await Directory(user_dir).exists();
        bool root_dir_exists = showRootDir
            ? await Directory(root_dir).exists()
            : false;
        return {
          'user_dir': user_dir,
          'root_dir': root_dir,
          'user_dir_exists': user_dir_exists,
          'root_dir_exists': root_dir_exists,
        };
      }(),
      hasData: (data) {
        Map<String, dynamic> map = data as Map<String, dynamic>;
        String user_dir = map['user_dir']!;
        String root_dir = map['root_dir']!;
        bool root_dir_exists = map['root_dir_exists']!;
        bool user_dir_exists = map['user_dir_exists']!;
        return _Card(
          title: 'Recording',
          children: [
            if (!bind.isOutgoingOnly())
              _OptionCheckBox(
                context,
                'Automatically record incoming sessions',
                kOptionAllowAutoRecordIncoming,
              ),
            if (!bind.isIncomingOnly())
              _OptionCheckBox(
                context,
                'Automatically record outgoing sessions',
                kOptionAllowAutoRecordOutgoing,
                isServer: false,
              ),
            if (showRootDir && !bind.isOutgoingOnly())
              Row(
                children: [
                  Text(
                    '${translate(bind.isIncomingOnly() ? "Directory" : "Incoming")}:',
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: root_dir_exists
                          ? () => launchUrl(Uri.file(root_dir))
                          : null,
                      child: Text(
                        root_dir,
                        softWrap: true,
                        style: root_dir_exists
                            ? const TextStyle(
                                decoration: TextDecoration.underline,
                              )
                            : null,
                      ),
                    ).marginOnly(left: 10),
                  ),
                ],
              ).marginOnly(left: _kContentHMargin),
            if (!(showRootDir && bind.isIncomingOnly()))
              Row(
                children: [
                  Text(
                    '${translate((showRootDir && !bind.isOutgoingOnly()) ? "Outgoing" : "Directory")}:',
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: user_dir_exists
                          ? () => launchUrl(Uri.file(user_dir))
                          : null,
                      child: Text(
                        user_dir,
                        softWrap: true,
                        style: user_dir_exists
                            ? const TextStyle(
                                decoration: TextDecoration.underline,
                              )
                            : null,
                      ),
                    ).marginOnly(left: 10),
                  ),
                  ElevatedButton(
                    onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                        ? null
                        : () async {
                            String? initialDirectory;
                            if (await Directory.fromUri(
                              Uri.directory(user_dir),
                            ).exists()) {
                              initialDirectory = user_dir;
                            }
                            String? selectedDirectory = await FilePicker
                                .platform
                                .getDirectoryPath(
                                  initialDirectory: initialDirectory,
                                );
                            if (selectedDirectory != null) {
                              await bind.mainSetLocalOption(
                                key: kOptionVideoSaveDirectory,
                                value: selectedDirectory,
                              );
                              setState(() {});
                            }
                          },
                    child: Text(translate('Change')),
                  ).marginOnly(left: 5),
                ],
              ).marginOnly(left: _kContentHMargin),
          ],
        );
      },
    );
  }

  Widget language() {
    return futureBuilder(
      future: () async {
        String langs = await bind.mainGetLangs();
        return {'langs': langs};
      }(),
      hasData: (res) {
        Map<String, String> data = res as Map<String, String>;
        List<dynamic> langsList = jsonDecode(data['langs']!);
        Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
        List<String> keys = langsMap.keys.toList();
        List<String> values = langsMap.values.toList();
        keys.insert(0, defaultOptionLang);
        values.insert(0, translate('Default'));
        String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
        if (!keys.contains(currentKey)) {
          currentKey = defaultOptionLang;
        }
        final isOptFixed = isOptionFixed(kCommConfKeyLang);
        return ComboBox(
          keys: keys,
          values: values,
          initialKey: currentKey,
          onChanged: (key) async {
            await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
            if (isWeb) reloadCurrentWindow();
            if (!isWeb) reloadAllWindows();
            if (!isWeb) bind.mainChangeLanguage(lang: key);
          },
          enabled: !isOptFixed,
        ).marginOnly(left: _kContentHMargin);
      },
    );
  }
}

enum _AccessMode { custom, full, view }

class _Display extends StatefulWidget {
  const _Display({Key? key}) : super(key: key);

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        viewStyle(context),
        scrollStyle(context),
        imageQuality(context),
        codec(context),
        if (isDesktop) trackpadSpeed(context),
        if (!isWeb) privacyModeImpl(context),
        other(context),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget viewStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionViewStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    return _Card(
      title: 'Default View Style',
      children: [
        _Radio(
          context,
          value: kRemoteViewStyleOriginal,
          groupValue: groupValue,
          label: 'Scale original',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: kRemoteViewStyleAdaptive,
          groupValue: groupValue,
          label: 'Scale adaptive',
          onChanged: isOptFixed ? null : onChanged,
        ),
      ],
    );
  }

  Widget scrollStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionScrollStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
        key: kOptionScrollStyle,
        value: value,
      );
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionScrollStyle);

    onEdgeScrollEdgeThicknessChanged(double value) async {
      await bind.mainSetUserDefaultOption(
        key: kOptionEdgeScrollEdgeThickness,
        value: value.round().toString(),
      );
      setState(() {});
    }

    return _Card(
      title: 'Default Scroll Style',
      children: [
        _Radio(
          context,
          value: kRemoteScrollStyleAuto,
          groupValue: groupValue,
          label: 'ScrollAuto',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: kRemoteScrollStyleBar,
          groupValue: groupValue,
          label: 'Scrollbar',
          onChanged: isOptFixed ? null : onChanged,
        ),
        if (!isWeb) ...[
          _Radio(
            context,
            value: kRemoteScrollStyleEdge,
            groupValue: groupValue,
            label: 'ScrollEdge',
            onChanged: isOptFixed ? null : onChanged,
          ),
          Offstage(
            offstage: groupValue != kRemoteScrollStyleEdge,
            child: EdgeThicknessControl(
              value:
                  double.tryParse(
                    bind.mainGetUserDefaultOption(
                      key: kOptionEdgeScrollEdgeThickness,
                    ),
                  ) ??
                  100.0,
              onChanged: isOptionFixed(kOptionEdgeScrollEdgeThickness)
                  ? null
                  : onEdgeScrollEdgeThicknessChanged,
            ),
          ),
        ],
      ],
    );
  }

  Widget imageQuality(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
        key: kOptionImageQuality,
        value: value,
      );
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kOptionImageQuality);
    final groupValue = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    return _Card(
      title: 'Default Image Quality',
      children: [
        _Radio(
          context,
          value: kRemoteImageQualityBest,
          groupValue: groupValue,
          label: 'Good image quality',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: kRemoteImageQualityBalanced,
          groupValue: groupValue,
          label: 'Balanced',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: kRemoteImageQualityLow,
          groupValue: groupValue,
          label: 'Optimize reaction time',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: kRemoteImageQualityCustom,
          groupValue: groupValue,
          label: 'Custom',
          onChanged: isOptFixed ? null : onChanged,
        ),
        Offstage(
          offstage: groupValue != kRemoteImageQualityCustom,
          child: customImageQualitySetting(),
        ),
      ],
    );
  }

  Widget trackpadSpeed(BuildContext context) {
    final initSpeed =
        (int.tryParse(bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
        kDefaultTrackpadSpeed);
    final curSpeed = SimpleWrapper(initSpeed);
    void onDebouncer(int v) {
      bind.mainSetUserDefaultOption(
        key: kKeyTrackpadSpeed,
        value: v.toString(),
      );
      // It's better to notify all sessions that the default speed is changed.
      // But it may also be ok to take effect in the next connection.
    }

    return _Card(
      title: 'Default trackpad speed',
      children: [
        TrackpadSpeedWidget(value: curSpeed, onDebouncer: onDebouncer),
      ],
    );
  }

  Widget codec(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
        key: kOptionCodecPreference,
        value: value,
      );
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(
      key: kOptionCodecPreference,
    );
    var hwRadios = [];
    final isOptFixed = isOptionFixed(kOptionCodecPreference);
    try {
      final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
      final h264 = codecsJson['h264'] ?? false;
      final h265 = codecsJson['h265'] ?? false;
      if (h264) {
        hwRadios.add(
          _Radio(
            context,
            value: 'h264',
            groupValue: groupValue,
            label: 'H264',
            onChanged: isOptFixed ? null : onChanged,
          ),
        );
      }
      if (h265) {
        hwRadios.add(
          _Radio(
            context,
            value: 'h265',
            groupValue: groupValue,
            label: 'H265',
            onChanged: isOptFixed ? null : onChanged,
          ),
        );
      }
    } catch (e) {
      debugPrint("failed to parse supported hwdecodings, err=$e");
    }
    return _Card(
      title: 'Default Codec',
      children: [
        _Radio(
          context,
          value: 'auto',
          groupValue: groupValue,
          label: 'Auto',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: 'vp8',
          groupValue: groupValue,
          label: 'VP8',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: 'vp9',
          groupValue: groupValue,
          label: 'VP9',
          onChanged: isOptFixed ? null : onChanged,
        ),
        _Radio(
          context,
          value: 'av1',
          groupValue: groupValue,
          label: 'AV1',
          onChanged: isOptFixed ? null : onChanged,
        ),
        ...hwRadios,
      ],
    );
  }

  Widget privacyModeImpl(BuildContext context) {
    final supportedPrivacyModeImpls = bind.mainSupportedPrivacyModeImpls();
    late final List<dynamic> privacyModeImpls;
    try {
      privacyModeImpls = jsonDecode(supportedPrivacyModeImpls);
    } catch (e) {
      debugPrint('failed to parse supported privacy mode impls, err=$e');
      return Offstage();
    }
    if (privacyModeImpls.length < 2) {
      return Offstage();
    }

    final key = 'privacy-mode-impl-key';
    onChanged(String value) async {
      await bind.mainSetOption(key: key, value: value);
      setState(() {});
    }

    String groupValue = bind.mainGetOptionSync(key: key);
    if (groupValue.isEmpty) {
      groupValue = bind.mainDefaultPrivacyModeImpl();
    }
    return _Card(
      title: 'Privacy mode',
      children: privacyModeImpls.map((impl) {
        final d = impl as List<dynamic>;
        return _Radio(
          context,
          value: d[0] as String,
          groupValue: groupValue,
          label: d[1] as String,
          onChanged: onChanged,
        );
      }).toList(),
    );
  }

  Widget otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    final isOptFixed = isOptionFixed(key);
    onChanged(bool b) async {
      await bind.mainSetUserDefaultOption(
        key: key,
        value: b
            ? 'Y'
            : (key == kOptionEnableFileCopyPaste ? 'N' : defaultOptionNo),
      );
      setState(() {});
    }

    return GestureDetector(
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: isOptFixed ? null : (_) => onChanged(!value),
          ).marginOnly(right: 5),
          Expanded(child: Text(translate(label))),
        ],
      ).marginOnly(left: _kCheckBoxLeftMargin),
      onTap: isOptFixed ? null : () => onChanged(!value),
    );
  }

  Widget other(BuildContext context) {
    final children = otherDefaultSettings()
        .map((e) => otherRow(e.$1, e.$2))
        .toList();
    return _Card(title: 'Other Default Options', children: children);
  }
}

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}

class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [outgoing(context), incoming(context)],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          translate('printer-requires-installed-{$appName}-client-tip'),
        ),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
        'install-printer-res',
        'install-printer-res',
        (evt) async {
          if (evt['success'] as bool) {
            setState(() {});
          } else {
            failedMsg.value = evt['msg'] as String;
          }
        },
        replace: true,
      );
      return Column(
        children: [
          Obx(
            () => failedMsg.value.isNotEmpty
                ? Offstage()
                : Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      translate('printer-{$appName}-not-installed-tip'),
                    ).marginOnly(bottom: 10.0),
                  ),
          ),
          Obx(
            () => failedMsg.value.isEmpty
                ? Offstage()
                : Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      failedMsg.value,
                      style: DefaultTextStyle.of(
                        context,
                      ).style.copyWith(color: Colors.red),
                    ).marginOnly(bottom: 10.0),
                  ),
          ),
          _Button('Install {$appName} Printer', () {
            failedMsg.value = '';
            bind.mainSetCommon(key: 'install-printer', value: '');
          }),
        ],
      ).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady(),
      ]);
    }
    return _Card(title: 'Outgoing Print Jobs', children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
        key: kKeyPrinterIncomingJobAction,
        value: value,
      );
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(
      title: 'Incoming Print Jobs',
      children: [
        _Radio(
          context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: 'Dismiss',
          onChanged: onRadioChanged,
        ),
        _Radio(
          context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: 'use-the-default-printer-tip',
          onChanged: onRadioChanged,
        ),
        _Radio(
          context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: 'use-the-selected-printer-tip',
          onChanged: onRadioChanged,
        ),
        if (printerOptions.printerNames.isNotEmpty)
          ComboBox(
            initialKey: printerOptions.printerName,
            keys: printerOptions.printerNames,
            values: printerOptions.printerNames,
            enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
            onChanged: (value) async {
              await bind.mainSetLocalOption(
                key: kKeyPrinterSelected,
                value: value,
              );
              setState(() {});
            },
          ).marginOnly(left: 10),
        _OptionCheckBox(
          context,
          'auto-print-tip',
          kKeyPrinterAllowAutoPrint,
          isServer: false,
          enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
        ),
      ],
    );
  }
}

class _About extends StatefulWidget {
  const _About({Key? key}) : super(key: key);

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: () async {
        final version = await bind.mainGetVersion();
        final buildDate = await bind.mainGetBuildDate();
        final fingerprint = await bind.mainGetFingerprint();
        return {
          'version': version,
          'buildDate': buildDate,
          'fingerprint': fingerprint,
        };
      }(),
      hasData: (data) {
        final version = data['version'].toString();
        final buildDate = data['buildDate'].toString();
        final fingerprint = data['fingerprint'].toString();
        final scrollController = ScrollController();
        return SingleChildScrollView(
          controller: scrollController,
          child: _Card(
            title: translate('About RustDesk'),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8.0),
                  SelectionArea(
                    child: Text(
                      '${translate('Version')}: $version',
                    ).marginSymmetric(vertical: 4.0),
                  ),
                  SelectionArea(
                    child: Text(
                      '${translate('Build Date')}: $buildDate',
                    ).marginSymmetric(vertical: 4.0),
                  ),
                  if (!isWeb)
                    SelectionArea(
                      child: Text(
                        '${translate('Fingerprint')}: $fingerprint',
                      ).marginSymmetric(vertical: 4.0),
                    ),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFF2c8cff)),
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 8,
                    ),
                    child: SelectionArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Copyright © ${DateTime.now().toString().substring(0, 4)} Purslane Tech Pte. Ltd.',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Text(
                                  translate('Slogan_tip'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).marginSymmetric(vertical: 4.0),
                ],
              ).marginOnly(left: _kContentHMargin),
            ],
          ),
        );
      },
    );
  }
}

//#endregion

//#region components

// ignore: non_constant_identifier_names
Widget _Card({
  required String title,
  required List<Widget> children,
  List<Widget>? title_suffix,
}) {
  return Row(
    children: [
      Flexible(
        child: SizedBox(
          width: _kCardFixedWidth,
          child: Card(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        translate(title),
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontSize: _kTitleFontSize),
                      ),
                    ),
                    ...?title_suffix,
                  ],
                ).marginOnly(left: _kContentHMargin, top: 10, bottom: 10),
                ...children.map(
                  (e) => e.marginOnly(top: 4, right: _kContentHMargin),
                ),
              ],
            ).marginOnly(bottom: 10),
          ).marginOnly(left: _kCardLeftMargin, top: 15),
        ),
      ),
    ],
  );
}

// ignore: non_constant_identifier_names
Widget _OptionCheckBox(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  Icon? checkedIcon,
  bool? fakeValue,
  bool isServer = true,
  bool Function()? optGetter,
  Future<void> Function(String, bool)? optSetter,
}) {
  getOpt() => optGetter != null
      ? optGetter()
      : (isServer
            ? mainGetBoolOptionSync(key)
            : mainGetLocalBoolOptionSync(key));
  bool value = getOpt();
  final isOptFixed = isOptionFixed(key);
  if (reverse) value = !value;
  var ref = value.obs;
  onChanged(option) async {
    if (option != null) {
      if (reverse) option = !option;
      final setter =
          optSetter ?? (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
      await setter(key, option);
      final readOption = getOpt();
      if (reverse) {
        ref.value = !readOption;
      } else {
        ref.value = readOption;
      }
      update?.call(readOption);
    }
  }

  if (fakeValue != null) {
    ref.value = fakeValue;
    enabled = false;
  }

  return GestureDetector(
    child: Obx(
      () => Row(
        children: [
          Checkbox(
            value: ref.value,
            onChanged: enabled && !isOptFixed ? onChanged : null,
          ).marginOnly(right: 5),
          Offstage(
            offstage: !ref.value || checkedIcon == null,
            child: checkedIcon?.marginOnly(right: 5),
          ),
          Expanded(
            child: Text(
              translate(label),
              style: TextStyle(color: disabledTextColor(context, enabled)),
            ),
          ),
        ],
      ),
    ).marginOnly(left: _kCheckBoxLeftMargin),
    onTap: enabled && !isOptFixed
        ? () {
            onChanged(!ref.value);
          }
        : null,
  );
}

// ignore: non_constant_identifier_names
Widget _Radio<T>(
  BuildContext context, {
  required T value,
  required T groupValue,
  required String label,
  required Function(T value)? onChanged,
  bool autoNewLine = true,
}) {
  final onChange2 = onChanged != null
      ? (T? value) {
          if (value != null) {
            onChanged(value);
          }
        }
      : null;
  return GestureDetector(
    child: Row(
      children: [
        Radio<T>(value: value, groupValue: groupValue, onChanged: onChange2),
        Expanded(
          child: Text(
            translate(label),
            overflow: autoNewLine ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kContentFontSize,
              color: disabledTextColor(context, onChange2 != null),
            ),
          ).marginOnly(left: 5),
        ),
      ],
    ).marginOnly(left: _kRadioLeftMargin),
    onTap: () => onChange2?.call(value),
  );
}

class WaylandCard extends StatefulWidget {
  const WaylandCard({Key? key}) : super(key: key);

  @override
  State<WaylandCard> createState() => _WaylandCardState();
}

class _WaylandCardState extends State<WaylandCard> {
  final restoreTokenKey = 'wayland-restore-token';
  static const _kClearShortcutsInhibitorEventKey =
      'clear-gnome-shortcuts-inhibitor-permission-res';
  final _clearShortcutsInhibitorFailedMsg = ''.obs;
  // Don't show the shortcuts permission reset button for now.
  // Users can change it manually:
  //   "Settings" -> "Apps" -> "SubnetDesk" -> "Permissions" -> "Inhibit Shortcuts".
  // For resetting(clearing) the permission from the portal permission store, you can
  // use (replace <desktop-id> with the SubnetDesk desktop file ID):
  //   busctl --user call org.freedesktop.impl.portal.PermissionStore \
  //   /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore \
  //   DeletePermission sss "gnome" "shortcuts-inhibitor" "<desktop-id>"
  // On a native install this is typically "rustdesk.desktop"; on Flatpak it is usually
  // the exported desktop ID derived from the Flatpak app-id (e.g. "com.zibochen.SubnetDesk.desktop").
  //
  // We may add it back in the future if needed.
  final showResetInhibitorPermission = false;

  @override
  void initState() {
    super.initState();
    if (showResetInhibitorPermission) {
      platformFFI.registerEventHandler(
        _kClearShortcutsInhibitorEventKey,
        _kClearShortcutsInhibitorEventKey,
        (evt) async {
          if (!mounted) return;
          if (evt['success'] == true) {
            setState(() {});
          } else {
            _clearShortcutsInhibitorFailedMsg.value =
                evt['msg'] as String? ?? 'Unknown error';
          }
        },
      );
    }
  }

  @override
  void dispose() {
    if (showResetInhibitorPermission) {
      platformFFI.unregisterEventHandler(
        _kClearShortcutsInhibitorEventKey,
        _kClearShortcutsInhibitorEventKey,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: bind.mainHandleWaylandScreencastRestoreToken(
        key: restoreTokenKey,
        value: "get",
      ),
      hasData: (restoreToken) {
        final hasShortcutsPermission =
            showResetInhibitorPermission &&
            bind.mainGetCommonSync(
                  key: "has-gnome-shortcuts-inhibitor-permission",
                ) ==
                "true";

        final children = [
          if (restoreToken.isNotEmpty)
            _buildClearScreenSelection(context, restoreToken),
          if (hasShortcutsPermission)
            _buildClearShortcutsInhibitorPermission(context),
        ];
        return Offstage(
          offstage: children.isEmpty,
          child: _Card(title: 'Wayland', children: children),
        );
      },
    );
  }

  Widget _buildClearScreenSelection(BuildContext context, String restoreToken) {
    onConfirm() async {
      final msg = await bind.mainHandleWaylandScreencastRestoreToken(
        key: restoreTokenKey,
        value: "clear",
      );
      gFFI.dialogManager.dismissAll();
      if (msg.isNotEmpty) {
        msgBox(
          gFFI.sessionId,
          'custom-nocancel',
          'Error',
          msg,
          '',
          gFFI.dialogManager,
        );
      } else {
        setState(() {});
      }
    }

    showConfirmMsgBox() => msgBoxCommon(
      gFFI.dialogManager,
      'Confirmation',
      Text(translate('confirm_clear_Wayland_screen_selection_tip')),
      [
        dialogButton('OK', onPressed: onConfirm),
        dialogButton(
          'Cancel',
          onPressed: () => gFFI.dialogManager.dismissAll(),
        ),
      ],
    );

    return _Button(
      'Clear Wayland screen selection',
      showConfirmMsgBox,
      tip: 'clear_Wayland_screen_selection_tip',
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all<Color>(
          Theme.of(context).colorScheme.error.withOpacity(0.75),
        ),
      ),
    );
  }

  Widget _buildClearShortcutsInhibitorPermission(BuildContext context) {
    onConfirm() {
      _clearShortcutsInhibitorFailedMsg.value = '';
      bind.mainSetCommon(
        key: "clear-gnome-shortcuts-inhibitor-permission",
        value: "",
      );
      gFFI.dialogManager.dismissAll();
    }

    showConfirmMsgBox() => msgBoxCommon(
      gFFI.dialogManager,
      'Confirmation',
      Text(translate('confirm-clear-shortcuts-inhibitor-permission-tip')),
      [
        dialogButton('OK', onPressed: onConfirm),
        dialogButton(
          'Cancel',
          onPressed: () => gFFI.dialogManager.dismissAll(),
        ),
      ],
    );

    return Column(
      children: [
        Obx(
          () => _clearShortcutsInhibitorFailedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    _clearShortcutsInhibitorFailedMsg.value,
                    style: DefaultTextStyle.of(
                      context,
                    ).style.copyWith(color: Colors.red),
                  ).marginOnly(bottom: 10.0),
                ),
        ),
        _Button(
          'Reset keyboard shortcuts permission',
          showConfirmMsgBox,
          tip: 'clear-shortcuts-inhibitor-permission-tip',
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all<Color>(
              Theme.of(context).colorScheme.error.withOpacity(0.75),
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: non_constant_identifier_names
Widget _Button(
  String label,
  Function() onPressed, {
  bool enabled = true,
  String? tip,
  ButtonStyle? style,
}) {
  var button = ElevatedButton(
    onPressed: enabled ? onPressed : null,
    child: Text(translate(label)).marginSymmetric(horizontal: 15),
    style: style,
  );
  StatefulWidget child;
  if (tip == null) {
    child = button;
  } else {
    child = Tooltip(message: translate(tip), child: button);
  }
  return Row(children: [child]).marginOnly(left: _kContentHMargin);
}

// ignore: non_constant_identifier_names
Widget _SubButton(String label, Function() onPressed, [bool enabled = true]) {
  return Row(
    children: [
      ElevatedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(translate(label)).marginSymmetric(horizontal: 15),
      ),
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

// ignore: non_constant_identifier_names
Widget _SubLabeledWidget(
  BuildContext context,
  String label,
  Widget child, {
  bool enabled = true,
}) {
  return Row(
    children: [
      Text(
        '${translate(label)}: ',
        style: TextStyle(color: disabledTextColor(context, enabled)),
      ),
      SizedBox(width: 10),
      child,
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

Widget _lock(bool locked, String label, Function() onUnlock) {
  return Offstage(
    offstage: !locked,
    child: Row(
      children: [
        Flexible(
          child: SizedBox(
            width: _kCardFixedWidth,
            child: Card(
              child: ElevatedButton(
                child: SizedBox(
                  height: 25,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.security_sharp, size: 20),
                      Text(translate(label)).marginOnly(left: 5),
                    ],
                  ).marginSymmetric(vertical: 2),
                ),
                onPressed: () async {
                  final unlockPin = bind.mainGetUnlockPin();
                  if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                    bool checked = await callMainCheckSuperUserPermission();
                    if (checked) {
                      onUnlock();
                    }
                  } else {
                    checkUnlockPinDialog(unlockPin, onUnlock);
                  }
                },
              ).marginSymmetric(horizontal: 2, vertical: 4),
            ).marginOnly(left: _kCardLeftMargin),
          ).marginOnly(top: 10),
        ),
      ],
    ),
  );
}

_LabeledTextField(
  BuildContext context,
  String label,
  TextEditingController controller,
  String errorText,
  bool enabled,
  bool secure,
) {
  return Table(
    columnWidths: const {0: FixedColumnWidth(150), 1: FlexColumnWidth()},
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${translate(label)}:',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: disabledTextColor(context, enabled),
              ),
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: secure,
            autocorrect: false,
            decoration: InputDecoration(
              errorText: errorText.isNotEmpty ? errorText : null,
            ),
            style: TextStyle(color: disabledTextColor(context, enabled)),
          ).workaroundFreezeLinuxMint(),
        ],
      ),
    ],
  ).marginOnly(bottom: 8);
}

class _CountDownButton extends StatefulWidget {
  _CountDownButton({
    Key? key,
    required this.text,
    required this.second,
    required this.onPressed,
  }) : super(key: key);
  final String text;
  final VoidCallback? onPressed;
  final int second;

  @override
  State<_CountDownButton> createState() => _CountDownButtonState();
}

class _CountDownButtonState extends State<_CountDownButton> {
  bool _isButtonDisabled = false;

  late int _countdownSeconds = widget.second;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isButtonDisabled
          ? null
          : () {
              widget.onPressed?.call();
              setState(() {
                _isButtonDisabled = true;
                _countdownSeconds = widget.second;
              });
              _startCountdownTimer();
            },
      child: Text(
        _isButtonDisabled ? '$_countdownSeconds s' : translate(widget.text),
      ),
    );
  }
}

//#endregion

//#region dialogs
