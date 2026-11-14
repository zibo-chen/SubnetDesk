import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const String favoriteUngroupedId = '__ungrouped__';

bool isDeviceFingerprint(String value) =>
    RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);

String normalizeFavoriteGroupName(String value) => value.trim();

class FavoriteGroup {
  const FavoriteGroup({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, String> toJson() => {'id': id, 'name': name};
}

class FavoriteGroupModel extends ChangeNotifier {
  FavoriteGroupModel({
    String Function()? read,
    void Function(String value)? write,
  }) : _read =
           read ??
           (() => bind.getLocalFlutterOption(k: kOptionFavoritePeerGroups)),
       _write =
           write ??
           ((value) => bind.setLocalFlutterOption(
             k: kOptionFavoritePeerGroups,
             v: value,
           ));

  final String Function() _read;
  final void Function(String value) _write;

  final List<FavoriteGroup> _groups = [];
  final Map<String, String> _peerGroups = {};
  bool _loaded = false;
  int _nextId = 0;
  int _revision = 0;
  List<FavoriteGroup> _committedGroups = [];
  Map<String, String> _committedPeerGroups = {};

  List<FavoriteGroup> get groups => List.unmodifiable(_groups);

  void load() {
    if (_loaded) return;
    _loaded = true;

    final raw = _read();
    if (raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('favorite group data is not an object');
      }

      final groupIds = <String>{};
      final groupNames = <String>{};
      final rawGroups = decoded['groups'];
      if (rawGroups is List) {
        for (final item in rawGroups) {
          if (item is! Map) continue;
          final id = item['id'];
          final name = item['name'];
          if (id is! String || name is! String) continue;
          final normalizedName = normalizeFavoriteGroupName(name);
          final normalizedKey = normalizedName.toLowerCase();
          if (id.isEmpty ||
              normalizedName.isEmpty ||
              groupIds.contains(id) ||
              groupNames.contains(normalizedKey)) {
            continue;
          }
          groupIds.add(id);
          groupNames.add(normalizedKey);
          _groups.add(FavoriteGroup(id: id, name: normalizedName));
        }
      }

      final rawPeerGroups = decoded['peer_groups'];
      if (rawPeerGroups is Map) {
        for (final entry in rawPeerGroups.entries) {
          final peerId = entry.key;
          final groupId = entry.value;
          if (peerId is String &&
              peerId.isNotEmpty &&
              groupId is String &&
              groupIds.contains(groupId)) {
            final key = isDeviceFingerprint(peerId)
                ? peerId.toLowerCase()
                : peerId;
            _peerGroups[key] = groupId;
          }
        }
      }
      _committedGroups = List.of(_groups);
      _committedPeerGroups = Map.of(_peerGroups);
    } catch (error) {
      _groups.clear();
      _peerGroups.clear();
      debugPrint('failed to load favorite peer groups: $error');
    }
  }

  bool createGroup(String value) {
    load();
    final name = normalizeFavoriteGroupName(value);
    if (name.isEmpty || name.runes.length > 32 || _containsName(name)) {
      return false;
    }

    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (_groups.any((group) => group.id == id)) {
      id = '${id}_${_nextId++}';
    }
    _groups.add(FavoriteGroup(id: id, name: name));
    _saveAndNotify();
    return true;
  }

  bool renameGroup(String id, String value) {
    load();
    final index = _groups.indexWhere((group) => group.id == id);
    final name = normalizeFavoriteGroupName(value);
    if (index < 0 ||
        name.isEmpty ||
        name.runes.length > 32 ||
        _containsName(name, exceptGroupId: id)) {
      return false;
    }
    if (_groups[index].name == name) return true;

    _groups[index] = FavoriteGroup(id: id, name: name);
    _saveAndNotify();
    return true;
  }

  bool deleteGroup(String id) {
    load();
    if (!_groups.any((group) => group.id == id)) return false;
    _groups.removeWhere((group) => group.id == id);

    _peerGroups.removeWhere((_, groupId) => groupId == id);
    _saveAndNotify();
    return true;
  }

  void setPeerGroup(String peerId, String? groupId) =>
      setPeerGroups([peerId], groupId);

  /// One persisted update and one notification, even for hundreds of peers.
  void setPeerGroups(Iterable<String> peerIds, String? groupId) {
    load();
    if (groupId == favoriteUngroupedId) groupId = null;
    if (groupId != null && !_groups.any((group) => group.id == groupId)) return;
    var changed = false;
    for (final value in peerIds.toSet()) {
      if (!isDeviceFingerprint(value)) continue;
      final id = value.toLowerCase();
      if (id.isEmpty || _peerGroups[id] == groupId) continue;
      if (groupId == null) {
        changed = _peerGroups.remove(id) != null || changed;
      } else {
        _peerGroups[id] = groupId;
        changed = true;
      }
    }
    if (changed) _saveAndNotify();
  }

  /// The next single edit can be undone, without overwriting subsequent edits.
  bool Function() captureUndo() {
    load();
    final groups = List<FavoriteGroup>.of(_groups);
    final assignments = Map<String, String>.of(_peerGroups);
    final expectedRevision = _revision + 1;
    return () {
      if (_revision != expectedRevision) return false;
      _groups
        ..clear()
        ..addAll(groups);
      _peerGroups
        ..clear()
        ..addAll(assignments);
      _saveAndNotify();
      return true;
    };
  }

  void migratePeerKeys(Map<String, String> fingerprintByLegacyId) {
    load();
    var changed = false;
    for (final entry in fingerprintByLegacyId.entries) {
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(entry.value)) continue;
      final fingerprint = entry.value.toLowerCase();
      if (entry.key == fingerprint) continue;
      final assignment = _peerGroups.remove(entry.key);
      if (assignment != null) {
        _peerGroups.putIfAbsent(fingerprint, () => assignment);
        changed = true;
      }
    }
    if (changed) _saveAndNotify();
  }

  void removePeer(String peerId) {
    load();
    if (_peerGroups.remove(
          isDeviceFingerprint(peerId) ? peerId.toLowerCase() : peerId,
        ) !=
        null) {
      _saveAndNotify();
    }
  }

  String? groupIdForPeer(String peerId) {
    load();
    return _peerGroups[isDeviceFingerprint(peerId)
        ? peerId.toLowerCase()
        : peerId];
  }

  FavoriteGroup? groupById(String id) {
    load();
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  bool matches(String peerId, String? selectedGroupId) {
    load();
    if (selectedGroupId == null) return true;
    if (isDeviceFingerprint(peerId)) peerId = peerId.toLowerCase();
    if (selectedGroupId == favoriteUngroupedId) {
      return !_peerGroups.containsKey(peerId);
    }
    return _peerGroups[peerId] == selectedGroupId;
  }

  int countForGroup(Iterable<String> favoritePeerIds, String? groupId) {
    load();
    return favoritePeerIds.where((peerId) => matches(peerId, groupId)).length;
  }

  bool _containsName(String name, {String? exceptGroupId}) {
    final normalized = name.toLowerCase();
    return _groups.any(
      (group) =>
          group.id != exceptGroupId && group.name.toLowerCase() == normalized,
    );
  }

  void _saveAndNotify() {
    try {
      _write(
        jsonEncode({
          'version': 1,
          'groups': _groups.map((group) => group.toJson()).toList(),
          'peer_groups': _peerGroups,
        }),
      );
    } catch (_) {
      _groups
        ..clear()
        ..addAll(_committedGroups);
      _peerGroups
        ..clear()
        ..addAll(_committedPeerGroups);
      rethrow;
    }
    _committedGroups = List.of(_groups);
    _committedPeerGroups = Map.of(_peerGroups);
    _revision++;
    notifyListeners();
  }
}

final favoriteGroupModel = FavoriteGroupModel();
