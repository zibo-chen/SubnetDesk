import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/desktop/host_access_state.dart';

Widget workspace({
  HostAccessState state = const HostAccessState(
    loading: false,
    discoveryEnabled: true,
  ),
  String language = 'zh-CN',
  double textScale = 1,
  Future<void> Function(bool)? discovery,
  Future<bool> Function(bool)? remote,
}) => MaterialApp(
  theme: SubnetPalette.apply(ThemeData(useMaterial3: false)),
  home: SubnetLanguage(
    languageCode: language,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: LanWorkspace(
          nearby: const [
            WorkspaceDevice(
              id: '10.1.1.122:21118',
              name: 'desktop-m2bil6u',
              platform: 'Windows',
              online: true,
            ),
          ],
          recent: const [],
          favorites: const [],
          onConnect: (_, __) {},
          onFavorite: (_) {},
          onRefresh: () {},
          onSettings: () {},
          hostAccess: state,
          hostPermissionLabel: language == 'zh-CN'
              ? '授予辅助功能与屏幕录制权限'
              : 'Allow accessibility and screen recording',
          onDiscoveryChanged: discovery ?? (_) async {},
          onRemoteChanged: remote ?? (_) async => false,
          localPane: const Center(child: Text('Real local setup destination')),
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'remote requires credentials, current permissions and an active listener',
    () {
      for (final configured in [false, true]) {
        for (final permissions in [false, true]) {
          for (final stopped in [false, true]) {
            for (final running in [false, true]) {
              final state = HostAccessState.fromInfo({
                'configured': configured,
                'host_permissions_ready': permissions,
                'service_stopped': stopped,
                'running': running,
                'discovery_enabled': true,
              });
              expect(
                state.remoteEnabled,
                configured && permissions && !stopped && running,
              );
              expect(state.discoveryEnabled, isTrue);
            }
          }
        }
      }
      expect(HostAccessState.fromInfo({}).remoteEnabled, isFalse);
      expect(const HostAccessState().canEnableRemote, isFalse);
    },
  );

  testWidgets(
    'discovery works independently and prerequisites lead to local setup',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? discovery;
      await tester.pumpWidget(
        workspace(discovery: (value) async => discovery = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('host-access-discovery')));
      expect(discovery, isFalse);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).map((w) => w.value),
        [true, false],
      );
      await tester.tap(find.byKey(const ValueKey('host-access-remote')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('host-access-guide')), findsOneWidget);
      expect(find.text('设置访问密码'), findsOneWidget);
      expect(find.text('授予辅助功能与屏幕录制权限'), findsOneWidget);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).last.value,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('host-access-guide')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('host-access-remote')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('host-access-configure')));
      await tester.pumpAndSettle();
      expect(find.text('Real local setup destination'), findsOneWidget);
      expect(find.byKey(const ValueKey('host-access-guide')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ready access sends enable and disable without a setup guide', (
    tester,
  ) async {
    bool? requested;
    Future<bool> remote(bool value) async {
      requested = value;
      return true;
    }

    await tester.pumpWidget(
      workspace(
        state: const HostAccessState(
          loading: false,
          configured: true,
          permissionsReady: true,
        ),
        remote: remote,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('host-access-remote')));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(find.byKey(const ValueKey('host-access-guide')), findsNothing);
    await tester.pumpWidget(
      workspace(
        state: const HostAccessState(
          loading: false,
          configured: true,
          permissionsReady: true,
          serviceStopped: false,
          running: true,
        ),
        remote: remote,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('host-access-remote')));
    await tester.pumpAndSettle();
    expect(requested, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['zh-CN', 'en']) {
    for (final size in [
      const Size(640, 452),
      const Size(966, 677),
      const Size(1440, 900),
    ]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
          'local controls and guide fit $language $size text $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              workspace(language: language, textScale: scale),
            );
            await tester.pumpAndSettle();
            if (language == 'en') {
              for (final label in [
                'Discoverable',
                'Remote access',
                'Needs setup',
              ]) {
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.text(label),
                );
                final boxes = paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: label.length),
                );
                expect(
                  boxes.map((box) => box.top).toSet(),
                  hasLength(1),
                  reason: '$label stays on one line at $size, text $scale',
                );
                expect(paragraph.didExceedMaxLines, isFalse);
              }
            }
            await tester.ensureVisible(
              find.byKey(const ValueKey('host-access-remote')),
            );
            await tester.tap(find.byKey(const ValueKey('host-access-remote')));
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('host-access-configure')),
            );
            expect(
              find.byKey(const ValueKey('host-access-guide')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(
              find.byKey(const ValueKey('host-access-configure')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Real local setup destination'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
