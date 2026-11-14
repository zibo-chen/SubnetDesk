import 'dart:convert';

import 'package:flutter_hbb/models/favorite_group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates groups and assigns favorite peers', () {
    var stored = '';
    final model = FavoriteGroupModel(
      read: () => stored,
      write: (value) => stored = value,
    );

    expect(model.createGroup(' 办公室 '), isTrue);
    expect(model.createGroup('办公室'), isFalse);
    expect(model.createGroup('a' * 33), isFalse);
    expect(model.groups.single.name, '办公室');

    final groupId = model.groups.single.id;
    model.setPeerGroup('a' * 64, groupId);

    expect(model.matches('a' * 64, groupId), isTrue);
    expect(model.matches('a' * 64, favoriteUngroupedId), isFalse);
    expect(model.countForGroup(['a' * 64, 'b' * 64], groupId), 1);
    expect(model.countForGroup(['a' * 64, 'b' * 64], favoriteUngroupedId), 1);
    expect(jsonDecode(stored)['version'], 1);
  });

  test('deleting a group keeps its peers as ungrouped favorites', () {
    var stored = '';
    final model = FavoriteGroupModel(
      read: () => stored,
      write: (value) => stored = value,
    );

    model.createGroup('服务器');
    final groupId = model.groups.single.id;
    model.setPeerGroup('a' * 64, groupId);

    expect(model.deleteGroup(groupId), isTrue);
    expect(model.groups, isEmpty);
    expect(model.groupIdForPeer('a' * 64), isNull);
    expect(model.matches('a' * 64, favoriteUngroupedId), isTrue);
  });

  test('loads valid data and ignores invalid group references', () {
    final stored = jsonEncode({
      'version': 1,
      'groups': [
        {'id': 'office', 'name': '办公室'},
      ],
      'peer_groups': {'a' * 64: 'office', 'b' * 64: 'missing'},
    });
    final model = FavoriteGroupModel(read: () => stored, write: (_) {});

    model.load();

    expect(model.groups.single.name, '办公室');
    expect(model.groupIdForPeer('a' * 64), 'office');
    expect(model.groupIdForPeer('b' * 64), isNull);
  });
  test('96 fingerprint-keyed assignments use one write and can be undone', () {
    var stored = '';
    var writes = 0;
    final model = FavoriteGroupModel(
      read: () => stored,
      write: (value) {
        stored = value;
        writes++;
      },
    );
    model.createGroup('Office');
    final ids = List.generate(96, (i) => i.toRadixString(16).padLeft(64, '0'));
    final undo = model.captureUndo();
    final before = writes;
    model.setPeerGroups(ids, model.groups.single.id);
    expect(writes, before + 1);
    expect(model.countForGroup(ids, model.groups.single.id), 96);
    expect(undo(), isTrue);
    expect(model.countForGroup(ids, favoriteUngroupedId), 96);
    expect(undo(), isFalse);
  });
  test(
    'legacy group keys migrate to fingerprint once without replacing existing groups',
    () {
      var stored = jsonEncode({
        'version': 1,
        'groups': [
          {'id': 'office', 'name': 'Office'},
        ],
        'peer_groups': {'10.1.1.20:21118': 'office'},
      });
      final model = FavoriteGroupModel(
        read: () => stored,
        write: (value) => stored = value,
      );
      final fp = 'a' * 64;
      model.migratePeerKeys({
        '10.1.1.20:21118': fp,
        'other': 'not a fingerprint',
      });
      expect(model.groupIdForPeer(fp), model.groups.single.id);
      expect(model.groupIdForPeer('10.1.1.20:21118'), isNull);
      final reloaded = FavoriteGroupModel(read: () => stored, write: (_) {});
      expect(reloaded.groupIdForPeer(fp), model.groups.single.id);
    },
  );
  test(
    'failed storage rolls back a batch and later edits block stale undo',
    () {
      var fail = false;
      final model = FavoriteGroupModel(
        read: () => '',
        write: (_) {
          if (fail) throw StateError('disk full');
        },
      );
      model.createGroup('Office');
      fail = true;
      expect(
        () => model.setPeerGroups(['a' * 64, 'b' * 64], model.groups.single.id),
        throwsStateError,
      );
      expect(model.groupIdForPeer('a' * 64), isNull);
      fail = false;
      final undo = model.captureUndo();
      model.setPeerGroups(['a' * 64], model.groups.single.id);
      model.createGroup('Later');
      expect(undo(), isFalse);
      expect(model.groups.length, 2);
    },
  );
  test(
    'new assignments reject address/name keys and canonicalize fingerprints',
    () {
      final model = FavoriteGroupModel(read: () => '', write: (_) {});
      model.createGroup('Office');
      final id = model.groups.single.id;
      model.setPeerGroups(['10.0.0.1', 'office-pc', 'A' * 64], id);
      expect(model.groupIdForPeer('10.0.0.1'), isNull);
      expect(model.groupIdForPeer('office-pc'), isNull);
      expect(model.groupIdForPeer('a' * 64), id);
    },
  );
}
