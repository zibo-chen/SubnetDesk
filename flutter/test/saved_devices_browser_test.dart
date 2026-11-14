import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/models/favorite_group_model.dart';

String fingerprint(int value) => value.toRadixString(16).padLeft(64, '0');
List<WorkspaceDevice> devices() => List.generate(
  96,
  (i) => WorkspaceDevice(
    id: fingerprint(i),
    fingerprint: fingerprint(i),
    name: 'Workstation ${i.toString().padLeft(3, '0')}',
    address: '192.0.2.${i + 1}:21118',
    platform: 'Windows',
    online: i % 3 == 0 ? null : i.isEven,
  ),
);

Future<void> openFavorites(
  WidgetTester tester,
  FavoriteGroupModel model, {
  Future<UndoDeviceAddress> Function(WorkspaceDevice, String, bool)?
  onEditAddress,
  double scale = 1,
  bool allSources = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SubnetPalette.apply(ThemeData()),
      home: MediaQuery(
        data: MediaQueryData(
          size: tester.view.physicalSize / tester.view.devicePixelRatio,
          textScaler: TextScaler.linear(scale),
        ),
        child: AnimatedBuilder(
          animation: model,
          builder: (_, __) => LanWorkspace(
            nearby: allSources ? devices() : const [],
            recent: allSources ? devices() : const [],
            favorites: devices(),
            groups: model.groups,
            groupFor: model.groupIdForPeer,
            onAssignGroups: model.setPeerGroups,
            captureGroupUndo: model.captureUndo,
            onAssignGroup: model.setPeerGroup,
            onCreateGroup: model.createGroup,
            onRenameGroup: model.renameGroup,
            onDeleteGroup: model.deleteGroup,
            onEditAddress: onEditAddress,
            onConnect: (_, __) {},
            onFavorite: (_) {},
            onRefresh: () {},
            onSettings: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Favorites').first);
  await tester.tap(find.text('Favorites').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('source tabs retain the same desktop layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = FavoriteGroupModel(read: () => '', write: (_) {});
    model.createGroup('Office');
    await openFavorites(tester, model, allSources: true);
    final keys = [
      const ValueKey('workspace-desktop-header'),
      const ValueKey('saved-device-groups'),
      const ValueKey('saved-device-sources'),
      const ValueKey('workspace-device-list'),
      ValueKey('device-row-${fingerprint(0)}'),
    ];
    final positions = {
      for (final key in keys) key: tester.getRect(find.byKey(key)),
    };
    final next = tester.getRect(find.byTooltip('Next page'));
    for (final label in ['Nearby', 'Recent', 'All devices', 'Favorites']) {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
      for (final key in keys) {
        expect(
          tester.getRect(find.byKey(key)),
          positions[key],
          reason: '$label: $key',
        );
      }
      expect(tester.getRect(find.byTooltip('Next page')), next);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('96 devices support cross-page moves and undo by fingerprint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = FavoriteGroupModel(read: () => '', write: (_) {});
    model.createGroup('Office');
    model.createGroup('Backup');
    model.setPeerGroups(
      devices().take(24).map((d) => d.id),
      model.groups.first.id,
    );
    await openFavorites(tester, model);
    expect(find.text('Favorite devices'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('select-device-${fingerprint(0)}')));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('select-device-${fingerprint(12)}')));
    await tester.tap(find.text('Move to group'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search destination groups'),
      'Backup',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Backup'));
    await tester.tap(find.text('Move 2 devices'));
    await tester.pumpAndSettle();
    expect(model.groupIdForPeer(fingerprint(0)), model.groups.last.id);
    expect(model.groupIdForPeer(fingerprint(12)), model.groups.last.id);
    expect(
      model.countForGroup(devices().map((d) => d.id), model.groups.last.id),
      2,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(model.groupIdForPeer(fingerprint(0)), model.groups.first.id);
    expect(model.groupIdForPeer(fingerprint(12)), model.groups.first.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing IP passes stable fingerprint and preserves automatic updates',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? id, address;
      bool? automatic;
      var undone = false;
      final model = FavoriteGroupModel(read: () => '', write: (_) {});
      await openFavorites(
        tester,
        model,
        onEditAddress: (device, value, auto) async {
          id = device.id;
          address = value;
          automatic = auto;
          return () async {
            undone = true;
          };
        },
      );
      await tester.tap(
        find.byKey(ValueKey('device-actions-${fingerprint(0)}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit address'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '999.1.1.1');
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      expect(id, isNull);
      expect(find.text('Enter a valid IP address or hostname'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '192.0.2.200');
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      expect(id, fingerprint(0));
      expect(address, '192.0.2.200');
      expect(automatic, isTrue);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (const Size(960, 678), 1.0),
    (const Size(640, 452), 2.0),
    (const Size(1440, 900), 1.5),
  ]) {
    testWidgets(
      'saved devices fit ${scenario.$1} at ${scenario.$2} text scale',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final model = FavoriteGroupModel(read: () => '', write: (_) {});
        model.createGroup('A very long office group name');
        await openFavorites(tester, model, scale: scenario.$2);
        expect(find.byTooltip('Next page').hitTestable(), findsOneWidget);
        expect(
          find.byKey(ValueKey('select-device-${fingerprint(0)}')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
