import 'package:flutter_hbb/common/widgets/autocomplete.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

Peer _peer({
  required String id,
  String alias = '',
  String username = '',
  String hostname = '',
  bool online = false,
}) {
  final peer = Peer(
    id: id,
    username: username,
    hostname: hostname,
    alias: alias,
    fingerprint: '',
    platform: '',
    rdpPort: '',
    rdpUsername: '',
  );
  peer.online = online;
  return peer;
}

void main() {
  test('merged autocomplete peers keep recent metadata and LAN state', () {
    final peers = mergeAutocompletePeers(
      recentPeers: [
        _peer(id: '123456789', alias: 'Office PC', username: 'recent-user'),
      ],
      lanPeers: [_peer(id: '123456789', username: 'lan-user', online: true)],
    );

    expect(peers, hasLength(1));
    expect(peers.single.id, '123456789');
    expect(peers.single.alias, 'Office PC');
    expect(peers.single.username, 'recent-user');
    expect(peers.single.online, isTrue);
  });

  test('peer copies preserve online state', () {
    final peer = _peer(id: '987654321', online: true);

    expect(Peer.copy(peer).online, isTrue);
  });

  test('rest recent endpoints remain available without cloud status', () {
    final peers = mergeAutocompletePeers(restRecentPeerIds: ['host.lan:21118']);

    expect(peers, hasLength(1));
    expect(peers.single.id, 'host.lan:21118');
    expect(peers.single.online, isFalse);
  });
}
