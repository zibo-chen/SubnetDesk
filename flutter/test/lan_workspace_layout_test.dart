import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/common.dart' show mainWindowSizeForWorkArea;
import 'package:flutter_hbb/desktop/host_access_state.dart';

const device = WorkspaceDevice(
  id: '192.168.31.20:21118',
  name: 'A long workstation name for scaled interfaces',
  platform: 'macOS',
  online: true,
);

void main() {
  test('default and restored windows fit the logical DPI-scaled work area', () {
    for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
      final workArea = Size(1920 / dpr, 1040 / dpr);
      final fitted = mainWindowSizeForWorkArea(const Size(960, 640), workArea);
      expect(fitted.width, lessThanOrEqualTo(workArea.width));
      expect(fitted.height, lessThanOrEqualTo(workArea.height));
    }
    expect(
      mainWindowSizeForWorkArea(const Size(1920, 1080), const Size(960, 520)),
      const Size(960, 520),
    );
    expect(
      mainWindowSizeForWorkArea(const Size(300, 200), const Size(1920, 1040)),
      const Size(640, 480),
    );
  });
  testWidgets('workspace copy follows the app language override', (
    tester,
  ) async {
    for (final language in ['en', 'zh-CN', 'cn', 'ZH_cn']) {
      await tester.pumpWidget(
        MaterialApp(
          home: SubnetLanguage(
            languageCode: language,
            child: Builder(
              builder: (context) => Text(subnetText(context, '设备', 'Devices')),
            ),
          ),
        ),
      );
      expect(find.text(language == 'en' ? 'Devices' : '设备'), findsOneWidget);
    }
  });
  testWidgets('settings rows wrap controls at large text sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(720, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SubnetSettingRow(
              title: 'Default remote scaling',
              description:
                  'Changes the remote image without changing local UI size.',
              control: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in ['Follow System', 'Light', 'Dark'])
                    ChoiceChip(label: Text(label), selected: label == 'Light'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Dark'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('discovery order and presence changes do not move device rows', (
    tester,
  ) async {
    Widget workspace(List<WorkspaceDevice> peers) => MaterialApp(
      home: LanWorkspace(
        mobile: true,
        nearby: peers,
        recent: const [device],
        favorites: const [],
        onConnect: (_, __) {},
        onFavorite: (_) {},
        onRefresh: () {},
        onSettings: () {},
      ),
    );
    const alpha = WorkspaceDevice(id: 'a.local', name: 'Alpha', online: false);
    const zeta = WorkspaceDevice(id: 'z.local', name: 'Zeta', online: true);
    await tester.pumpWidget(workspace([zeta, alpha]));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View all'));
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    final alphaPosition = tester.getTopLeft(
      find.byKey(const ValueKey('device-row-a.local')),
    );
    final zetaPosition = tester.getTopLeft(
      find.byKey(const ValueKey('device-row-z.local')),
    );
    expect(alphaPosition.dy, lessThan(zetaPosition.dy));
    await tester.pumpWidget(
      workspace([
        const WorkspaceDevice(id: 'a.local', name: 'Alpha', online: true),
        const WorkspaceDevice(id: 'z.local', name: 'Zeta', online: false),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('device-row-a.local'))),
      alphaPosition,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('device-row-z.local'))),
      zetaPosition,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('full device list scrolls and connects each original endpoint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(966, 677);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final peers = List.generate(
      30,
      (i) => WorkspaceDevice(
        id: '10.1.1.${i + 10}:${i == 29 ? 22000 : 21118}',
        name: 'Workstation ${i.toString().padLeft(2, '0')}',
        online: i == 0 ? null : i != 1,
      ),
    );
    final connected = <String>[];
    Widget workspace(List<WorkspaceDevice> devices) => MaterialApp(
      theme: SubnetPalette.apply(ThemeData()),
      home: LanWorkspace(
        nearby: devices,
        recent: devices.isEmpty ? const [] : [devices.first],
        favorites: devices.isEmpty ? const [] : [devices.first],
        onConnect: (peer, tool) {
          expect(tool, LanTool.desktop);
          connected.add(peer.id);
        },
        onFavorite: (_) {},
        onRefresh: () {},
        onSettings: () {},
      ),
    );
    await tester.pumpWidget(workspace(peers));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('30 devices'), findsOneWidget);
    expect(find.text('Sessions'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.text('Not checked'), findsOneWidget);
    expect(find.text('Unreachable'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('device-row-${peers[8].id}'))).dy,
      lessThan(677),
      reason: 'Compact rows show at least nine devices in the current window',
    );
    for (final peer in [peers.first, peers.last]) {
      final button = find.byKey(
        ValueKey('workspace-device-connect-${peer.id}'),
      );
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('workspace-device-list')),
          matching: find.byType(Scrollable),
        ),
      );
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(of: button, matching: find.text('Connect')),
      );
      expect(label.didExceedMaxLines, isFalse,
          reason: 'The full English action stays visible in the device table');
      expect(label.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 7),
      ).map((box) => box.top).toSet(), hasLength(1));
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(connected, [peers.first.id, peers.last.id]);
    expect(find.text('10.1.1.39:22000'), findsOneWidget);
    await tester.pumpWidget(workspace(const []));
    await tester.pumpAndSettle();
    expect(find.text('0 devices'), findsOneWidget);
    expect(find.text('No devices here'), findsOneWidget);
    expect(find.text('Connect by address').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('device navigation merges sources and resets favorites', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(966, 677));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const nearby = WorkspaceDevice(
      id: 'nearby.local:21118',
      name: 'Current desktop',
      online: true,
    );
    const stale = WorkspaceDevice(
      id: 'nearby.local:21118',
      name: 'Old desktop',
      online: false,
    );
    const history = WorkspaceDevice(id: 'history.local:22000', name: 'History');
    const favorite = WorkspaceDevice(
      id: 'favorite.local:21118',
      name: 'Favorite',
    );
    final connected = <String>[];
    final navigation = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData()),
        home: LanWorkspace(
          nearby: const [nearby],
          recent: const [stale, history],
          favorites: const [stale, favorite],
          onConnect: (peer, _) => connected.add(peer.id),
          onFavorite: (_) {},
          onRefresh: () {},
          onSettings: () {},
          onNavigationChanged: navigation.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('2 devices'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workspace-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('All devices'), findsOneWidget);
    expect(find.text('3 devices'), findsOneWidget);
    expect(find.text('Old desktop'), findsNothing);
    expect(find.text('Current desktop'), findsOneWidget);
    for (final peer in [nearby, history, favorite]) {
      await tester.tap(
        find.byKey(ValueKey('workspace-device-connect-${peer.id}')),
      );
    }
    expect(connected, [nearby.id, history.id, favorite.id]);
    await tester.tap(find.byKey(const ValueKey('workspace-nav-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-home-content')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('workspace-device-list')), findsNothing);
    expect(navigation, [1, 1, 0]);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(640, 452),
    const Size(960, 612),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'desktop home fits one page with many devices at $size text $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final peers = List.generate(
            30,
            (i) => WorkspaceDevice(
              id: '10.1.1.${i + 10}:21118',
              name: 'Workstation $i',
              online: true,
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: SubnetPalette.apply(ThemeData()),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: LanWorkspace(
                nearby: peers,
                recent: [peers.first],
                favorites: const [],
                hostAccess: const HostAccessState(
                  loading: false,
                  discoveryEnabled: true,
                ),
                onConnect: (_, __) {},
                onFavorite: (_) {},
                onRefresh: () {},
                onSettings: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final content = find.byKey(const ValueKey('workspace-home-content'));
          expect(
            find.descendant(of: content, matching: find.byType(Scrollable)),
            findsNothing,
          );
          for (final key in [
            'host-access-remote',
            'workspace-primary-connect',
            'workspace-device-actions',
          ]) {
            expect(
              find.byKey(ValueKey(key)).hitTestable(),
              findsOneWidget,
              reason: key,
            );
          }
          expect(
            find.byTooltip('Refresh devices').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('View all').hitTestable(), findsOneWidget);
          await tester.tap(find.text('View all'));
          await tester.pumpAndSettle();
          expect(find.text('30 devices'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('address validation preserves LAN hostnames, IPv6 and port bounds', () {
    for (final address in [
      '192.168.31.20',
      'studio.local:21118',
      '[fd00::20]:21118',
      'fd00::20',
      '[fe80::1%en0]:21118',
    ]) {
      expect(validLanWorkspaceAddress(address), isTrue, reason: address);
    }
    for (final address in [
      '',
      'http://host',
      '192.168.1.999',
      'host:0',
      'host:65536',
      'host name',
      'host:abc',
      '[::::]:21118',
    ]) {
      expect(validLanWorkspaceAddress(address), isFalse, reason: address);
    }
  });

  test('device addresses hide only the default port for display', () {
    for (final entry in {
      '192.168.31.20:21118': '192.168.31.20',
      'studio.local:21118': 'studio.local',
      '[fd00::20]:21118': '[fd00::20]',
      '[fe80::1%en0]:21118': '[fe80::1%en0]',
      '192.168.31.20:22000': '192.168.31.20:22000',
      '[fd00::20]:22000': '[fd00::20]:22000',
      'fd00::20': 'fd00::20',
    }.entries) {
      final peer = WorkspaceDevice(id: entry.key, name: entry.key);
      expect(peer.displayAddress, entry.value);
      expect(peer.displayName, entry.value);
      expect(peer.id, entry.key);
    }
  });

  testWidgets('desktop home fills its height and keeps address entry in Add', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(966, 677);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const custom = WorkspaceDevice(id: '10.1.1.50:22000', name: 'Custom port');
    WorkspaceDevice? connected;
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData()),
        home: LanWorkspace(
          nearby: const [device, custom],
          recent: const [device],
          favorites: const [],
          onConnect: (peer, _) => connected = peer,
          onFavorite: (_) {},
          onRefresh: () => refreshes++,
          onSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('192.168.31.20'), findsOneWidget);
    expect(find.text('macOS · 192.168.31.20'), findsOneWidget);
    expect(find.text('10.1.1.50:22000'), findsOneWidget);
    expect(find.text('Connect by address'), findsNothing);
    await tester.tap(find.byTooltip('Refresh devices'));
    expect(refreshes, 1);
    for (final peer in [device, custom]) {
      final card = find.byKey(ValueKey('workspace-nearby-device-${peer.id}'));
      expect(tester.getBottomRight(card).dy, closeTo(677 - 24, .01));
    }
    await tester.tap(find.byKey(ValueKey('device-row-${device.id}')));
    expect(connected?.id, device.id);
    await tester.tap(find.byTooltip('Add device'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Connect by address'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'new.local:22000');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(connected?.id, 'new.local:22000');
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'zh-CN']) {
    for (final size in [
      const Size(640, 452),
      const Size(966, 677),
      const Size(1440, 900),
    ]) {
      testWidgets('desktop alignment $language at $size', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: SubnetPalette.apply(ThemeData()),
            home: SubnetLanguage(
              languageCode: language,
              child: LanWorkspace(
                nearby: const [device],
                recent: const [device],
                favorites: const [],
                onConnect: (_, __) {},
                onFavorite: (_) {},
                onRefresh: () {},
                onSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final key in [
          'workspace-desktop-navigation',
          'workspace-hero-image',
          'workspace-primary-connect',
          'workspace-nearby-section',
        ]) {
          final target = find.byKey(ValueKey(key));
          final left = tester.getTopLeft(target);
          final right = tester.getBottomRight(target);
          expect(
            (left.dx + right.dx) / 2,
            closeTo(size.width / 2, .01),
            reason: key,
          );
        }
        final brand = find.byKey(const ValueKey('workspace-header-brand'));
        final actions = find.byKey(const ValueKey('workspace-header-actions'));
        final navY = tester
            .getCenter(find.byKey(const ValueKey('workspace-nav-0')))
            .dy;
        expect(navY, closeTo(tester.getCenter(brand).dy, .01));
        expect(navY, closeTo(tester.getCenter(actions).dy, .01));
        for (final index in [1, 2]) {
          expect(
            tester.getCenter(find.byKey(ValueKey('workspace-nav-$index'))).dy,
            closeTo(navY, .01),
          );
        }
        final content = find.byKey(const ValueKey('workspace-home-content'));
        expect(
          tester.getTopLeft(content).dx,
          closeTo(tester.getTopLeft(brand).dx, .01),
        );
        expect(
          tester.getBottomRight(content).dx,
          closeTo(tester.getBottomRight(actions).dx, .01),
        );
      });
    }
  }

  testWidgets('desktop scales the composition uniformly down to 640x452', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final artwork = find.descendant(
      of: find.byKey(const ValueKey('workspace-hero-image')),
      matching: find.byType(Image),
    );
    Future<Size> render(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: SubnetPalette.apply(ThemeData()),
          home: LanWorkspace(
            nearby: const [device],
            recent: const [device],
            favorites: const [],
            onConnect: (_, __) {},
            onFavorite: (_) {},
            onRefresh: () {},
            onSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Decorative artwork is not an input target; geometry below checks visibility.
      expect(artwork, findsOneWidget);
      expect(
        find.byKey(ValueKey('device-actions-' + device.id)).hitTestable(),
        findsOneWidget,
      );
      final topLeft = tester.getTopLeft(artwork);
      final bottomRight = tester.getBottomRight(artwork);
      expect(topLeft.dx, greaterThanOrEqualTo(0));
      expect(topLeft.dy, greaterThanOrEqualTo(0));
      expect(bottomRight.dx, lessThanOrEqualTo(size.width));
      expect(bottomRight.dy, lessThanOrEqualTo(size.height));
      return Size(bottomRight.dx - topLeft.dx, bottomRight.dy - topLeft.dy);
    }

    final normal = await render(const Size(960, 678));
    final small = await render(const Size(640, 452));
    expect(small.width / normal.width, closeTo(2 / 3, .001));
    expect(small.height / normal.height, closeTo(2 / 3, .001));
  });

  testWidgets('desktop rows connect directly and More targets the same peer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 452);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const other = WorkspaceDevice(id: 'other.local', name: 'Other device');
    final connections = <(String, LanTool)>[];
    String? favorite;
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData()),
        home: LanWorkspace(
          nearby: const [device, other],
          recent: const [device],
          favorites: const [],
          onConnect: (peer, tool) => connections.add((peer.id, tool)),
          onFavorite: (peer) => favorite = peer.id,
          onRefresh: () {},
          onSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('device-row-other.local')));
    await tester.pumpAndSettle();
    expect(connections, [(other.id, LanTool.desktop)]);
    expect(find.text('Back to devices'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    for (final entry in {
      'File transfer': LanTool.files,
      'Terminal': LanTool.terminal,
      'Camera': LanTool.camera,
    }.entries) {
      final previousCount = connections.length;
      await tester.tap(
        find.byKey(const ValueKey('device-actions-other.local')),
      );
      await tester.pumpAndSettle();
      expect(connections.length, previousCount);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(connections.length, previousCount + 1);
      expect(connections.last, (other.id, entry.value));
    }
    await tester.tap(find.byKey(const ValueKey('device-actions-other.local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite device'));
    await tester.pumpAndSettle();
    expect(favorite, other.id);
    expect(connections.length, 4);
    String? copiedAddress;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedAddress = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('device-actions-other.local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy address'));
    await tester.pumpAndSettle();
    expect(copiedAddress, other.id);
    expect(connections.length, 4);
    expect(tester.takeException(), isNull);
  });

  for (final mobile in [false, true]) {
    for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
      for (final fontScale in [1.0, 1.5, 2.0]) {
        testWidgets('layout mobile=$mobile dpr=$dpr text=$fontScale', (
          tester,
        ) async {
          final size = mobile ? const Size(360, 800) : const Size(1024, 768);
          tester.view.devicePixelRatio = dpr;
          tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: SubnetPalette.apply(ThemeData(useMaterial3: false)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(fontScale)),
                child: child!,
              ),
              home: LanWorkspace(
                mobile: mobile,
                nearby: const [device],
                recent: const [device],
                favorites: const [],
                onConnect: (_, __) {},
                onFavorite: (_) {},
                onRefresh: () {},
                onSettings: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('View all'));
          await tester.tap(find.text('View all'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(ChoiceChip), findsNothing);
          expect(find.byTooltip('Search devices'), findsNothing);
          await tester.ensureVisible(find.text(device.name));
          await tester.tap(find.text(device.name));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('landscape and large-text details remain reachable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(1266, 585);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    LanTool? selectedTool;
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData(useMaterial3: false)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: LanWorkspace(
          mobile: true,
          nearby: const [device],
          recent: const [device],
          favorites: const [],
          onConnect: (_, tool) => selectedTool = tool,
          onFavorite: (_) {},
          onRefresh: () {},
          onSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('View all'));
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(device.name));
    await tester.tap(find.text(device.name));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('workspace-nav-0')), findsNothing);
    await tester.tap(find.text('Connect device'));
    expect(selectedTool, LanTool.desktop);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(640, 452), const Size(960, 612)]) {
    for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
      for (final fontScale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'compact $size dpr=$dpr text=$fontScale keeps actions visible',
          (tester) async {
            tester.view.devicePixelRatio = dpr;
            tester.view.physicalSize = Size(
              size.width * dpr,
              size.height * dpr,
            );
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            LanTool? selectedTool;
            await tester.pumpWidget(
              MaterialApp(
                theme: SubnetPalette.apply(ThemeData()),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(fontScale)),
                  child: child!,
                ),
                home: LanWorkspace(
                  nearby: const [device],
                  recent: const [device],
                  favorites: const [],
                  onConnect: (peer, tool) {
                    expect(peer.id, device.id);
                    selectedTool = tool;
                  },
                  onFavorite: (_) {},
                  onRefresh: () {},
                  onSettings: () {},
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final actions = find.byKey(
              const ValueKey('workspace-hero-actions'),
            );
            final actionsLeft = tester.getTopLeft(actions);
            final actionsRight = tester.getBottomRight(actions);
            expect(
              (actionsLeft.dx + actionsRight.dx) / 2,
              closeTo(size.width / 2, .01),
              reason:
                  'Connect and More stay centered below the device identity',
            );
            expect(
              actionsLeft.dy,
              greaterThanOrEqualTo(
                tester
                    .getBottomRight(
                      find.text('${device.platform} · 192.168.31.20'),
                    )
                    .dy,
              ),
            );
            expect(
              actionsRight.dy,
              lessThan(tester.getTopLeft(find.text('Nearby devices')).dy),
              reason: 'The primary action stays above nearby devices',
            );
            for (final key in [
              'workspace-primary-connect',
              'workspace-device-actions',
            ]) {
              expect(
                find.byKey(ValueKey(key)).hitTestable(),
                findsOneWidget,
                reason: key,
              );
            }
            for (final tooltip in ['Add device', 'Settings']) {
              expect(
                find.byTooltip(tooltip).hitTestable(),
                findsOneWidget,
                reason: tooltip,
              );
            }
            await tester.tap(
              find.byKey(const ValueKey('workspace-device-actions')),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Terminal'));
            await tester.tap(find.text('Terminal'));
            await tester.pumpAndSettle();
            expect(selectedTool, LanTool.terminal);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.byTooltip('Refresh devices'));
            await tester.pumpAndSettle();
            expect(
              find.byTooltip('Refresh devices').hitTestable(),
              findsOneWidget,
            );
            await tester.ensureVisible(find.text('View all'));
            await tester.tap(find.text('View all'));
            await tester.pumpAndSettle();
            expect(find.byType(TextField), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text(device.name),
              80,
              scrollable: find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            selectedTool = null;
            await tester.tap(
              find.byKey(ValueKey('workspace-device-connect-${device.id}')),
            );
            await tester.pumpAndSettle();
            expect(selectedTool, LanTool.desktop);
            expect(find.byType(TextField), findsNothing);
            expect(
              find.byKey(ValueKey('device-actions-' + device.id)).hitTestable(),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(ValueKey('device-actions-' + device.id)),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Device information'));
            await tester.tap(find.text('Device information'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.text('Connection address'), findsOneWidget);
            expect(find.text('Close').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Close'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'incoming-only mode retains host access without outgoing controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SubnetPalette.apply(ThemeData(useMaterial3: false)),
          home: LanWorkspace(
            mobile: true,
            incomingOnly: true,
            localPane: const Text('host controls'),
            nearby: const [device],
            recent: const [device],
            favorites: const [],
            onConnect: (_, __) =>
                fail('incoming-only mode offered an outgoing connection'),
            onFavorite: (_) {},
            onRefresh: () {},
            onSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('host controls'), findsOneWidget);
      expect(find.byTooltip('Search devices'), findsNothing);
      expect(find.byTooltip('Add device'), findsNothing);
      expect(find.byKey(const ValueKey('workspace-nav-0')), findsNothing);
      expect(find.byKey(const ValueKey('workspace-nav-1')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('host controls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
