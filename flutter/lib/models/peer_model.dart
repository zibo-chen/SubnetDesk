import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'platform_model.dart';

class Peer {
  final String id;
  String username; // pc username
  String hostname;
  String platform;
  String alias;
  String fingerprint;
  String rdpPort;
  String rdpUsername;
  // null means unverified/stale, not offline.
  bool? online;
  int lastSeen = 0;
  int lastChecked = 0;

  String getId() {
    if (alias != '') {
      return alias;
    }
    return id;
  }

  Peer.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? '',
        username = json['username'] ?? '',
        hostname = json['hostname'] ?? '',
        platform = json['platform'] ?? '',
        alias = json['alias'] ?? '',
        fingerprint = json['fingerprint'] ?? '',
        rdpPort = json['rdpPort'] ?? '',
        rdpUsername = json['rdpUsername'] ?? '' {
    online = json['online'] is bool ? json['online'] as bool : null;
    lastSeen = (json['last_seen'] as num?)?.toInt() ?? 0;
    lastChecked = (json['last_checked'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "username": username,
      "hostname": hostname,
      "platform": platform,
      "alias": alias,
      "fingerprint": fingerprint,
      "rdpPort": rdpPort,
      "rdpUsername": rdpUsername,
      "online": online,
      "last_seen": lastSeen,
      "last_checked": lastChecked,
    };
  }

  Peer({
    required this.id,
    required this.username,
    required this.hostname,
    required this.platform,
    required this.alias,
    required this.fingerprint,
    required this.rdpPort,
    required this.rdpUsername,
  });

  Peer.loading()
      : this(
          id: '...',
          username: '...',
          hostname: '...',
          platform: '...',
          alias: '',
          fingerprint: '',
          rdpPort: '',
          rdpUsername: '',
        );
  bool equal(Peer other) {
    return id == other.id &&
        username == other.username &&
        hostname == other.hostname &&
        platform == other.platform &&
        alias == other.alias &&
        fingerprint == other.fingerprint &&
        rdpPort == other.rdpPort &&
        rdpUsername == other.rdpUsername;
  }

  factory Peer.copy(Peer other) {
    final peer = Peer(
        id: other.id,
        username: other.username,
        hostname: other.hostname,
        platform: other.platform,
        alias: other.alias,
        fingerprint: other.fingerprint,
        rdpPort: other.rdpPort,
        rdpUsername: other.rdpUsername);
    peer.online = other.online;
    peer.lastSeen = other.lastSeen;
    peer.lastChecked = other.lastChecked;
    return peer;
  }
}

enum UpdateEvent { online, load }

int comparePeerStatus(Peer left, Peer right) {
  int rank(Peer peer) => peer.online == true ? 0 : (peer.online == null ? 1 : 2);
  final status = rank(left).compareTo(rank(right));
  return status != 0 ? status : left.id.compareTo(right.id);
}

typedef GetInitPeers = RxList<Peer> Function();

class Peers extends ChangeNotifier {
  final String name;
  final String loadEvent;
  List<Peer> peers = List.empty(growable: true);
  // Part of the peers that are not in the rest peers list.
  // When there're too many peers, we may want to load the front 100 peers first,
  // so we can see peers in UI quickly. `restPeerIds` is the rest peers' ids.
  // And then load all peers later.
  List<String> restPeerIds = List.empty(growable: true);
  final GetInitPeers? getInitPeers;
  UpdateEvent event = UpdateEvent.load;

  Peers(
      {required this.name,
      required this.getInitPeers,
      required this.loadEvent}) {
    peers = getInitPeers?.call() ?? [];
    platformFFI.registerEventHandler(loadEvent, name, (evt) async {
      _updatePeers(evt);
    });
  }

  @override
  void dispose() {
    platformFFI.unregisterEventHandler(loadEvent, name);
    super.dispose();
  }

  Peer getByIndex(int index) {
    if (index < peers.length) {
      return peers[index];
    } else {
      return Peer.loading();
    }
  }

  int getPeersCount() {
    return peers.length;
  }

  void _updatePeers(Map<String, dynamic> evt) {
    if (getInitPeers != null) {
      peers = getInitPeers?.call() ?? [];
    } else {
      peers = _decodePeers(evt['peers']);
    }

    restPeerIds = [];
    if (evt['ids'] != null) {
      restPeerIds = (evt['ids'] as String).split(',');
    }

    event = UpdateEvent.load;
    notifyListeners();
  }

  List<Peer> _decodePeers(String peersStr) {
    try {
      if (peersStr == "") return [];
      List<dynamic> peers = json.decode(peersStr);
      return peers.map((peer) {
        return Peer.fromJson(peer as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('peers(): $e');
    }
    return [];
  }
}
