import 'package:flutter_hbb/desktop/lan_device_name.dart';
import 'package:flutter_hbb/desktop/lan_discovery_refresh.dart';
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
    test('refreshes only while the visible tab is LAN', () {
      expect(
        shouldRefreshLanDiscovery(
          lanTabSelected: true,
          windowMinimized: false,
        ),
        isTrue,
      );
      expect(
        shouldRefreshLanDiscovery(
          lanTabSelected: false,
          windowMinimized: false,
        ),
        isFalse,
      );
      expect(
        shouldRefreshLanDiscovery(
          lanTabSelected: true,
          windowMinimized: true,
        ),
        isFalse,
      );
    });
  });
}
