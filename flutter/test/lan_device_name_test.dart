import 'package:flutter_hbb/desktop/lan_device_name.dart';
import 'package:flutter_hbb/desktop/lan_discovery_refresh.dart';
import 'package:flutter_hbb/desktop/peer_tab_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LAN device name', () {
    test('trims a valid custom name and accepts Unicode', () {
      expect(normalizeLanDeviceName('  会议室 Mac  '), '会议室 Mac');
      expect(validateLanDeviceName('会议室 Mac'), isNull);
    });

    test('allows an empty name to restore the system default', () {
      expect(normalizeLanDeviceName('   '), isEmpty);
      expect(validateLanDeviceName('   '), isNull);
    });

    test('rejects control characters and names over 64 characters', () {
      expect(validateLanDeviceName('Office\nMac'), isNotNull);
      expect(validateLanDeviceName('a' * 65), isNotNull);
    });
  });

  group('LAN discovery refresh', () {
    test('refreshes every peer list while the window is visible', () {
      expect(
        shouldRefreshLanDiscovery(
          windowMinimized: false,
        ),
        isTrue,
      );
      expect(
        shouldRefreshLanDiscovery(
          windowMinimized: true,
        ),
        isFalse,
      );
    });
  });

  group('peer tab label', () {
    test('prefers the local alias', () {
      expect(
        composePeerTabLabel(
          peerId: '192.168.1.10:21118',
          alias: '  客厅平板  ',
          hostname: '08',
        ),
        '客厅平板',
      );
    });

    test('uses the remote device name when no alias exists', () {
      expect(
        composePeerTabLabel(
          peerId: '192.168.1.10:21118',
          alias: '',
          hostname: '08',
        ),
        '08',
      );
    });

    test('falls back to the peer address', () {
      expect(
        composePeerTabLabel(
          peerId: '192.168.1.10:21118',
          alias: ' ',
          hostname: ' ',
        ),
        '192.168.1.10:21118',
      );
    });
  });
}
