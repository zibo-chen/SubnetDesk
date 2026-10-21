import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/device_art.dart';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/models/peer_model.dart';

void main() {
  test('hardware metadata overrides OS and hostname guesses', () {
    for (final entry in {
      'phone': DeviceKind.phone,
      'tablet': DeviceKind.tablet,
      'laptop': DeviceKind.laptop,
      'desktop': DeviceKind.desktop,
      'all-in-one': DeviceKind.allInOne,
      'server': DeviceKind.server,
    }.entries) {
      expect(
        resolveDeviceKind(
          deviceType: entry.key,
          platform: 'Linux',
          hostname: 'macbook-server',
        ),
        entry.value,
      );
    }
    expect(resolveDeviceKind(platform: 'Linux'), DeviceKind.desktop);
    expect(resolveDeviceKind(platform: 'macOS'), DeviceKind.desktop);
    expect(resolveDeviceKind(platform: 'Windows Server'), DeviceKind.server);
    expect(resolveDeviceKind(platform: 'Android'), DeviceKind.phone);
    expect(
      resolveDeviceKind(platform: 'iOS', hostname: 'iPad14,1'),
      DeviceKind.tablet,
    );
    expect(resolveDeviceKind(hostname: 'macbook-pro'), DeviceKind.laptop);
    expect(resolveDeviceKind(hostname: 'imac-studio'), DeviceKind.allInOne);
    expect(resolveDeviceKind(hostname: 'linux-server-01'), DeviceKind.server);
    expect(resolveDeviceKind(deviceType: '../../missing'), DeviceKind.desktop);
  });

  test(
    'peer copy, persistence and workspace preserve hardware without using alias',
    () {
      final peer = Peer.fromJson({
        'id': '192.168.1.2:21118',
        'hostname': 'Office PC',
        'alias': 'My iPad',
        'platform': 'Linux',
        'device_type': 'server',
      });
      expect(WorkspaceDevice.fromPeer(Peer.copy(peer)).kind, DeviceKind.server);
      expect(Peer.fromJson(peer.toJson()).deviceType, 'server');
      peer.deviceType = '';
      expect(WorkspaceDevice.fromPeer(peer).kind, DeviceKind.desktop);
      expect(Peer.fromJson({'device_type': 123}).deviceType, '');
    },
  );

  for (final mobile in [false, true]) {
    testWidgets('remote hero updates with selected hardware, mobile=$mobile', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        mobile ? const Size(430, 900) : const Size(1100, 800),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget workspace(String type) => MaterialApp(
        home: LanWorkspace(
          mobile: mobile,
          nearby: const [],
          recent: [
            WorkspaceDevice(
              id: 'host:21118',
              name: 'Office',
              platform: 'Linux',
              deviceType: type,
            ),
          ],
          favorites: const [],
          onConnect: (_, __) {},
          onFavorite: (_) {},
          onRefresh: () {},
          onSettings: () {},
        ),
      );
      for (final kind in DeviceKind.values) {
        final type = kind == DeviceKind.allInOne ? 'all-in-one' : kind.name;
        await tester.pumpWidget(workspace(type));
        await tester.pumpAndSettle();
        final hero = find.descendant(
          of: find.byKey(const ValueKey('workspace-hero-image')),
          matching: find.byType(Image),
        );
        expect(
          (tester.widget<Image>(hero).image as AssetImage).assetName,
          kind.asset,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}
