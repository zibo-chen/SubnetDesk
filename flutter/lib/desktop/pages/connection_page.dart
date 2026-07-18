// main window right pane

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/lan_discovery_refresh.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../models/platform_model.dart';

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
            onTap: () async {
              await start_service(true);
            },
            child: Text(
              translate("Start service"),
              style:
                  TextStyle(decoration: TextDecoration.underline, fontSize: em),
            ),
          ).marginOnly(left: em),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(
        () => isIncomingOnly
            ? Column(
                children: [
                  basicWidget(),
                  Align(
                    child: startServiceWidget(),
                    alignment: Alignment.centerLeft,
                  ).marginOnly(top: 2.0, left: 22.0),
                ],
              )
            : basicWidget(),
      ),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    Key? key,
    this.selectedPeerTab = PeerTabIndex.lan,
  }) : super(key: key);

  final PeerTabIndex selectedPeerTab;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> with WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberPassword = false;
  Timer? _lanDiscoveryTimer;

  bool isWindowMinimized = false;

  @override
  void initState() {
    super.initState();
    final savedCardUiType =
        bind.getLocalFlutterOption(k: kOptionPeerCardUiType);
    if (savedCardUiType == PeerUiType.list.name) {
      peerCardUiType.value = PeerUiType.list;
    } else {
      peerCardUiType.value = PeerUiType.grid;
    }
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
            _idEditingController.text = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
    _loadSelectedPeers();
    _lanDiscoveryTimer = Timer.periodic(lanDiscoveryRefreshInterval, (_) {
      if (shouldRefreshLanDiscovery(
        lanTabSelected: widget.selectedPeerTab == PeerTabIndex.lan,
        windowMinimized: isWindowMinimized,
      )) {
        bind.mainDiscover();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ConnectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPeerTab != widget.selectedPeerTab) {
      peerSearchText.value = '';
      peerSearchTextController.clear();
      _loadSelectedPeers();
    }
  }

  void _loadSelectedPeers() {
    switch (widget.selectedPeerTab) {
      case PeerTabIndex.recent:
        bind.mainLoadRecentPeers();
        break;
      case PeerTabIndex.fav:
        bind.mainLoadFavPeers();
        break;
      case PeerTabIndex.lan:
        bind.mainLoadLanPeers();
        bind.mainDiscover();
        break;
    }
  }

  @override
  void dispose() {
    _lanDiscoveryTimer?.cancel();
    _idController.dispose();
    windowManager.removeListener(this);
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    if (_idFocusNode.hasFocus) {
      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: textLength,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Colors.white12 : const Color(0xFFE4E8F0);
    final sectionTitle = switch (widget.selectedPeerTab) {
      PeerTabIndex.recent => translate('Recent sessions'),
      PeerTabIndex.fav => translate('Favorites'),
      PeerTabIndex.lan => translate('Discovered'),
    };
    final peers = switch (widget.selectedPeerTab) {
      PeerTabIndex.recent => gFFI.recentPeersModel,
      PeerTabIndex.fav => gFFI.favoritePeersModel,
      PeerTabIndex.lan => gFFI.lanPeersModel,
    };
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showAddDeviceDialog(context),
                icon: const Icon(Icons.add, size: 20),
                label: Text(translate('Add')),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 290),
                  child: TextField(
                    controller: peerSearchTextController,
                    onChanged: (value) => peerSearchText.value = value,
                    decoration: InputDecoration(
                      hintText:
                          '${translate('Search')} · ${translate('Local Address')}',
                      prefixIcon: const Icon(Icons.search, size: 21),
                      suffixIcon: Obx(
                        () => peerSearchText.value.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                onPressed: () {
                                  peerSearchTextController.clear();
                                  peerSearchText.value = '';
                                },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                      ),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildSortButton(context, border),
              const SizedBox(width: 10),
              _buildViewButton(context, border),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedBuilder(
                  animation: peers,
                  builder: (context, _) => Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: sectionTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  (${peers.peers.length})',
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: PeerTabPage(
                    key: ValueKey(widget.selectedPeerTab),
                    selectedIndex: widget.selectedPeerTab.index,
                    showTabs: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton(BuildContext context, Color border) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: PopupMenuButton<String>(
        tooltip: translate('Sort by'),
        icon: const Icon(Icons.swap_vert_rounded),
        initialValue: peerSort.value,
        onSelected: (value) {
          peerSort.value = value;
          bind.setLocalFlutterOption(k: kOptionPeerSorting, v: value);
        },
        itemBuilder: (context) => PeerSortType.values
            .map(
              (value) => PopupMenuItem<String>(
                value: value,
                child: Text(translate(value)),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildViewButton(BuildContext context, Color border) {
    return Obx(
      () => Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: translate('Grid View'),
              onPressed: () => _setPeerCardUiType(PeerUiType.grid),
              icon: Icon(
                Icons.grid_view_rounded,
                color: peerCardUiType.value == PeerUiType.grid
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            IconButton(
              tooltip: translate('List'),
              onPressed: () => _setPeerCardUiType(PeerUiType.list),
              icon: Icon(
                Icons.view_list_rounded,
                color: peerCardUiType.value == PeerUiType.list
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setPeerCardUiType(PeerUiType type) {
    peerCardUiType.value = type;
    bind.setLocalFlutterOption(k: kOptionPeerCardUiType, v: type.name);
  }

  Future<void> _showAddDeviceDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(translate('Add')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _idEditingController,
                  focusNode: _idFocusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '${translate('Local Address')} (IP / DNS)',
                    prefixIcon: const Icon(Icons.desktop_windows_outlined),
                  ),
                  onChanged: (value) => _idController.id = value,
                  onSubmitted: (_) async {
                    final connected = await onConnect();
                    if (connected && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: translate('Username'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: translate('Password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  onSubmitted: (_) async {
                    final connected = await onConnect();
                    if (connected && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
                CheckboxListTile(
                  value: _rememberPassword,
                  onChanged: (value) => setDialogState(
                    () => _rememberPassword = value == true,
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(translate('Remember password')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(translate('Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final connected = await onConnect();
                if (connected && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(translate('Connect')),
            ),
          ],
        ),
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  Future<bool> onConnect({
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTerminal = false,
  }) async {
    final endpoint = _idController.id;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (endpoint.isEmpty || (username.isEmpty && password.isNotEmpty)) {
      showToast(
        '${translate('Local Address')} · ${translate('Username')} · ${translate('Password')}',
      );
      return false;
    }
    final credentialPayload = password.isEmpty
        ? null
        : jsonEncode({
            'lan_version': 1,
            'username': username,
            'password': password,
            'remember': _rememberPassword,
          });
    await connect(
      context,
      endpoint,
      isFileTransfer: isFileTransfer,
      isViewCamera: isViewCamera,
      isTerminal: isTerminal,
      password: credentialPayload,
    );
    _passwordController.clear();
    return true;
  }
}
