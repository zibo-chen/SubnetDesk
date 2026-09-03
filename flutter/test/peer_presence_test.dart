import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rust payload preserves boolean, null and last-seen timestamps', () {
    final payload =
        jsonDecode(File('test/fixtures/peer_presence.json').readAsStringSync())
            as List;
    final peers = payload.map((json) => Peer.fromJson(json)).toList();
    expect(peers.map((peer) => peer.online), [true, false, null]);
    expect(peers.map((peer) => peer.lastSeen), [100000, 60000, 0]);
    for (final peer in peers) {
      expect(Peer.copy(peer).toJson(), peer.toJson());
      expect(Peer.fromJson(peer.toJson()).toJson(), peer.toJson());
    }
  });

  test('missing or string-encoded status is unknown, never offline', () {
    expect(Peer.fromJson({'id': 'legacy'}).online, isNull);
    expect(Peer.fromJson({'id': 'legacy', 'online': 'true'}).online, isNull);
  });

  test(
    'all peer lists accept offline, unknown and rediscovery events',
    () async {
      for (final event in [
        'load_lan_peers',
        'load_recent_peers',
        'load_fav_peers',
      ]) {
        final peers = Peers(
          name: 'test-$event',
          getInitPeers: null,
          loadEvent: event,
        );
        for (final status in <bool?>[true, false, null, true]) {
          await platformFFI.tryHandle({
            'name': event,
            'peers': jsonEncode([
              {'id': 'host:21118', 'online': status, 'last_seen': 1000},
            ]),
          });
          expect(peers.peers.single.online, status, reason: event);
          expect(peers.peers.single.lastSeen, 1000);
        }
        peers.dispose();
      }
    },
  );

  test('status sorting is deterministic and comparator is antisymmetric', () {
    final peers = [
      Peer.fromJson({'id': 'offline', 'online': false}),
      Peer.fromJson({'id': 'online-b', 'online': true}),
      Peer.fromJson({'id': 'unknown'}),
      Peer.fromJson({'id': 'online-a', 'online': true}),
    ];
    for (final a in peers) {
      expect(comparePeerStatus(a, a), 0);
      for (final b in peers) {
        expect(comparePeerStatus(a, b).sign, -comparePeerStatus(b, a).sign);
      }
    }
    peers.sort(comparePeerStatus);
    expect(peers.map((peer) => peer.id), [
      'online-a',
      'online-b',
      'unknown',
      'offline',
    ]);
  });
}
