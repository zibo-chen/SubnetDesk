import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import '../../../models/platform_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';

@visibleForTesting
List<Peer> mergeAutocompletePeers({
  Iterable<Peer> lanPeers = const [],
  Iterable<Peer> recentPeers = const [],
  Iterable<String> restRecentPeerIds = const [],
}) {
  final combinedPeers = <String, Peer>{};

  void addPeer(Peer peer) {
    if (peer.id.isEmpty) {
      return;
    }
    final existingPeer = combinedPeers[peer.id];
    if (existingPeer == null) {
      combinedPeers[peer.id] = Peer.copy(peer);
    } else if (peer.online) {
      existingPeer.online = true;
    }
  }

  for (final peer in lanPeers) {
    addPeer(peer);
  }
  for (final peer in recentPeers) {
    addPeer(peer);
  }
  for (final id in restRecentPeerIds) {
    if (id.isNotEmpty && !combinedPeers.containsKey(id)) {
      combinedPeers[id] = Peer.fromJson({'id': id});
    }
  }

  return combinedPeers.values.toList(growable: false);
}

class AllPeersLoader {
  List<Peer> peers = [];

  bool _isPeersLoading = false;
  bool _isPeersLoaded = false;
  void Function(VoidCallback)? _setState;
  bool _isCleared = false;

  bool get needLoad => !_isPeersLoaded && !_isPeersLoading;
  bool get isPeersLoaded => _isPeersLoaded;

  AllPeersLoader();

  void init(void Function(VoidCallback) setState) {
    _setState = setState;
    _isCleared = false;
    gFFI.recentPeersModel.addListener(_mergeAllPeers);
    gFFI.lanPeersModel.addListener(_mergeAllPeers);
  }

  void clear() {
    gFFI.recentPeersModel.removeListener(_mergeAllPeers);
    gFFI.lanPeersModel.removeListener(_mergeAllPeers);
    _setState = null;
    _isCleared = true;
  }

  Future<void> getAllPeers() async {
    if (!needLoad) {
      return;
    }
    _isPeersLoading = true;

    if (gFFI.recentPeersModel.peers.isEmpty) {
      bind.mainLoadRecentPeers();
    }
    if (gFFI.lanPeersModel.peers.isEmpty) {
      bind.mainLoadLanPeers();
    }
    final startTime = DateTime.now();
    _mergeAllPeers();
    final diffTime = DateTime.now().difference(startTime).inMilliseconds;
    if (diffTime < 100) {
      await Future.delayed(Duration(milliseconds: diffTime));
    }
  }

  void _mergeAllPeers() {
    if (_isCleared) {
      return;
    }
    peers = mergeAutocompletePeers(
      lanPeers: gFFI.lanPeersModel.peers,
      recentPeers: gFFI.recentPeersModel.peers,
      restRecentPeerIds: gFFI.recentPeersModel.restPeerIds,
    );
    _scheduleSetState(() {
      _isPeersLoading = false;
      _isPeersLoaded = true;
    });
  }

  void _scheduleSetState(VoidCallback callback) {
    if (_isCleared) {
      return;
    }
    final setState = _setState;
    if (setState == null) {
      callback();
    } else {
      setState(callback);
    }
  }
}

class AutocompletePeerTile extends StatefulWidget {
  final VoidCallback onSelect;
  final Peer peer;

  const AutocompletePeerTile({
    Key? key,
    required this.onSelect,
    required this.peer,
  }) : super(key: key);

  @override
  AutocompletePeerTileState createState() => AutocompletePeerTileState();
}

class AutocompletePeerTileState extends State<AutocompletePeerTile> {
  @override
  Widget build(BuildContext context) {
    final double tileRadius = 5;
    final name =
        '${widget.peer.username}${widget.peer.username.isNotEmpty && widget.peer.hostname.isNotEmpty ? '@' : ''}${widget.peer.hostname}';
    final greyStyle = TextStyle(
      fontSize: 11,
      color: Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.6),
    );
    final child = GestureDetector(
      onTap: () => widget.onSelect(),
      child: Padding(
        padding: EdgeInsets.only(left: 5, right: 5),
        child: Container(
          height: 42,
          margin: EdgeInsets.only(bottom: 5),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: str2color(
                    '${widget.peer.id}${widget.peer.platform}',
                    0x7f,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(tileRadius),
                    bottomLeft: Radius.circular(tileRadius),
                  ),
                ),
                alignment: Alignment.center,
                width: 42,
                height: null,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: getPlatformImage(widget.peer.platform, size: 30),
                ),
              ),
              Expanded(
                child: Container(
                  padding: EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(tileRadius),
                      bottomRight: Radius.circular(tileRadius),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(top: 2),
                          child: Container(
                            margin: EdgeInsets.only(top: 2),
                            child: Column(
                              children: [
                                Container(
                                  margin: EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      getOnline(8, widget.peer.online),
                                      Expanded(
                                        child: Text(
                                          widget.peer.alias.isEmpty
                                              ? formatID(widget.peer.id)
                                              : widget.peer.alias,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleSmall,
                                        ),
                                      ),
                                      widget.peer.alias.isNotEmpty
                                          ? Padding(
                                              padding: const EdgeInsets.only(
                                                left: 5,
                                                right: 5,
                                              ),
                                              child: Text(
                                                "(${widget.peer.id})",
                                                style: greyStyle,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            )
                                          : Container(),
                                    ],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    name,
                                    style: greyStyle,
                                    textAlign: TextAlign.start,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
            ],
          ),
        ),
      ),
    );
    return child;
  }
}
