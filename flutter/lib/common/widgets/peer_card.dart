import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import '../../desktop/widgets/popup_menu.dart';

typedef PopupMenuEntryBuilder = Future<List<mod_menu.PopupMenuEntry<String>>>
    Function(BuildContext);

enum PeerUiType { grid, tile, list }

final peerCardUiType = PeerUiType.grid.obs;

bool? hideUsernameOnCard;

class _PeerCard extends StatefulWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final Function(BuildContext, String) connect;
  final PopupMenuEntryBuilder popupMenuEntryBuilder;

  const _PeerCard({
    required this.peer,
    required this.tab,
    required this.connect,
    required this.popupMenuEntryBuilder,
    Key? key,
  }) : super(key: key);

  @override
  _PeerCardState createState() => _PeerCardState();
}

/// State for the connection page.
class _PeerCardState extends State<_PeerCard>
    with AutomaticKeepAliveClientMixin {
  var _menuPos = RelativeRect.fill;
  final double _cardRadius = 16;
  final double _tileRadius = 5;
  final double _borderWidth = 2;
  bool _favorite = false;

  bool get _isDiscoveredPeer => widget.tab == PeerTabIndex.lan;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  @override
  void didUpdateWidget(covariant _PeerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.id != widget.peer.id || oldWidget.tab != widget.tab) {
      _loadFavorite();
    }
  }

  Future<void> _loadFavorite() async {
    final favorites = await bind.mainGetFav();
    if (mounted) {
      setState(() => _favorite = favorites.contains(widget.peer.id));
    }
  }

  Future<void> _toggleFavorite() async {
    final favorites = (await bind.mainGetFav()).toList();
    if (favorites.contains(widget.peer.id)) {
      favorites.remove(widget.peer.id);
    } else {
      favorites.add(widget.peer.id);
    }
    await bind.mainStoreFav(favs: favorites);
    if (widget.tab == PeerTabIndex.fav) {
      await bind.mainLoadFavPeers();
    }
    await _loadFavorite();
  }

  String _primaryLabel(Peer peer) {
    if (!_isDiscoveredPeer) {
      return peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    }
    if (peer.alias.isNotEmpty) return peer.alias;
    if (peer.hostname.isNotEmpty) return peer.hostname;
    return formatID(peer.id);
  }

  String _secondaryLabel(Peer peer) {
    if (!_isDiscoveredPeer) {
      return hideUsernameOnCard == true
          ? peer.hostname
          : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    }
    return [peer.platform, formatID(peer.id)]
        .where((value) => value.isNotEmpty)
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(
      () =>
          stateGlobal.isPortrait.isTrue ? _buildPortrait() : _buildLandscape(),
    );
  }

  Widget gestureDetector({required Widget child}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final peer = super.widget.peer;
    return GestureDetector(
      onDoubleTap: peerTabModel.multiSelectionMode
          ? null
          : () => widget.connect(context, peer.id),
      onTap: () {
        if (peerTabModel.multiSelectionMode) {
          peerTabModel.select(peer);
        } else {
          if (isMobile) {
            widget.connect(context, peer.id);
          } else {
            peerTabModel.select(peer);
          }
        }
      },
      onLongPress: () => peerTabModel.select(peer),
      child: child,
    );
  }

  Widget _buildPortrait() {
    final peer = super.widget.peer;
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 2),
      child: gestureDetector(
        child: Container(
          padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: _buildPeerTile(context, peer, null),
        ),
      ),
    );
  }

  Widget _buildLandscape() {
    final peer = super.widget.peer;
    var deco = Rx<BoxDecoration?>(
      BoxDecoration(
        border: Border.all(color: Colors.transparent, width: _borderWidth),
        borderRadius: BorderRadius.circular(
          peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
        ),
      ),
    );
    return MouseRegion(
      onEnter: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: _borderWidth,
          ),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      onExit: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(color: Colors.transparent, width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      child: gestureDetector(
        child: Obx(
          () => peerCardUiType.value == PeerUiType.grid
              ? _buildPeerCard(context, peer, deco)
              : _buildPeerTile(context, peer, deco),
        ),
      ),
    );
  }

  makeChild(bool isPortrait, Peer peer) {
    final primaryLabel = _primaryLabel(peer);
    final secondaryLabel = _secondaryLabel(peer);
    final greyStyle = TextStyle(
      fontSize: 11,
      color: Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.6),
    );
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          decoration: BoxDecoration(
            color: str2color('${peer.id}${peer.platform}', 0x7f),
            borderRadius: isPortrait
                ? BorderRadius.circular(_tileRadius)
                : BorderRadius.only(
                    topLeft: Radius.circular(_tileRadius),
                    bottomLeft: Radius.circular(_tileRadius),
                  ),
          ),
          alignment: Alignment.center,
          width: isPortrait ? 50 : 42,
          height: isPortrait ? 50 : null,
          child: Stack(
            children: [
              getPlatformImage(
                peer.platform,
                size: isPortrait ? 38 : 30,
              ).paddingAll(6),
              if (_shouldBuildPasswordIcon(peer))
                Positioned(
                  top: 1,
                  left: 1,
                  child: Icon(Icons.key, size: 6, color: Colors.white),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(_tileRadius),
                bottomRight: Radius.circular(_tileRadius),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          getOnline(isPortrait ? 4 : 8, peer.online),
                          Expanded(
                            child: Text(
                              primaryLabel,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ).marginOnly(top: isPortrait ? 0 : 2),
                      Row(
                        children: [
                          Flexible(
                            child: Tooltip(
                              message: secondaryLabel,
                              waitDuration: const Duration(seconds: 1),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  secondaryLabel,
                                  style: isPortrait ? null : greyStyle,
                                  textAlign: TextAlign.start,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ).marginOnly(top: 2),
                ),
                isPortrait
                    ? checkBoxOrActionMorePortrait(peer)
                    : checkBoxOrActionMoreLandscape(peer, isTile: true),
              ],
            ).paddingOnly(left: 10.0, top: 3.0),
          ),
        ),
      ],
    );
  }

  Widget _buildPeerTile(
    BuildContext context,
    Peer peer,
    Rx<BoxDecoration?>? deco,
  ) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    return Obx(
      () => deco == null
          ? makeChild(stateGlobal.isPortrait.isTrue, peer)
          : Container(
              foregroundDecoration: deco.value,
              child: makeChild(stateGlobal.isPortrait.isTrue, peer),
            ),
    );
  }

  Widget _buildPeerCard(
    BuildContext context,
    Peer peer,
    Rx<BoxDecoration?> deco,
  ) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final primaryLabel = _primaryLabel(peer);
    final secondaryLabel = _secondaryLabel(peer);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF24262D) : Colors.white;
    final border = isDark ? Colors.white12 : const Color(0xFFE1E5EC);
    final muted = isDark ? Colors.white60 : const Color(0xFF737B8C);
    final child = Card(
      color: surface,
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withOpacity(0.08),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
        side: BorderSide(color: border),
      ),
      child: Obx(
        () => Container(
          foregroundDecoration: deco.value,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_cardRadius - _borderWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 72,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [Color(0xFF253A61), Color(0xFF1D2940)]
                            : const [Color(0xFFF1F6FF), Color(0xFFE4EEFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            width: 76,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1677FF),
                              borderRadius: BorderRadius.circular(7),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF1677FF).withOpacity(0.25),
                                  blurRadius: 14,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                            child: Center(
                              child: getPlatformImage(peer.platform, size: 36),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      getOnline(8, peer.online),
                      Text(
                        'LAN',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _favorite
                            ? translate('Remove from Favorites')
                            : translate('Add to Favorites'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: _toggleFavorite,
                        icon: Icon(
                          _favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 20,
                          color: _favorite ? Colors.amber : muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Tooltip(
                    message: primaryLabel,
                    child: Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildPeerDetail(
                    Icons.person_outline_rounded,
                    peer.username.isEmpty ? '-' : peer.username,
                    muted,
                  ),
                  const SizedBox(height: 3),
                  _buildPeerDetail(
                    Icons.desktop_windows_outlined,
                    peer.hostname.isEmpty ? secondaryLabel : peer.hostname,
                    muted,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ElevatedButton(
                            onPressed: () => widget.connect(context, peer.id),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: const Color(0xFF1677FF),
                              backgroundColor: isDark
                                  ? const Color(0xFF26354D)
                                  : const Color(0xFFF0F6FF),
                              elevation: 0,
                            ),
                            child: Text(
                              translate('Connect'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(color: border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: checkBoxOrActionMoreLandscape(
                          peer,
                          isTile: false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        child,
        if (_shouldBuildPasswordIcon(peer))
          Positioned(
            top: 4,
            left: 12,
            child: Icon(Icons.key, size: 12, color: Colors.white),
          ),
      ],
    );
  }

  Widget _buildPeerDetail(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
      ],
    );
  }

  Widget checkBoxOrActionMorePortrait(Peer peer) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: selected
            ? Icon(Icons.check_box, color: MyTheme.accent)
            : Icon(Icons.check_box_outline_blank),
      );
    } else {
      return InkWell(
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.more_vert),
        ),
        onTapDown: (e) {
          final x = e.globalPosition.dx;
          final y = e.globalPosition.dy;
          _menuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onTap: () {
          _showPeerMenu(peer.id);
        },
      );
    }
  }

  Widget checkBoxOrActionMoreLandscape(Peer peer, {required bool isTile}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      final icon = selected
          ? Icon(Icons.check_box, color: MyTheme.accent)
          : Icon(Icons.check_box_outline_blank);
      bool last = peerTabModel.isShiftDown && peer.id == peerTabModel.lastId;
      double right = isTile ? 4 : 0;
      if (last) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: MyTheme.accent, width: 1),
          ),
          child: icon,
        ).marginOnly(right: right);
      } else {
        return icon.marginOnly(right: right);
      }
    } else {
      return _actionMore(peer);
    }
  }

  Widget _actionMore(Peer peer) => Listener(
        onPointerDown: (e) {
          final x = e.position.dx;
          final y = e.position.dy;
          _menuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onPointerUp: (_) => _showPeerMenu(peer.id),
        child: build_more(context),
      );

  bool _shouldBuildPasswordIcon(Peer peer) {
    return false;
  }

  /// Show the peer menu and handle user's choice.
  /// User might remove the peer or send a file to the peer.
  void _showPeerMenu(String id) async {
    await mod_menu.showMenu(
      context: context,
      position: _menuPos,
      items: await super.widget.popupMenuEntryBuilder(context),
      elevation: 8,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

abstract class BasePeerCard extends StatelessWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final EdgeInsets? menuPadding;

  BasePeerCard({
    required this.peer,
    required this.tab,
    this.menuPadding,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _PeerCard(
      peer: peer,
      tab: tab,
      connect: (BuildContext context, String id) =>
          connectInPeerTab(context, peer, tab),
      popupMenuEntryBuilder: _buildPopupMenuEntry,
    );
  }

  Future<List<mod_menu.PopupMenuEntry<String>>> _buildPopupMenuEntry(
    BuildContext context,
  ) async =>
      (await _buildMenuItems(context))
          .map(
            (e) => e.build(
              context,
              const MenuConfig(
                commonColor: CustomPopupMenuTheme.commonColor,
                height: CustomPopupMenuTheme.height,
                dividerHeight: CustomPopupMenuTheme.dividerHeight,
              ),
            ),
          )
          .expand((i) => i)
          .toList();

  @protected
  Future<List<MenuEntryBase<String>>> _buildMenuItems(BuildContext context);

  MenuEntryBase<String> _connectCommonAction(
    BuildContext context,
    String title, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
    bool isTerminal = false,
    bool isTerminalRunAsAdmin = false,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(title, style: style),
      proc: () {
        if (isTerminalRunAsAdmin) {
          setEnvTerminalAdmin();
        }
        connectInPeerTab(
          context,
          peer,
          tab,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTcpTunneling: isTcpTunneling,
          isRDP: isRDP,
          isTerminal: isTerminal || isTerminalRunAsAdmin,
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _connectAction(BuildContext context) {
    return _connectCommonAction(
      context,
      (peer.alias.isEmpty
          ? translate('Connect')
          : '${translate('Connect')} ${peer.id}'),
    );
  }

  @protected
  MenuEntryBase<String> _transferFileAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('Transfer file'),
      isFileTransfer: true,
    );
  }

  @protected
  MenuEntryBase<String> _viewCameraAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('View camera'),
      isViewCamera: true,
    );
  }

  @protected
  MenuEntryBase<String> _terminalAction(BuildContext context) {
    return _connectCommonAction(
      context,
      '${translate('Terminal')} (beta)',
      isTerminal: true,
    );
  }

  @protected
  MenuEntryBase<String> _terminalRunAsAdminAction(BuildContext context) {
    return _connectCommonAction(
      context,
      '${translate('Terminal (Run as administrator)')} (beta)',
      isTerminalRunAsAdmin: true,
    );
  }

  @protected
  MenuEntryBase<String> _tcpTunnelingAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('TCP tunneling'),
      isTcpTunneling: true,
    );
  }

  @protected
  MenuEntryBase<String> _rdpAction(BuildContext context, String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Container(
        alignment: AlignmentDirectional.center,
        height: CustomPopupMenuTheme.height,
        child: Row(
          children: [
            Text(translate('RDP'), style: style),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Transform.scale(
                  scale: 0.8,
                  child: IconButton(
                    icon: const Icon(Icons.edit),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      _rdpDialog(id);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      proc: () {
        connectInPeerTab(context, peer, tab, isRDP: true);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _wolAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(translate('WOL'), style: style),
      proc: () {
        bind.mainWol(id: id);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  /// Only available on Windows.
  @protected
  MenuEntryBase<String> _createShortCutAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) =>
          Text(translate('Create desktop shortcut'), style: style),
      proc: () {
        bind.mainCreateShortcut(id: id);
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  Future<MenuEntryBase<String>> _openNewConnInAction(
    String id,
    String label,
    String key,
  ) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate(label),
      getter: () async => mainGetPeerBoolOptionSync(id, key),
      setter: (bool v) async {
        await bind.mainSetPeerOption(
          id: id,
          key: key,
          value: bool2option(key, v),
        );
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  _openInTabsAction(String id) async =>
      await _openNewConnInAction(id, 'Open in New Tab', kOptionOpenInTabs);

  _openInWindowsAction(String id) async => await _openNewConnInAction(
        id,
        'Open in new window',
        kOptionOpenInWindows,
      );

  // ignore: unused_element
  _openNewConnInOptAction(String id) async =>
      mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs)
          ? await _openInWindowsAction(id)
          : await _openInTabsAction(id);

  @protected
  MenuEntryBase<String> _renameAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) =>
          Text(translate('Rename'), style: style),
      proc: () async {
        String oldName = await _getAlias(id);
        renameDialog(
          oldName: oldName,
          onSubmit: (String newName) async {
            if (newName != oldName) {
              await bind.mainSetPeerAlias(id: id, alias: newName);
              showToast(translate('Successful'));
              _update();
            }
          },
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _removeAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(translate('Delete'), style: style?.copyWith(color: Colors.red)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Transform.scale(
                scale: 0.8,
                child: Icon(Icons.delete_forever, color: Colors.red),
              ),
            ).marginOnly(right: 4),
          ),
        ],
      ),
      proc: () {
        onSubmit() async {
          switch (tab) {
            case PeerTabIndex.recent:
              await bind.mainRemovePeer(id: id);
              bind.mainLoadRecentPeers();
              break;
            case PeerTabIndex.fav:
              final favs = (await bind.mainGetFav()).toList();
              if (favs.remove(id)) {
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
              }
              break;
            case PeerTabIndex.lan:
              await bind.mainRemoveDiscovered(id: id);
              bind.mainLoadLanPeers();
              break;
          }
          showToast(translate('Successful'));
        }

        deleteConfirmDialog(
          onSubmit,
          '${translate('Delete')} "${peer.alias.isEmpty ? formatID(peer.id) : peer.alias}"?',
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addFavAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(translate('Add to Favorites'), style: style),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Transform.scale(
                scale: 0.8,
                child: Icon(Icons.star_outline),
              ),
            ).marginOnly(right: 4),
          ),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (!favs.contains(id)) {
            favs.add(id);
            await bind.mainStoreFav(favs: favs);
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _rmFavAction(
    String id,
    Future<void> Function() reloadFunc,
  ) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(translate('Remove from Favorites'), style: style),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Transform.scale(scale: 0.8, child: Icon(Icons.star)),
            ).marginOnly(right: 4),
          ),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (favs.remove(id)) {
            await bind.mainStoreFav(favs: favs);
            await reloadFunc();
          }
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  Future<String> _getAlias(String id) async =>
      await bind.mainGetPeerOption(id: id, key: 'alias');

  @protected
  void _update();
}

class RecentPeerCard extends BasePeerCard {
  RecentPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
          peer: peer,
          tab: PeerTabIndex.recent,
          menuPadding: menuPadding,
          key: key,
        );

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
    BuildContext context,
  ) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      _viewCameraAction(context),
      _terminalAction(context),
    ];

    if (peer.platform == kPeerPlatformWindows) {
      menuItems.add(_terminalRunAsAdminAction(context));
    }

    final List favs = (await bind.mainGetFav()).toList();

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    if (isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadRecentPeers();
}

class FavoritePeerCard extends BasePeerCard {
  FavoritePeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
          peer: peer,
          tab: PeerTabIndex.fav,
          menuPadding: menuPadding,
          key: key,
        );

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
    BuildContext context,
  ) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      _viewCameraAction(context),
      _terminalAction(context),
    ];

    if (peer.platform == kPeerPlatformWindows) {
      menuItems.add(_terminalRunAsAdminAction(context));
    }

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    if (isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    menuItems.add(
      _rmFavAction(peer.id, () async {
        await bind.mainLoadFavPeers();
      }),
    );

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadFavPeers();
}

class DiscoveredPeerCard extends BasePeerCard {
  DiscoveredPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
          peer: peer,
          tab: PeerTabIndex.lan,
          menuPadding: menuPadding,
          key: key,
        );

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
    BuildContext context,
  ) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      _viewCameraAction(context),
      _terminalAction(context),
    ];

    if (peer.platform == kPeerPlatformWindows) {
      menuItems.add(_terminalRunAsAdminAction(context));
    }

    final List favs = (await bind.mainGetFav()).toList();

    if (isDesktop && peer.platform != kPeerPlatformAndroid) {
      menuItems.add(_tcpTunnelingAction(context));
    }
    // menuItems.add(await _openNewConnInOptAction(peer.id));
    if (isWindows && peer.platform == kPeerPlatformWindows) {
      menuItems.add(_rdpAction(context, peer.id));
    }
    menuItems.add(_wolAction(peer.id));
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadLanPeers();
}

void _rdpDialog(String id) async {
  final maxLength = bind.mainMaxEncryptLen();
  final port = await bind.mainGetPeerOption(id: id, key: 'rdp_port');
  final username = await bind.mainGetPeerOption(id: id, key: 'rdp_username');
  final portController = TextEditingController(text: port);
  final userController = TextEditingController(text: username);
  final passwordController = TextEditingController(
    text: await bind.mainGetPeerOption(id: id, key: 'rdp_password'),
  );
  RxBool secure = true.obs;

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      String port = portController.text.trim();
      String username = userController.text;
      String password = passwordController.text;
      await bind.mainSetPeerOption(id: id, key: 'rdp_port', value: port);
      await bind.mainSetPeerOption(
        id: id,
        key: 'rdp_username',
        value: username,
      );
      await bind.mainSetPeerOption(
        id: id,
        key: 'rdp_password',
        value: password,
      );
      showToast(translate('Successful'));
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('RDP Settings')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isDesktop
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        child: Text(
                          "${translate('Port')}:",
                          textAlign: TextAlign.right,
                        ).marginOnly(right: 10),
                      )
                    : SizedBox.shrink(),
                Expanded(
                  child: TextField(
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$',
                        ),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: isDesktop ? null : translate('Port'),
                      hintText: '3389',
                    ),
                    controller: portController,
                    autofocus: true,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: isDesktop ? 8 : 0),
            Obx(
              () => Row(
                children: [
                  stateGlobal.isPortrait.isFalse
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 140),
                          child: Text(
                            "${translate('Username')}:",
                            textAlign: TextAlign.right,
                          ).marginOnly(right: 10),
                        )
                      : SizedBox.shrink(),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: isDesktop ? null : translate('Username'),
                      ),
                      controller: userController,
                    ).workaroundFreezeLinuxMint(),
                  ),
                ],
              ).marginOnly(bottom: stateGlobal.isPortrait.isFalse ? 8 : 0),
            ),
            Obx(
              () => Row(
                children: [
                  stateGlobal.isPortrait.isFalse
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 140),
                          child: Text(
                            "${translate('Password')}:",
                            textAlign: TextAlign.right,
                          ).marginOnly(right: 10),
                        )
                      : SizedBox.shrink(),
                  Expanded(
                    child: Obx(
                      () => TextField(
                        obscureText: secure.value,
                        maxLength: maxLength,
                        decoration: InputDecoration(
                          labelText: isDesktop ? null : translate('Password'),
                          suffixIcon: IconButton(
                            onPressed: () => secure.value = !secure.value,
                            icon: Icon(
                              secure.value
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        controller: passwordController,
                      ).workaroundFreezeLinuxMint(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

Widget getOnline(double rightPadding, bool online) {
  return Tooltip(
    message: translate(online ? 'Online' : 'Offline'),
    waitDuration: const Duration(seconds: 1),
    child: Padding(
      padding: EdgeInsets.fromLTRB(0, 4, rightPadding, 4),
      child: CircleAvatar(
        radius: 3,
        backgroundColor: online ? Colors.green : kColorWarn,
      ),
    ),
  );
}

Widget build_more(BuildContext context, {bool invert = false}) {
  final RxBool hover = false.obs;
  return InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () {},
    onHover: (value) => hover.value = value,
    child: Obx(
      () => CircleAvatar(
        radius: 14,
        backgroundColor: hover.value
            ? (invert
                ? Theme.of(context).colorScheme.background
                : Theme.of(context).scaffoldBackgroundColor)
            : (invert
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background),
        child: Icon(
          Icons.more_vert,
          size: 18,
          color: hover.value
              ? Theme.of(context).textTheme.titleLarge?.color
              : Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.5),
        ),
      ),
    ),
  );
}

void connectInPeerTab(
  BuildContext context,
  Peer peer,
  PeerTabIndex tab, {
  bool isFileTransfer = false,
  bool isViewCamera = false,
  bool isTcpTunneling = false,
  bool isRDP = false,
  bool isTerminal = false,
}) async {
  connect(
    context,
    peer.id,
    password: '',
    username: peer.username,
    isFileTransfer: isFileTransfer,
    isTerminal: isTerminal,
    isViewCamera: isViewCamera,
    isTcpTunneling: isTcpTunneling,
    isRDP: isRDP,
  );
}
