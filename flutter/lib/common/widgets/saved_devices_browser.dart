part of 'lan_workspace.dart';

/// Device management stays separate from the LAN adapter and its identity store.
class _SavedDevicesBrowser extends StatefulWidget {
  const _SavedDevicesBrowser({
    required this.nearby,
    required this.recent,
    required this.favorites,
    required this.groups,
    required this.groupFor,
    required this.source,
    required this.onSource,
    required this.onAssignGroups,
    required this.captureUndo,
    required this.onManageGroup,
    required this.onAdd,
    required this.onRefresh,
    required this.onConnect,
    required this.actions,
  });
  final List<WorkspaceDevice> nearby, recent, favorites;
  final List<FavoriteGroup> groups;
  final String? Function(String)? groupFor;
  final int source;
  final ValueChanged<int> onSource;
  final void Function(Iterable<String>, String?)? onAssignGroups;
  final bool Function() Function()? captureUndo;
  final Future<void> Function(String, String?) onManageGroup;
  final VoidCallback onAdd, onRefresh;
  final void Function(WorkspaceDevice, LanTool) onConnect;
  final Widget Function(WorkspaceDevice, {Key? key}) actions;

  @override
  State<_SavedDevicesBrowser> createState() => _SavedDevicesBrowserState();
}

class _SavedDevicesBrowserState extends State<_SavedDevicesBrowser> {
  static const pageSize = 12;
  final _search = TextEditingController();
  final _groupSearch = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <String>{};
  String? _group;
  String _status = 'all';
  int _page = 0;
  String t(String zh, String en) => subnetText(context, zh, en);
  bool get favorites => widget.source == 1;
  String groupName(String? id) => id == null
      ? t('全部收藏', 'All favorites')
      : id == favoriteUngroupedId
      ? t('未分组', 'Ungrouped')
      : widget.groups.where((g) => g.id == id).firstOrNull?.name ??
            t('未分组', 'Ungrouped');
  String? groupFor(String id) => widget.groupFor?.call(id);
  int count(String? id) => widget.favorites
      .where(
        (d) =>
            id == null ||
            (id == favoriteUngroupedId
                ? groupFor(d.id) == null
                : groupFor(d.id) == id),
      )
      .length;
  List<WorkspaceDevice> get scoped {
    final map = <String, WorkspaceDevice>{};
    final peers = favorites
        ? widget.favorites
        : widget.source == 0
        ? widget.nearby
        : widget.source == 3
        ? widget.recent
        : [...widget.recent, ...widget.favorites, ...widget.nearby];
    for (final d in peers) {
      map[d.id] = d;
    }
    return map.values
        .where(
          (d) =>
              !favorites ||
              _group == null ||
              (_group == favoriteUngroupedId
                  ? groupFor(d.id) == null
                  : groupFor(d.id) == _group),
        )
        .toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
  }

  List<WorkspaceDevice> get filtered {
    final query = _search.text.trim().toLowerCase();
    return scoped
        .where(
          (d) =>
              '${d.displayName} ${d.connectionAddress} ${d.hostname}'
                  .toLowerCase()
                  .contains(query) &&
              (_status == 'all' ||
                  (_status == 'reachable'
                      ? d.online == true
                      : _status == 'unreachable'
                      ? d.online == false
                      : d.online == null)),
        )
        .toList();
  }

  void resetSelection() {
    _selected.clear();
    _page = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void selectGroup(String? value) {
    setState(() {
      _group = value;
      _search.clear();
      resetSelection();
    });
    widget.onSource(1);
  }

  @override
  void didUpdateWidget(covariant _SavedDevicesBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _search.clear();
      resetSelection();
    }
    _selected.retainAll(widget.favorites.map((d) => d.id).toSet());
    if (_group != null &&
        _group != favoriteUngroupedId &&
        !widget.groups.any((g) => g.id == _group))
      _group = null;
  }

  @override
  void dispose() {
    _search.dispose();
    _groupSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void toggle(String id) {
    if (!isDeviceFingerprint(id)) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> moveSelected() async {
    if (_selected.isEmpty || widget.onAssignGroups == null) return;
    var target = favoriteUngroupedId;
    var search = '';
    final ids = Set<String>.of(_selected);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          scrollable: true,
          title: Text(t('移动到分组', 'Move to group')),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t(
                      '已选择 ${ids.length} 台设备',
                      '${ids.length} devices selected',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: t('搜索目标分组', 'Search destination groups'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) =>
                      update(() => search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final group in [
                          FavoriteGroup(
                            id: favoriteUngroupedId,
                            name: t('未分组', 'Ungrouped'),
                          ),
                          ...widget.groups,
                        ])
                          if (group.name.toLowerCase().contains(search))
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              title: Text(group.name),
                              secondary: Text('${count(group.id)}'),
                              value: group.id,
                              groupValue: target,
                              onChanged: (value) =>
                                  update(() => target = value ?? target),
                            ),
                        if (![
                          t('未分组', 'Ungrouped'),
                          ...widget.groups.map((g) => g.name),
                        ].any((name) => name.toLowerCase().contains(search)))
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(t('没有匹配的分组', 'No matching groups')),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${groupName(target)}: ${count(target)} → ${count(target) + ids.where((id) => (groupFor(id) ?? favoriteUngroupedId) != target).length}',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t('移动后可撤销', 'You can undo this move'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(c).hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(t('取消', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, target),
              child: Text(
                t('移动 ${ids.length} 台设备', 'Move ${ids.length} devices'),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final changed = ids
        .where((id) => (groupFor(id) ?? favoriteUngroupedId) != result)
        .toList();
    if (changed.isEmpty) return;
    final undo = widget.captureUndo?.call();
    try {
      widget.onAssignGroups!(changed, result);
      setState(() => _selected.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('已移动 ${changed.length} 台设备', 'Moved ${changed.length} devices'),
          ),
          action: undo == null
              ? null
              : SnackBarAction(
                  label: t('撤销', 'Undo'),
                  onPressed: () {
                    try {
                      if (!undo())
                        showToast(
                          t(
                            '分组已有新更改，无法撤销',
                            'Groups changed again. Cannot undo.',
                          ),
                        );
                    } catch (error) {
                      debugPrint('Undoing groups failed: $error');
                      showToast(
                        t('无法保存分组，请重试', 'Could not save groups. Try again.'),
                      );
                    }
                  },
                ),
        ),
      );
    } catch (error) {
      debugPrint('Moving favorite devices failed: $error');
      showToast(t('无法保存分组，请重试', 'Could not save groups. Try again.'));
    }
  }

  Widget groupEntry(String? id) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: favorites && _group == id
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => selectGroup(id),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      groupName(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: favorites && _group == id
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${count(id)}',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          ),
          if (id != null && id != favoriteUngroupedId)
            PopupMenuButton<String>(
              tooltip: t('管理分组', 'Manage group') + ' ${groupName(id)}',
              onSelected: (action) => widget.onManageGroup(action, id),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(t('重命名分组', 'Rename group')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t('删除分组', 'Delete group')),
                ),
              ],
              icon: const Icon(Icons.more_horiz, size: 20),
            ),
        ],
      ),
    ),
  );

  Widget sidebar() => Container(
    key: const ValueKey('saved-device-groups'),
    width: math.max(
      240,
      math.min(342, MediaQuery.sizeOf(context).width * .213),
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('分组', 'Groups'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => widget.onManageGroup('new', null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(t('新建分组', 'New group')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _groupSearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: t('搜索分组', 'Search groups'),
          ),
        ),
        const SizedBox(height: 18),
        groupEntry(null),
        groupEntry(favoriteUngroupedId),
        const Divider(height: 28),
        Expanded(
          child: ListView(
            children: [
              for (final group in widget.groups)
                if (group.name.toLowerCase().contains(
                  _groupSearch.text.trim().toLowerCase(),
                ))
                  groupEntry(group.id),
            ],
          ),
        ),
      ],
    ),
  );

  Widget status(WorkspaceDevice device) {
    final label = device.online == null
        ? t('未检查', 'Not checked')
        : device.online!
        ? t('可达', 'Reachable')
        : t('暂不可达', 'Unreachable');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          device.online == null
              ? Icons.help_outline
              : device.online!
              ? Icons.check_circle_outline
              : Icons.error_outline,
          size: 19,
          color: device.online == true
              ? const Color(0xFF447956)
              : Theme.of(context).hintColor,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: device.online == true
                  ? const Color(0xFF447956)
                  : Theme.of(context).hintColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget columns({
    required Widget check,
    required Widget name,
    required Widget address,
    required Widget group,
    required Widget status,
    required Widget actions,
    required bool compact,
  }) => Row(
    children: [
      SizedBox(width: 42, child: check),
      Expanded(flex: 3, child: name),
      const SizedBox(width: 16),
      if (!compact) ...[
        Expanded(flex: 2, child: address),
        const SizedBox(width: 16),
      ],
      if (!compact && MediaQuery.sizeOf(context).width >= 1150) ...[
        Expanded(flex: 2, child: group),
        const SizedBox(width: 16),
      ],
      SizedBox(width: compact ? 104 : 128, child: status),
      const SizedBox(width: 12),
      SizedBox(width: compact ? 40 : 128, child: actions),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final showSidebar =
          box.maxWidth >= 850 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      final data = filtered;
      final pages = math.max(1, (data.length / pageSize).ceil());
      final page = math.min(_page, pages - 1);
      final rows = data.skip(page * pageSize).take(pageSize).toList();
      final selectable = rows.where((d) => isDeviceFingerprint(d.id)).toList();
      final allSelected =
          selectable.isNotEmpty &&
          selectable.every((d) => _selected.contains(d.id));
      final someSelected = rows.any((d) => _selected.contains(d.id));
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
          ),
        ),
        child: Row(
          children: [
            if (showSidebar) sidebar(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: box.maxWidth < 700 ? 16 : 26,
                  vertical: 16,
                ),
                child: LayoutBuilder(
                  builder: (context, inner) {
                    final compact =
                        inner.maxWidth < 720 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(1) > 1.5;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.max(140, inner.maxHeight - 180),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  key: const ValueKey('saved-device-sources'),
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    for (final entry in [
                                      (0, t('附近设备', 'Nearby')),
                                      (3, t('最近连接', 'Recent')),
                                      (1, t('收藏', 'Favorites')),
                                      (2, t('全部设备', 'All devices')),
                                    ])
                                      ChoiceChip(
                                        label: Text(entry.$2),
                                        showCheckmark: false,
                                        selected: widget.source == entry.$1,
                                        onSelected: (_) {
                                          setState(resetSelection);
                                          widget.onSource(entry.$1);
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              favorites
                                                  ? _group == null
                                                        ? t(
                                                            '收藏设备',
                                                            'Favorite devices',
                                                          )
                                                        : groupName(_group)
                                                  : widget.source == 0
                                                  ? t('附近设备', 'Nearby devices')
                                                  : widget.source == 3
                                                  ? t(
                                                      '最近连接',
                                                      'Recent connections',
                                                    )
                                                  : t('全部设备', 'All devices'),
                                              style: const TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            t(
                                              '${scoped.length} 台',
                                              '${scoped.length} devices',
                                            ),
                                            key: const ValueKey(
                                              'workspace-device-count',
                                            ),
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).hintColor,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: t('刷新设备', 'Refresh devices'),
                                      onPressed: widget.onRefresh,
                                      icon: const Icon(Icons.refresh),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: math.max(
                                        160,
                                        inner.maxWidth >= 680
                                            ? inner.maxWidth - 320
                                            : inner.maxWidth,
                                      ),
                                      child: TextField(
                                        controller: _search,
                                        onChanged: (_) =>
                                            setState(resetSelection),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          prefixIcon: const Icon(Icons.search),
                                          hintText: favorites
                                              ? t(
                                                  '搜索${groupName(_group)}：名称、IP、主机名',
                                                  'Search ${groupName(_group)}: name, IP, hostname',
                                                )
                                              : t(
                                                  '搜索名称、IP 或主机名',
                                                  'Search name, IP or hostname',
                                                ),
                                          suffixIcon: _search.text.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: t(
                                                    '清空搜索',
                                                    'Clear search',
                                                  ),
                                                  icon: const Icon(Icons.close),
                                                  onPressed: () => setState(() {
                                                    _search.clear();
                                                    resetSelection();
                                                  }),
                                                ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 150,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _status,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                        ),
                                        items: [
                                          for (final entry in [
                                            ('all', t('全部状态', 'All statuses')),
                                            ('reachable', t('可达', 'Reachable')),
                                            (
                                              'unreachable',
                                              t('暂不可达', 'Unreachable'),
                                            ),
                                            (
                                              'unchecked',
                                              t('未检查', 'Not checked'),
                                            ),
                                          ])
                                            DropdownMenuItem(
                                              value: entry.$1,
                                              child: Text(
                                                entry.$2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          _status = v ?? 'all';
                                          resetSelection();
                                        }),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: widget.onAdd,
                                      icon: const Icon(Icons.add, size: 19),
                                      label: Text(t('添加设备', 'Add device')),
                                    ),
                                  ],
                                ),
                                if (!showSidebar)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            key: ValueKey(_group),
                                            initialValue: _group ?? '',
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              labelText: t('分组', 'Group'),
                                            ),
                                            items: [
                                              DropdownMenuItem(
                                                value: '',
                                                child: Text(
                                                  '${groupName(null)} (${count(null)})',
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: favoriteUngroupedId,
                                                child: Text(
                                                  '${groupName(favoriteUngroupedId)} (${count(favoriteUngroupedId)})',
                                                ),
                                              ),
                                              for (final g in widget.groups)
                                                DropdownMenuItem(
                                                  value: g.id,
                                                  child: Text(
                                                    '${g.name} (${count(g.id)})',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                            onChanged: (value) => selectGroup(
                                              value == '' ? null : value,
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: t('管理分组', 'Manage groups'),
                                          onSelected: (action) => widget
                                              .onManageGroup(action, _group),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'new',
                                              child: Text(
                                                t('新建分组', 'New group'),
                                              ),
                                            ),
                                            if (_group != null &&
                                                _group !=
                                                    favoriteUngroupedId) ...[
                                              PopupMenuItem(
                                                value: 'rename',
                                                child: Text(
                                                  t('重命名分组', 'Rename group'),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  t('删除分组', 'Delete group'),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                if (_selected.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Wrap(
                                      spacing: 20,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          t(
                                            '已选 ${_selected.length} 台',
                                            '${_selected.length} selected',
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: moveSelected,
                                          iconAlignment: IconAlignment.end,
                                          icon: const Icon(
                                            Icons.expand_more,
                                            size: 18,
                                          ),
                                          label: Text(
                                            t('移动到分组', 'Move to group'),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              setState(_selected.clear),
                                          child: Text(
                                            t('取消选择', 'Clear selection'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      t(
                                        '共 ${data.length} 台设备',
                                        '${data.length} matching devices',
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(context).hintColor,
                                      ),
                                    ),
                                  ),
                                if (!largeText)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: DefaultTextStyle(
                                      style: TextStyle(
                                        color: Theme.of(context).hintColor,
                                        fontSize: 13,
                                      ),
                                      child: columns(
                                        compact: compact,
                                        check: Tooltip(
                                          message: t(
                                            '选择本页 ${rows.length} 台设备',
                                            'Select ${rows.length} devices on this page',
                                          ),
                                          child: Checkbox(
                                            tristate: true,
                                            value: allSelected
                                                ? true
                                                : someSelected
                                                ? null
                                                : false,
                                            onChanged:
                                                !favorites ||
                                                    widget.onAssignGroups ==
                                                        null
                                                ? null
                                                : (_) => setState(() {
                                                    for (final d
                                                        in selectable) {
                                                      allSelected
                                                          ? _selected.remove(
                                                              d.id,
                                                            )
                                                          : _selected.add(d.id);
                                                    }
                                                  }),
                                          ),
                                        ),
                                        name: Text(t('设备名称', 'Device name')),
                                        address: Text(t('地址', 'Address')),
                                        group: Text(t('所属分组', 'Group')),
                                        status: Text(t('状态', 'Status')),
                                        actions: Text(t('操作', 'Actions')),
                                      ),
                                    ),
                                  ),
                                const Divider(height: 1),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: rows.isEmpty
                              ? Center(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.search, size: 34),
                                        const SizedBox(height: 16),
                                        Text(t('没有找到设备', 'No devices found')),
                                        const SizedBox(height: 12),
                                        if (favorites && _group != null)
                                          TextButton(
                                            onPressed: () => setState(() {
                                              _group = null;
                                              resetSelection();
                                            }),
                                            child: Text(
                                              t(
                                                '在全部收藏中查找',
                                                'Search all favorites',
                                              ),
                                            ),
                                          ),
                                        TextButton(
                                          onPressed: () => setState(() {
                                            _search.clear();
                                            _status = 'all';
                                            resetSelection();
                                          }),
                                          child: Text(
                                            t('清除筛选', 'Clear filters'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Scrollbar(
                                  controller: _scroll,
                                  child: ListView.separated(
                                    key: const ValueKey(
                                      'workspace-device-list',
                                    ),
                                    controller: _scroll,
                                    itemCount: rows.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (c, index) {
                                      final d = rows[index];
                                      final name = Row(
                                        children: [
                                          Icon(
                                            Icons.desktop_windows_outlined,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Tooltip(
                                                  message: d.displayName,
                                                  child: Text(
                                                    d.displayName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                if (compact)
                                                  Text(
                                                    d.displayAddress,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(
                                                        context,
                                                      ).hintColor,
                                                    ),
                                                  ),
                                                if (largeText) status(d),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                      final check = Checkbox(
                                        key: ValueKey('select-device-${d.id}'),
                                        value: _selected.contains(d.id),
                                        semanticLabel:
                                            t('选择 ', 'Select ') + d.displayName,
                                        onChanged:
                                            !favorites ||
                                                widget.onAssignGroups == null ||
                                                !isDeviceFingerprint(d.id)
                                            ? null
                                            : (_) => toggle(d.id),
                                      );
                                      final actions = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!compact)
                                            OutlinedButton(
                                              onPressed: () => widget.onConnect(
                                                d,
                                                LanTool.desktop,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                fixedSize: const Size(76, 32),
                                                textStyle: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                              ),
                                              child: Text(t('连接', 'Connect')),
                                            ),
                                          SizedBox(
                                            width: 40,
                                            height: 40,
                                            child: widget.actions(
                                              d,
                                              key: ValueKey(
                                                'device-actions-${d.id}',
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                      return Material(
                                        color: _selected.contains(d.id)
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                            : Colors.transparent,
                                        child: InkWell(
                                          key: ValueKey('device-row-${d.id}'),
                                          onTap: () =>
                                              _selected.isNotEmpty && favorites
                                              ? toggle(d.id)
                                              : widget.onConnect(
                                                  d,
                                                  LanTool.desktop,
                                                ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: largeText
                                                ? Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 42,
                                                        child: check,
                                                      ),
                                                      Expanded(child: name),
                                                      SizedBox(
                                                        width: 40,
                                                        height: 40,
                                                        child: widget.actions(
                                                          d,
                                                          key: ValueKey(
                                                            'device-actions-${d.id}',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : columns(
                                                    compact: compact,
                                                    check: check,
                                                    name: name,
                                                    address: Tooltip(
                                                      message:
                                                          d.connectionAddress,
                                                      child: Text(
                                                        d.displayAddress,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    group: Text(
                                                      groupName(
                                                        groupFor(d.id) ??
                                                            favoriteUngroupedId,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    status: status(d),
                                                    actions: actions,
                                                  ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data.isEmpty
                                    ? t('共 0 台', '0 devices')
                                    : t(
                                        '显示 ${page * pageSize + 1}–${math.min((page + 1) * pageSize, data.length)} / 共 ${data.length} 台',
                                        '${page * pageSize + 1}–${math.min((page + 1) * pageSize, data.length)} of ${data.length}',
                                      ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t('上一页', 'Previous page'),
                              onPressed: page == 0
                                  ? null
                                  : () => setState(() {
                                      _page = page - 1;
                                      if (_scroll.hasClients) _scroll.jumpTo(0);
                                    }),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('${page + 1}/$pages'),
                            IconButton(
                              tooltip: t('下一页', 'Next page'),
                              onPressed: page + 1 >= pages
                                  ? null
                                  : () => setState(() {
                                      _page = page + 1;
                                      if (_scroll.hasClients) _scroll.jumpTo(0);
                                    }),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
