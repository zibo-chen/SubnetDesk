import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/favorite_group_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'dart:convert';
import '../../desktop/host_access_state.dart';
import '../../desktop/widgets/host_access_controls.dart';

import 'peer_card.dart';
import 'device_art.dart';
import 'subnet_ui.dart';

enum LanTool { desktop, files, terminal, camera }

class WorkspaceDevice {
  const WorkspaceDevice({
    required this.id,
    required this.name,
    this.platform = '',
    this.deviceType = '',
    this.hostname = '',
    this.online,
    this.fingerprint = '',
  });
  final String id;
  final String name;
  final String platform;
  final String deviceType, hostname;
  final bool? online;
  final String fingerprint;

  String get displayAddress {
    final match = RegExp(r'^([^:]+|\[[^\]]+\]):21118$').firstMatch(id);
    return match?.group(1) ?? id;
  }

  String get displayName => name == id ? displayAddress : name;

  DeviceKind get kind => resolveDeviceKind(
    deviceType: deviceType,
    platform: platform,
    hostname: hostname,
  );

  factory WorkspaceDevice.fromPeer(Peer peer) => WorkspaceDevice(
    id: peer.id,
    name: peer.alias.isNotEmpty
        ? peer.alias
        : peer.hostname.isNotEmpty
        ? peer.hostname
        : peer.id,
    platform: peer.platform,
    deviceType: peer.deviceType,
    hostname: peer.hostname,
    online: peer.online,
    fingerprint: peer.fingerprint,
  );
}

/// The live adapter keeps discovery and connections in the existing LAN stack.
class LanWorkspacePage extends StatefulWidget {
  const LanWorkspacePage({
    super.key,
    required this.onSettings,
    this.localPane,
    this.mobile = false,
    this.onNavigationChanged,
  });
  final VoidCallback onSettings;
  final Widget? localPane;
  final bool mobile;
  final ValueChanged<int>? onNavigationChanged;

  @override
  State<LanWorkspacePage> createState() => _LanWorkspacePageState();
}

class _LanWorkspacePageState extends State<LanWorkspacePage>
    with WidgetsBindingObserver, WindowListener {
  Timer? _timer;
  late final Listenable _updates;
  bool _resumed = true;
  HostAccessState _hostAccess = const HostAccessState();
  Future<void>? _hostRefresh;
  bool _changingHostAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isDesktop) windowManager.addListener(this);
    favoriteGroupModel.load();
    _updates = Listenable.merge([
      gFFI.lanPeersModel,
      gFFI.recentPeersModel,
      gFFI.favoritePeersModel,
      favoriteGroupModel,
    ]);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_resumed) _refresh();
    });
  }

  void _refresh() {
    if (!widget.mobile && !bind.isOutgoingOnly()) {
      _refreshHostAccess();
    }
    if (bind.isIncomingOnly()) return;
    bind.mainLoadLanPeers();
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
    bind.mainDiscover();
  }

  Future<void> _refreshHostAccess() => _hostRefresh ??= _readHostAccess()
      .whenComplete(() => _hostRefresh = null);

  Future<void> _readHostAccess() async {
    try {
      final info = jsonDecode(await bind.mainGetLanServerInfo()) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _hostAccess = HostAccessState.fromInfo(
            info, busy: _changingHostAccess));
      }
    } catch (error) {
      debugPrint('Reading local access failed: $error');
      if (mounted) {
        setState(() => _hostAccess = const HostAccessState());
      }
    }
  }

  Future<bool> _changeHostAccess(bool enabled, {bool discovery = false}) async {
    if (_changingHostAccess) return true;
    _changingHostAccess = true;
    try {
      await _refreshHostAccess();
      if (!mounted) return true;
      if (_hostAccess.loading) throw StateError('Host status is unavailable');
      if (!discovery && enabled && !_hostAccess.canEnableRemote) return false;
      if (discovery) {
        await bind.mainSetOption(key: kOptionEnableLanDiscovery, value: enabled ? 'Y' : 'N');
      } else {
        await start_service(enabled);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshHostAccess();
      return true;
    } catch (error) {
      debugPrint('Updating local access failed: $error');
      if (mounted) {
        showToast(subnetText(context, '无法更新本机接入状态，请重试',
            'Could not update local access. Try again.'));
      }
      return true;
    } finally {
      _changingHostAccess = false;
      if (mounted) await _refreshHostAccess();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (isDesktop) windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  void _connect(WorkspaceDevice device, LanTool tool) {
    if (bind.isIncomingOnly()) return;
    final candidates = [
      ...gFFI.lanPeersModel.peers,
      ...gFFI.recentPeersModel.peers,
      ...gFFI.favoritePeersModel.peers,
    ];
    final matches = candidates.where((peer) => peer.id == device.id);
    if (matches.isEmpty) {
      connect(
        context,
        device.id,
        isFileTransfer: tool == LanTool.files,
        isTerminal: tool == LanTool.terminal,
        isViewCamera: tool == LanTool.camera,
      );
    } else {
      connectInPeerTab(
        context,
        matches.first,
        PeerTabIndex.lan,
        isFileTransfer: tool == LanTool.files,
        isTerminal: tool == LanTool.terminal,
        isViewCamera: tool == LanTool.camera,
      );
    }
  }

  Future<void> _favorite(WorkspaceDevice device) async {
    try {
      final ids = (await bind.mainGetFav()).toSet();
      if (!ids.remove(device.id)) ids.add(device.id);
      await bind.mainStoreFav(favs: ids.toList());
      if (!ids.contains(device.id)) favoriteGroupModel.removePeer(device.id);
      await bind.mainLoadFavPeers();
    } catch (error) {
      debugPrint('Updating favorite failed: $error');
      if (mounted)
        showToast(
          subnetText(
            context,
            '无法保存收藏，请重试',
            'Could not save favorites. Try again.',
          ),
        );
    }
  }

  @override
  void onWindowFocus() => _refresh();

  @override
  void onWindowEnterFullScreen() => stateGlobal.resizeEdgeSize.value = 0;

  @override
  void onWindowLeaveFullScreen() => stateGlobal.resizeEdgeSize.value =
      stateGlobal.isMaximized.value ? kMaximizeEdgeSize : windowResizeEdgeSize;

  @override
  void onWindowClose() => bind.mainOnMainWindowClose();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _updates,
    builder: (context, _) => LanWorkspace(
      mobile: widget.mobile,
      incomingOnly: bind.isIncomingOnly(),
      nearby: gFFI.lanPeersModel.peers.map(WorkspaceDevice.fromPeer).toList(),
      recent: gFFI.recentPeersModel.peers
          .map(WorkspaceDevice.fromPeer)
          .toList(),
      favorites: gFFI.favoritePeersModel.peers
          .map(WorkspaceDevice.fromPeer)
          .toList(),
      groups: favoriteGroupModel.groups,
      groupFor: favoriteGroupModel.groupIdForPeer,
      onAssignGroup: favoriteGroupModel.setPeerGroup,
      onCreateGroup: favoriteGroupModel.createGroup,
      onRenameGroup: favoriteGroupModel.renameGroup,
      onDeleteGroup: favoriteGroupModel.deleteGroup,
      onConnect: _connect,
      onFavorite: _favorite,
      onRefresh: _refresh,
      onSettings: widget.onSettings,
      onNavigationChanged: widget.onNavigationChanged,
      localPane: widget.localPane,
      hostAccess: widget.mobile || bind.isOutgoingOnly() ? null : _hostAccess,
      hostPermissionLabel: isMacOS
          ? subnetText(context, '授予辅助功能与屏幕录制权限', 'Allow accessibility and screen recording')
          : isWindows
          ? subnetText(context, '授予管理员权限', 'Allow administrator access')
          : isLinux && bind.mainCurrentIsWayland()
          ? subnetText(context, '授予 Wayland 录屏与输入控制权限', 'Allow Wayland screen sharing and input control')
          : subnetText(context, '检查系统接入权限', 'Check system access permissions'),
      onDiscoveryChanged: (value) async { await _changeHostAccess(value, discovery: true); },
      onRemoteChanged: _changeHostAccess,
    ),
  );
}

/// Presentation is independent of FFI so narrow layouts and empty states can be tested.
class LanWorkspace extends StatefulWidget {
  const LanWorkspace({
    super.key,
    required this.nearby,
    required this.recent,
    required this.favorites,
    required this.onConnect,
    required this.onFavorite,
    required this.onRefresh,
    required this.onSettings,
    this.mobile = false,
    this.incomingOnly = false,
    this.localPane,
    this.groups = const [],
    this.groupFor,
    this.onAssignGroup,
    this.onCreateGroup,
    this.onRenameGroup,
    this.onDeleteGroup,
    this.onNavigationChanged,
    this.hostAccess,
    this.hostPermissionLabel = '',
    this.onDiscoveryChanged,
    this.onRemoteChanged,
  });
  final List<WorkspaceDevice> nearby, recent, favorites;
  final void Function(WorkspaceDevice, LanTool) onConnect;
  final ValueChanged<WorkspaceDevice> onFavorite;
  final VoidCallback onRefresh, onSettings;
  final bool mobile;
  final bool incomingOnly;
  final Widget? localPane;
  final List<FavoriteGroup> groups;
  final String? Function(String)? groupFor;
  final void Function(String, String?)? onAssignGroup;
  final bool Function(String)? onCreateGroup, onDeleteGroup;
  final bool Function(String, String)? onRenameGroup;
  final ValueChanged<int>? onNavigationChanged;
  final HostAccessState? hostAccess;
  final String hostPermissionLabel;
  final Future<void> Function(bool)? onDiscoveryChanged;
  final Future<bool> Function(bool)? onRemoteChanged;

  @override
  State<LanWorkspace> createState() => _LanWorkspaceState();
}

class _LanWorkspaceState extends State<LanWorkspace> {
  int _navigation = 0;
  int _filter = 0;
  String? _group;
  WorkspaceDevice? _detail;
  final _deviceListScroll = ScrollController();

  String t(String zh, String en) => subnetText(context, zh, en);
  bool get _isFavorite => _filter == 1;
  Set<String> get _favoriteIds => widget.favorites.map((d) => d.id).toSet();

  @override
  void initState() {
    super.initState();
    if (widget.incomingOnly) _navigation = 2;
  }

  @override
  void didUpdateWidget(covariant LanWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.incomingOnly && !oldWidget.incomingOnly) {
      _navigation = 2;
      _detail = null;
    }
  }

  void _back() {
    if (_detail != null) {
      setState(() => _detail = null);
    } else {
      _navigate(widget.incomingOnly ? 2 : 0);
    }
  }

  @override
  void dispose() {
    _deviceListScroll.dispose();
    super.dispose();
  }

  void _navigate(int index, {int filter = 2}) {
    setState(() {
      _navigation = index;
      _detail = null;
      if (index == 1) {
        _filter = filter;
        _group = null;
      }
    });
    widget.onNavigationChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.mobile) return _workspace();
      if (constraints.biggest.isEmpty) return const SizedBox.shrink();
      // Scale the desktop composition uniformly, including its hit targets.
      // 612 is the client height of a 960x640 window with the native tab strip.
      final scale = math.min(
        1.0,
        math.min(constraints.maxWidth / 960, constraints.maxHeight / 612),
      );
      return FittedBox(
        key: const ValueKey('workspace-desktop-scale'),
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth / scale,
          height: constraints.maxHeight / scale,
          child: _workspace(),
        ),
      );
    },
  );

  Widget _workspace() => LayoutBuilder(
    builder: (context, constraints) {
      final stackedNavigation = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final mobile = widget.mobile;
      final nav = _nav();
      return PopScope(
        canPop: _detail == null && _navigation == (widget.incomingOnly ? 2 : 0),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          bottomNavigationBar:
              mobile &&
                  !widget.incomingOnly &&
                  _detail == null &&
                  MediaQuery.viewInsetsOf(context).bottom == 0
              ? SafeArea(
                  top: false,
                  child: Padding(padding: EdgeInsets.zero, child: nav),
                )
              : null,
          body: SafeArea(
            bottom: !mobile,
            child: Column(
              children: [
                if (!mobile)
                  _desktopHeader(nav, stacked: stackedNavigation)
                else if (_detail == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Expanded(child: SubnetBrand(compact: true)),
                        if (!widget.incomingOnly) ...[
                          IconButton(
                            tooltip: t('添加设备', 'Add device'),
                            onPressed: _addDevice,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                        IconButton(
                          tooltip: t('设置', 'Settings'),
                          onPressed: widget.onSettings,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _detail != null
                      ? _deviceDetail(
                          [
                                ..._orderedNearby,
                                ...widget.recent,
                                ...widget.favorites,
                              ].where((d) => d.id == _detail!.id).firstOrNull ??
                              _detail!,
                          compact:
                              !mobile &&
                              (constraints.maxWidth < 1000 ||
                                  constraints.maxHeight < 700),
                        )
                      : switch (_navigation) {
                          1 => _deviceBrowser(),
                          2 => _local(),
                          _ => _home(),
                        },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _desktopHeader(Widget navigation, {required bool stacked}) => Padding(
    key: const ValueKey('workspace-desktop-header'),
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  key: ValueKey('workspace-header-brand'),
                  width: 200,
                  child: SubnetBrand(compact: true),
                ),
                Expanded(child: stacked ? const SizedBox.shrink() : navigation),
                SizedBox(
                  key: const ValueKey('workspace-header-actions'),
                  width: 200,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!widget.incomingOnly) ...[
                        IconButton(
                          tooltip: t('添加设备', 'Add device'),
                          onPressed: _addDevice,
                          icon: const Icon(Icons.add_rounded, size: 22),
                        ),
                      ],
                      IconButton(
                        tooltip: t('设置', 'Settings'),
                        onPressed: widget.onSettings,
                        icon: const Icon(Icons.settings_outlined, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (stacked) ...[const SizedBox(height: 8), navigation],
          ],
        ),
      ),
    ),
  );

  Widget _nav() {
    final labels = [
      t('首页', 'Home'),
      t('设备列表', 'Devices'),
      t('本机', 'This device'),
    ];
    final icons = [
      Icons.home_outlined,
      Icons.devices_outlined,
      widget.mobile ? Icons.smartphone_outlined : Icons.computer_outlined,
    ];
    if (widget.mobile && !widget.incomingOnly) {
      return NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          indicatorColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).hintColor,
            ),
          ),
        ),
        child: NavigationBar(
          elevation: 0,
          selectedIndex: _navigation,
          onDestinationSelected: _navigate,
          destinations: [
            for (var index = 0; index < labels.length; index++)
              NavigationDestination(
                key: ValueKey('workspace-nav-$index'),
                icon: Icon(icons[index], size: 24),
                label: labels[index],
              ),
          ],
        ),
      );
    }
    final items = List<Widget>.generate(3, (index) {
      if (widget.incomingOnly && index != 2) return const SizedBox.shrink();
      final selected = index == _navigation;
      final child = Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey('workspace-nav-' + index.toString()),
          onPressed: () => _navigate(index),
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: widget.mobile ? 1 : .6)
                : Colors.transparent,
            foregroundColor: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).hintColor,
            minimumSize: Size(64, widget.mobile ? 44 : 36),
            tapTargetSize: widget.mobile
                ? null
                : MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.symmetric(
              horizontal: widget.mobile ? 24 : 16,
              vertical: 10,
            ),
          ),
          child: widget.mobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icons[index], size: 24),
                    const SizedBox(height: 3),
                    Text(labels[index], style: const TextStyle(fontSize: 13)),
                  ],
                )
              : Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
        ),
      );
      return widget.mobile ? Expanded(child: child) : child;
    });
    return widget.mobile
        ? Row(children: items)
        : Wrap(
            key: const ValueKey('workspace-desktop-navigation'),
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 8,
            children: items,
          );
  }

  WorkspaceDevice? get _continueDevice {
    if (widget.recent.isNotEmpty) {
      final last = widget.recent.first;
      return _orderedNearby.where((p) => p.id == last.id).firstOrNull ?? last;
    }
    return _orderedNearby.firstOrNull ?? widget.favorites.firstOrNull;
  }

  List<WorkspaceDevice> get _orderedNearby {
    // Discovery can retain multiple identities for an endpoint after an
    // upgrade or network change. An endpoint still represents one row.
    final devices = <String, WorkspaceDevice>{};
    for (final device in widget.nearby) {
      final previous = devices[device.id];
      if (previous == null || previous.online != true || device.online == true) {
        devices[device.id] = device;
      }
    }
    return devices.values.toList()..sort(_compareDeviceNames);
  }

  int _compareDeviceNames(WorkspaceDevice a, WorkspaceDevice b) {
    final nameOrder = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return nameOrder == 0 ? a.id.compareTo(b.id) : nameOrder;
  }

  Widget _home() => LayoutBuilder(
    builder: (context, box) {
      return widget.mobile ? _mobileHome() : _desktopHome(box);
    },
  );

  Widget _desktopHome(BoxConstraints box) {
    final device = _continueDevice;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final contentWidth = math.min(box.maxWidth - 64, 1040.0);
    final twoColumns = contentWidth >= 720 && !largeText;
    final illustrationHeight = (box.maxHeight * .24).clamp(120.0, 184.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('workspace-home-content'),
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.hostAccess != null)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: contentWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: HostAccessControls(
                          state: widget.hostAccess!,
                          permissionLabel: widget.hostPermissionLabel,
                          onDiscoveryChanged:
                              widget.onDiscoveryChanged ?? (_) async {},
                          onRemoteChanged:
                              widget.onRemoteChanged ?? (_) async => false,
                          onConfigure: () => _navigate(2),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(
                flex: 4,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: contentWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          key: const ValueKey('workspace-hero-identity'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!largeText) ...[
                              Text(
                                device == null
                                    ? t('连接身边的设备', 'Connect to a nearby device')
                                    : t('继续连接', 'Continue connecting'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DeviceArt(
                                kind: device?.kind ?? DeviceKind.desktop,
                                key: const ValueKey('workspace-hero-image'),
                                width: illustrationHeight * 1.25,
                                height: illustrationHeight,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              device?.displayName ??
                                  t('让设备，近一点', 'Your devices, closer'),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              device == null
                                  ? t(
                                      '发现同一网络中的设备，或通过地址连接',
                                      'Discover your local network, or connect by address',
                                    )
                                  : [
                                      device.platform,
                                      device.displayAddress,
                                    ].where((s) => s.isNotEmpty).join(' · '),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            if (device != null) ...[
                              const SizedBox(height: 8),
                              _status(device),
                            ],
                            const SizedBox(height: 20),
                            _heroActions(
                              device,
                              compact: true,
                              expand: largeText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      key: const ValueKey('workspace-nearby-section'),
                      children: [
                        const Divider(height: 24),
                        _nearbyHeading(),
                        const SizedBox(height: 10),
                        if (_orderedNearby.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              t(
                                '尚未发现设备，可刷新或通过地址连接',
                                'No devices discovered. Refresh or connect by address.',
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              for (final peer in _orderedNearby.take(
                                twoColumns ? 2 : 1,
                              ))
                                SizedBox(
                                  width: twoColumns
                                      ? (contentWidth - 16) / 2
                                      : contentWidth,
                                  child: Material(
                                    key: ValueKey(
                                      'workspace-nearby-device-${peer.id}',
                                    ),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: _deviceRow(
                                        peer,
                                        compact: true,
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nearbyHeading() => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => _navigate(1, filter: 0),
              child: Text(
                t('附近的设备', 'Nearby devices'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _navigate(1, filter: 1),
              child: Text(t('收藏', 'Favorites')),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => _navigate(1),
              child: Text(t('查看全部', 'View all')),
            ),
            IconButton(
              tooltip: t('刷新设备', 'Refresh devices'),
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _mobileHome() {
    final device = _continueDevice;
    final theme = Theme.of(context);
    final peers = _orderedNearby.take(3).toList();
    return SingleChildScrollView(
      key: const ValueKey('workspace-mobile-home-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            key: const ValueKey('workspace-mobile-connect-card'),
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device == null
                              ? t('连接身边的设备', 'Connect to a nearby device')
                              : t('继续连接', 'Continue connecting'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (device != null)
                        _deviceActions(
                          device,
                          key: const ValueKey('workspace-device-actions'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, box) {
                      final wide =
                          box.maxWidth >= 600 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                      final identity = _mobileConnectionIdentity(
                        device,
                        compact: wide,
                      );
                      final action = _heroActions(device, showMore: false);
                      return wide
                          ? Row(
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 24),
                                SizedBox(width: 200, child: action),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                identity,
                                const SizedBox(height: 16),
                                action,
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Column(
            key: const ValueKey('workspace-nearby-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _navigate(1, filter: 0),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      t('附近的设备', 'Nearby devices'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _navigate(1),
                        child: Text(t('查看全部', 'View all')),
                      ),
                      IconButton(
                        tooltip: t('刷新设备', 'Refresh devices'),
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    t(
                      '尚未发现设备，可刷新或通过地址连接',
                      'No devices discovered. Refresh or connect by address.',
                    ),
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              else
                for (final peer in peers) ...[
                  _deviceRow(peer, dense: true),
                  if (peer != peers.last) const Divider(height: 1),
                ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobileConnectionIdentity(
    WorkspaceDevice? device, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        DeviceArt(
          kind: device?.kind ?? DeviceKind.desktop,
          key: const ValueKey('workspace-hero-image'),
          width: compact ? 64 : 80,
          height: compact ? 64 : 96,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device?.displayName ?? t('让设备，近一点', 'Your devices, closer'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                device == null
                    ? t(
                        '发现同一网络中的设备，或通过地址连接',
                        'Discover your local network, or connect by address',
                      )
                    : [
                        device.platform,
                        device.displayAddress,
                      ].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
              if (device != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _status(device, compact: true),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
  Widget _heroActions(
    WorkspaceDevice? device, {
    bool compact = false,
    bool expand = false,
    bool showMore = true,
  }) => SizedBox(
    key: const ValueKey('workspace-hero-actions'),
    width: widget.mobile || expand ? double.infinity : 436,
    child: Row(
      children: [
        if (!widget.mobile && device != null) const SizedBox(width: 60),
        Expanded(
          child: ElevatedButton.icon(
            key: const ValueKey('workspace-primary-connect'),
            onPressed: device == null
                ? _addDevice
                : () => widget.onConnect(device, LanTool.desktop),
            style: ElevatedButton.styleFrom(
              minimumSize: Size(
                48,
                widget.mobile
                    ? 52
                    : compact
                    ? 44
                    : 56,
              ),
              visualDensity: VisualDensity.standard,
              textStyle: TextStyle(
                fontSize: widget.mobile || compact ? 16 : 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.north_east_rounded, size: 20),
            label: Text(
              device == null
                  ? t('通过地址连接', 'Connect by address')
                  : t('连接设备', 'Connect device'),
            ),
          ),
        ),
        if (device != null && showMore) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.mobile
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surfaceContainerHighest
                          .withValues(alpha: .4),
              ),
              child: _deviceActions(
                device,
                key: const ValueKey('workspace-device-actions'),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _deviceActions(WorkspaceDevice device, {Key? key}) =>
      PopupMenuButton<String>(
        key: key,
        tooltip: widget.mobile
            ? '${t('更多设备操作', 'More device actions')} · ${device.displayName}'
            : t('更多设备操作', 'More device actions'),
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (value) {
          switch (value) {
            case 'details':
              if (widget.mobile) {
                setState(() => _detail = device);
              } else {
                _showDeviceInformation(device);
              }
              return;
            case 'favorite':
              widget.onFavorite(device);
              return;
            case 'copy-address':
              _copy(device.id);
              return;
            default:
              widget.onConnect(device, LanTool.values.byName(value));
          }
        },
        itemBuilder: (_) => [
          if (widget.mobile)
            PopupMenuItem(
              value: 'details',
              child: Text(t('设备详情', 'Device details')),
            ),
          PopupMenuItem(
            value: 'files',
            child: Text(t('文件传输', 'File transfer')),
          ),
          PopupMenuItem(value: 'terminal', child: Text(t('终端', 'Terminal'))),
          PopupMenuItem(value: 'camera', child: Text(t('摄像头', 'Camera'))),
          if (!widget.mobile) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'favorite',
              child: Text(
                _favoriteIds.contains(device.id)
                    ? t('取消收藏', 'Remove favorite')
                    : t('收藏设备', 'Favorite device'),
              ),
            ),
            PopupMenuItem(
              value: 'copy-address',
              child: Text(t('复制地址', 'Copy address')),
            ),
            PopupMenuItem(
              value: 'details',
              child: Text(t('设备信息', 'Device information')),
            ),
          ],
        ],
      );

  Future<void> _showDeviceInformation(WorkspaceDevice device) =>
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(device.displayName),
          content: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (device.platform.isNotEmpty) Text(device.platform),
                const SizedBox(height: 12),
                _status(device),
                const SizedBox(height: 20),
                Text(t('连接地址', 'Connection address')),
                SelectableText(device.displayAddress),
                if (device.fingerprint.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(t('设备指纹', 'Device fingerprint') + ' · SHA-256'),
                  SelectableText(device.fingerprint),
                ],
                if (_favoriteIds.contains(device.id)) ...[
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue:
                        widget.groupFor?.call(device.id) ?? favoriteUngroupedId,
                    decoration: InputDecoration(
                      labelText: t('收藏分组', 'Favorite group'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: favoriteUngroupedId,
                        child: Text(t('未分组', 'Ungrouped')),
                      ),
                      ...widget.groups.map(
                        (g) =>
                            DropdownMenuItem(value: g.id, child: Text(g.name)),
                      ),
                    ],
                    onChanged: (v) => widget.onAssignGroup?.call(device.id, v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _copy(device.id),
              child: Text(t('复制地址', 'Copy address')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(t('关闭', 'Close')),
            ),
          ],
        ),
      );

  Widget _status(WorkspaceDevice device, {bool compact = false}) {
    final darkMobile = widget.mobile &&
        Theme.of(context).brightness == Brightness.dark;
    final color = device.online == true
        ? darkMobile
            ? const Color(0xFF91CDA2)
            : const Color(0xFF447956)
        : Theme.of(context).hintColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          device.online == true
              ? Icons.check_circle_outline_rounded
              : device.online == false
              ? Icons.remove_circle_outline_rounded
              : Icons.help_outline_rounded,
          color: color,
          size: compact ? 15 : 18,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            device.online == true
                ? t('可达', 'Reachable')
                : device.online == false
                ? t('暂不可达', 'Unreachable')
                : t('未检查', 'Not checked'),
            style: TextStyle(color: color, fontSize: compact ? 12 : 14),
          ),
        ),
      ],
    );
  }

  IconData _deviceIcon(WorkspaceDevice d) => d.kind.icon;

  Widget _avatar(WorkspaceDevice d, {double size = 56}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: Icon(_deviceIcon(d), size: size * .43),
  );

  Widget _deviceRow(
    WorkspaceDevice device, {
    bool compact = false,
    bool reconnect = false,
    bool dense = false,
  }) => InkWell(
    key: ValueKey('device-row-' + device.id),
    borderRadius: BorderRadius.circular(16),
    onTap: () => widget.mobile
        ? setState(() => _detail = device)
        : widget.onConnect(device, LanTool.desktop),
    child: Padding(
      padding: EdgeInsets.symmetric(
        vertical: dense ? 8 : 16,
        horizontal: widget.mobile ? 0 : 8,
      ),
      child: Row(
        children: [
          _avatar(
            device,
            size: dense
                ? 42
                : compact
                ? 62
                : 54,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.displayAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: dense ? 12 : 13,
                  ),
                ),
                const SizedBox(height: 5),
                _status(device, compact: dense),
              ],
            ),
          ),
          if (!widget.mobile) ...[
            if (!compact)
              OutlinedButton(
                onPressed: () => widget.onConnect(device, LanTool.desktop),
                child: Text(
                  reconnect ? t('重新连接', 'Reconnect') : t('连接', 'Connect'),
                ),
              ),
            _deviceActions(
              device,
              key: ValueKey('device-actions-' + device.id),
            ),
          ] else
            const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    ),
  );

  List<WorkspaceDevice> get _listedDevices {
    final map = <String, WorkspaceDevice>{};
    final source = _isFavorite
        ? widget.favorites
        : _filter == 0
        ? _orderedNearby
        : [...widget.recent, ...widget.favorites, ..._orderedNearby];
    for (final d in source) {
      map[d.id] = d;
    }
    final result = map.values
        .where(
          (d) =>
              !_isFavorite ||
              _group == null ||
              (_group == favoriteUngroupedId
                  ? widget.groupFor?.call(d.id) == null
                  : widget.groupFor?.call(d.id) == _group),
        )
        .toList();
    result.sort(_compareDeviceNames);
    return result;
  }

  Widget _deviceBrowser() {
    final devices = _listedDevices;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.mobile ? 16 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: LayoutBuilder(
            builder: (context, box) {
              final columns =
                  !widget.mobile &&
                  box.maxWidth >= math.max(760, _connectButtonWidth + 588) &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              return Scrollbar(
                controller: _deviceListScroll,
                child: CustomScrollView(
                  key: const ValueKey('workspace-device-list'),
                  controller: _deviceListScroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      _isFavorite
                                          ? t('收藏', 'Favorites')
                                          : _filter == 0
                                          ? t('附近的设备', 'Nearby devices')
                                          : t('全部设备', 'All devices'),
                                      style: TextStyle(
                                        fontSize: widget.mobile ? 24 : 28,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      t(
                                        '${devices.length} 台设备',
                                        devices.length == 1
                                            ? '1 device'
                                            : '${devices.length} devices',
                                      ),
                                      key: const ValueKey(
                                        'workspace-device-count',
                                      ),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).hintColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (columns)
                                Tooltip(
                                  message: t('刷新设备', 'Refresh devices'),
                                  child: TextButton.icon(
                                    onPressed: widget.onRefresh,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: Text(t('刷新', 'Refresh')),
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: t('刷新设备', 'Refresh devices'),
                                  onPressed: widget.onRefresh,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                            ],
                          ),
                          SizedBox(height: columns ? 0 : 16),
                          if (_isFavorite) _groupFilters(),
                          if (columns)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).hintColor,
                                ),
                                child: _deviceColumns(
                                  name: Text(t('设备', 'Device')),
                                  address: Text(t('地址', 'Address')),
                                  status: Text(t('状态', 'Status')),
                                  actions: Text(t('操作', 'Actions')),
                                ),
                              ),
                            ),
                          if (devices.isNotEmpty) const Divider(height: 1),
                        ],
                      ),
                    ),
                    if (devices.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: SubnetEmpty(
                            icon: _isFavorite
                                ? Icons.star_outline_rounded
                                : Icons.devices_outlined,
                            title: t('这里还没有设备', 'No devices here'),
                            message: _isFavorite
                                ? widget.mobile
                                      ? t(
                                          '在设备详情中收藏常用设备',
                                          'Save a device from its details',
                                        )
                                      : t(
                                          '在更多操作中收藏常用设备',
                                          'Save a device from More actions',
                                        )
                                : t(
                                    '请确认设备处于同一网络，或手动输入地址',
                                    'Check the local network, or enter an address',
                                  ),
                            action: TextButton(
                              onPressed: _addDevice,
                              child: Text(t('通过地址连接', 'Connect by address')),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) =>
                            _browserDeviceRow(devices[i], columns: columns),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  double get _connectButtonWidth => math.max(
    76,
    subnetTextWidth(
      context,
      t('连接', 'Connect'),
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ) + 24,
  );

  Widget _deviceColumns({
    required Widget name,
    required Widget address,
    required Widget status,
    required Widget actions,
  }) => Row(
    children: [
      Expanded(flex: 2, child: name),
      const SizedBox(width: 16),
      Expanded(child: address),
      const SizedBox(width: 16),
      SizedBox(width: 212, child: status),
      const SizedBox(width: 16),
      SizedBox(width: _connectButtonWidth + 48, child: actions),
    ],
  );

  Widget _browserDeviceRow(WorkspaceDevice device, {required bool columns}) {
    final name = Tooltip(
      message: device.displayName,
      child: Text(
        device.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
    final address = Tooltip(
      message: device.displayAddress,
      child: Text(
        device.displayAddress,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
      ),
    );
    final stackActions =
        widget.mobile && MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final actions = Flex(
      direction: stackActions ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: columns ? _connectButtonWidth : null,
          child: OutlinedButton(
            key: ValueKey('workspace-device-connect-${device.id}'),
            onPressed: () => widget.onConnect(device, LanTool.desktop),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(64, widget.mobile ? 48 : 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(
              t('连接', 'Connect'),
            ),
          ),
        ),
        SizedBox(width: stackActions ? 0 : 8, height: stackActions ? 8 : 0),
        SizedBox(
          width: widget.mobile ? 48 : 40,
          height: widget.mobile ? 48 : 40,
          child: _deviceActions(
            device,
            key: ValueKey('device-actions-${device.id}'),
          ),
        ),
      ],
    );
    return InkWell(
      key: ValueKey('device-row-${device.id}'),
      onTap: () => widget.mobile
          ? setState(() => _detail = device)
          : widget.onConnect(device, LanTool.desktop),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.mobile ? 0 : 8,
          vertical: columns ? 0 : 4,
        ),
        child: columns
            ? _deviceColumns(
                name: Row(
                  children: [
                    _avatar(device, size: 32),
                    const SizedBox(width: 16),
                    Expanded(child: name),
                  ],
                ),
                address: address,
                status: _status(device, compact: true),
                actions: actions,
              )
            : Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          const SizedBox(height: 4),
                          address,
                          const SizedBox(height: 4),
                          _status(device, compact: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  actions,
                ],
              ),
      ),
    );
  }

  Widget _groupFilters() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(t('全部分组', 'All groups')),
                  selected: _group == null,
                  onSelected: (_) => setState(() => _group = null),
                ),
                for (final g in widget.groups)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(g.name),
                      selected: _group == g.id,
                      onSelected: (_) => setState(() => _group = g.id),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(t('未分组', 'Ungrouped')),
                    selected: _group == favoriteUngroupedId,
                    onSelected: (_) =>
                        setState(() => _group = favoriteUngroupedId),
                  ),
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: t('管理分组', 'Manage groups'),
          onSelected: _manageGroup,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'new', child: Text(t('新建分组', 'New group'))),
            if (widget.groups.any((g) => g.id == _group)) ...[
              PopupMenuItem(
                value: 'rename',
                child: Text(t('重命名当前分组', 'Rename selected group')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(t('删除当前分组', 'Delete selected group')),
              ),
            ],
          ],
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    ),
  );

  Future<void> _manageGroup(String action) async {
    final group = widget.groups.where((g) => g.id == _group).firstOrNull;
    if (action == 'delete' && group != null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          scrollable: true,
          title: Text(t('删除分组', 'Delete group') + ' “' + group.name + '”'),
          content: Text(
            t(
              '分组中的设备仍会保留在收藏中。',
              'Devices in this group will remain in Favorites.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('删除分组', 'Delete group')),
            ),
          ],
        ),
      );
      if (accepted == true) {
        widget.onDeleteGroup?.call(group.id);
        if (mounted) setState(() => _group = null);
      }
      return;
    }
    final form = GlobalKey<FormState>();
    String value = action == 'rename' ? group?.name ?? '' : '';
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(
          action == 'rename'
              ? t('重命名分组', 'Rename group')
              : t('新建分组', 'New group'),
        ),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: value,
            autofocus: true,
            maxLength: 32,
            decoration: InputDecoration(labelText: t('分组名称', 'Group name')),
            onChanged: (v) => value = v,
            validator: (v) => (v ?? '').trim().isEmpty
                ? t('请输入名称', 'Enter a name')
                : widget.groups.any(
                    (g) =>
                        g.id != group?.id &&
                        g.name.toLowerCase() == v!.trim().toLowerCase(),
                  )
                ? t('已存在同名分组', 'A group with this name already exists')
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('取消', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, value.trim());
            },
            child: Text(t('保存', 'Save')),
          ),
        ],
      ),
    );
    if (result != null) {
      if (action == 'rename' && group != null) {
        widget.onRenameGroup?.call(group.id, result);
      } else {
        widget.onCreateGroup?.call(result);
      }
    }
  }

  Widget _deviceDetail(
    WorkspaceDevice device, {
    bool compact = false,
  }) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact
          ? 16
          : widget.mobile
          ? 16
          : 52,
    ),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: t('返回', 'Back'),
              onPressed: () => setState(() => _detail = null),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Text(
                widget.mobile
                    ? t('设备详情', 'Device details')
                    : t('返回设备', 'Back to devices'),
                style: TextStyle(
                  fontSize: widget.mobile ? 20 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: _favoriteIds.contains(device.id)
                  ? t('取消收藏', 'Remove favorite')
                  : t('收藏设备', 'Favorite device'),
              onPressed: () => widget.onFavorite(device),
              icon: Icon(
                _favoriteIds.contains(device.id)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
              ),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.mobile ? 760 : 1000,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: compact
                          ? 8
                          : widget.mobile
                          ? 20
                          : 32,
                    ),
                    DeviceArt(
                      kind: device.kind,
                      key: const ValueKey('workspace-detail-image'),
                      width: compact
                          ? 120
                          : widget.mobile
                          ? 160
                          : 220,
                      height: compact
                          ? 80
                          : widget.mobile
                          ? 112
                          : 156,
                    ),
                    SizedBox(
                      height: compact
                          ? 12
                          : widget.mobile
                          ? 20
                          : 24,
                    ),
                    Text(
                      device.displayName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact
                            ? 26
                            : widget.mobile
                            ? 24
                            : 34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.mobile
                          ? device.platform
                          : [
                              device.platform,
                              device.displayAddress,
                            ].where((v) => v.isNotEmpty).join(' · '),
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                    const SizedBox(height: 12),
                    _status(device),
                    const SizedBox(height: 28),
                    if (!widget.mobile && !compact) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                widget.onConnect(device, LanTool.desktop),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(270, 56),
                              visualDensity: VisualDensity.standard,
                            ),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(
                              Icons.north_east_rounded,
                              size: 20,
                            ),
                            label: Text(t('连接设备', 'Connect device')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                widget.onConnect(device, LanTool.files),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(150, 56),
                              visualDensity: VisualDensity.standard,
                            ),
                            icon: const Icon(Icons.folder_outlined, size: 22),
                            label: Text(t('文件传输', 'File transfer')),
                          ),
                          PopupMenuButton<LanTool>(
                            tooltip: t('更多设备操作', 'More device actions'),
                            onSelected: (tool) =>
                                widget.onConnect(device, tool),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: LanTool.terminal,
                                child: Text(t('终端', 'Terminal')),
                              ),
                              PopupMenuItem(
                                value: LanTool.camera,
                                child: Text(t('摄像头', 'Camera')),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.more_horiz_rounded),
                                  const SizedBox(width: 8),
                                  Text(t('更多', 'More')),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.expand_more_rounded),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Divider(),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('连接地址', 'Connection address')),
                      subtitle: SelectableText(device.displayAddress),
                      trailing: IconButton(
                        tooltip: t('复制地址', 'Copy address'),
                        onPressed: () => _copy(device.id),
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ),
                    const Divider(),
                    if (device.fingerprint.isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t('设备指纹', 'Device fingerprint')),
                        subtitle: const Text('SHA-256'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (c) => AlertDialog(
                            scrollable: true,
                            title: Text(t('设备指纹', 'Device fingerprint')),
                            content: SelectableText(device.fingerprint),
                            actions: [
                              TextButton(
                                onPressed: () => _copy(device.fingerprint),
                                child: Text(
                                  t('复制完整指纹', 'Copy full fingerprint'),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: Text(t('关闭', 'Close')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_favoriteIds.contains(device.id))
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.groupFor?.call(device.id) ??
                            favoriteUngroupedId,
                        decoration: InputDecoration(
                          labelText: t('收藏分组', 'Favorite group'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: favoriteUngroupedId,
                            child: Text(t('未分组', 'Ungrouped')),
                          ),
                          ...widget.groups.map(
                            (g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            widget.onAssignGroup?.call(device.id, v),
                      ),
                    const SizedBox(height: 20),
                    if (widget.mobile)
                      _toolRow(
                        device,
                        LanTool.files,
                        Icons.folder_outlined,
                        t('文件传输', 'File transfer'),
                        t(
                          '在本机与该设备之间传输文件',
                          'Transfer files between this device and the remote device',
                        ),
                      ),
                    if (widget.mobile)
                      _toolRow(
                        device,
                        LanTool.terminal,
                        Icons.terminal_rounded,
                        t('终端', 'Terminal'),
                        t('在该设备上打开终端', 'Open a terminal on this device'),
                      ),
                    if (widget.mobile)
                      _toolRow(
                        device,
                        LanTool.camera,
                        Icons.videocam_outlined,
                        t('摄像头', 'Camera'),
                        t(
                          '连接后检查设备支持的能力',
                          'Availability is checked when connecting',
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.mobile || compact)
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
              child: SizedBox(
                width: double.infinity,
                child: compact
                    ? _heroActions(device, compact: true, expand: true)
                    : ElevatedButton.icon(
                        onPressed: () =>
                            widget.onConnect(device, LanTool.desktop),
                        icon: const Icon(Icons.north_east_rounded),
                        label: Text(t('连接设备', 'Connect device')),
                      ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _toolRow(
    WorkspaceDevice device,
    LanTool tool,
    IconData icon,
    String title,
    String subtitle,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      child: Icon(icon),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => widget.onConnect(device, tool),
  );

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('已复制', 'Copied')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _local() {
    if (!widget.mobile && widget.localPane != null) return widget.localPane!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.mobile ? 16 : 52,
            vertical: widget.mobile ? 8 : 16,
          ),
          child: Text(
            t('本机', 'This device'),
            style: TextStyle(
              fontSize: widget.mobile ? 24 : 30,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child:
              widget.localPane ??
              SingleChildScrollView(
                child: SubnetEmpty(
                  icon: Icons.smartphone_outlined,
                  title: t('本机接收未启用', 'Incoming access is unavailable'),
                  message: t(
                    '仍可主动连接局域网中的其他设备。',
                    'You can still connect to other devices on your network.',
                  ),
                  action: OutlinedButton(
                    onPressed: widget.onSettings,
                    child: Text(t('打开设置', 'Open settings')),
                  ),
                ),
              ),
        ),
      ],
    );
  }
  Future<void> _addDevice() async {
    final form = GlobalKey<FormState>();
    String address = '';
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(t('通过地址连接', 'Connect by address')),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    '输入同一网络中设备的 IP 或主机名。',
                    'Enter the IP address or hostname of a device on your network.',
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: t('设备地址', 'Device address'),
                    hintText: '192.168.1.20',
                    helperMaxLines: 2,
                    errorMaxLines: 3,
                    helperText: t(
                      '可使用主机名；端口可省略',
                      'Hostnames are supported; the port is optional',
                    ),
                  ),
                  onChanged: (v) => address = v,
                  onFieldSubmitted: (v) {
                    if (form.currentState!.validate())
                      Navigator.pop(c, v.trim());
                  },
                  validator: (v) => validLanWorkspaceAddress(v ?? '')
                      ? null
                      : t(
                          '请输入有效的 IP 或主机名及可选端口',
                          'Enter a valid IP or hostname and optional port',
                        ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('取消', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (form.currentState!.validate())
                Navigator.pop(c, address.trim());
            },
            child: Text(t('下一步', 'Continue')),
          ),
        ],
      ),
    );
    if (result != null && mounted)
      widget.onConnect(
        WorkspaceDevice(id: result, name: result),
        LanTool.desktop,
      );
  }
}

bool validLanWorkspaceAddress(String value) {
  final text = value.trim();
  if (text.isEmpty || RegExp(r'\s|[/\\?#@]').hasMatch(text)) return false;
  if (text.startsWith('[')) {
    final match = RegExp(r'^\[([^\]]+)\](?::([0-9]+))?$').firstMatch(text);
    if (match == null || !_validIpv6Host(match.group(1)!)) return false;
    final port = match.group(2);
    return port == null || _validPort(port);
  }
  final parts = text.split(':');
  if (parts.length > 2) return _validIpv6Host(text);
  if (!RegExp(r'^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$').hasMatch(parts.first))
    return false;
  if (RegExp(r'^[0-9.]+$').hasMatch(parts.first)) {
    final octets = parts.first.split('.');
    if (octets.length != 4 ||
        octets.any((v) => int.tryParse(v) == null || int.parse(v) > 255))
      return false;
  }
  return parts.length == 1 || _validPort(parts.last);
}

bool _validIpv6Host(String value) {
  final parts = value.split('%');
  if (parts.length > 2 ||
      (parts.length == 2 && !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(parts.last)))
    return false;
  try {
    Uri.parseIPv6Address(parts.first);
    return true;
  } on FormatException {
    return false;
  }
}

bool _validPort(String value) {
  final port = int.tryParse(value);
  return port != null && port >= 1 && port <= 65535;
}
