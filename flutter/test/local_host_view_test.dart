import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/desktop/widgets/local_host_view.dart';

Widget hostWorkspace({
  String language = 'en',
  double textScale = 1,
  bool ready = false,
  bool loading = false,
  String endpoint = '10.1.1.143:21118',
  String deviceType = 'laptop',
  void Function(String)? onAction,
}) => MaterialApp(
  theme: SubnetPalette.apply(ThemeData(useMaterial3: false)),
  home: SubnetLanguage(
    languageCode: language,
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: LanWorkspace(
        nearby: const [],
        recent: const [],
        favorites: const [],
        onConnect: (_, __) {},
        onFavorite: (_) {},
        onRefresh: () {},
        onSettings: () {},
        localPane: LocalHostView(
          deviceName: 'macbook-pro-11607 with a long device name',
          platform: 'macOS',
          deviceType: deviceType,
          endpoint: endpoint,
          status: loading
              ? 'Reading access status'
              : ready
              ? 'Ready for access'
              : 'Access is not ready',
          ready: ready,
          loading: loading,
          onRename: loading ? null : () => onAction?.call('rename'),
          onCopyAddress: loading ? null : () => onAction?.call('copy'),
          onOtherAddresses: () => onAction?.call('addresses'),
          onIdentity: () => onAction?.call('identity'),
          onAdvanced: () => onAction?.call('advanced'),
          requirements: [
            for (final entry in {
              'screenRecording': language == 'zh-CN'
                  ? '屏幕录制'
                  : 'Screen recording',
              'accessibility': language == 'zh-CN' ? '辅助功能' : 'Accessibility',
              'password': language == 'zh-CN' ? '访问密码' : 'Access password',
            }.entries)
              LocalAccessRequirement(
                id: entry.key,
                icon: Icons.lock_outline,
                label: entry.value,
                description:
                    'Allow ${entry.value.toLowerCase()} for this device.',
                actionLabel: entry.key == 'password'
                    ? ready
                          ? 'Change password'
                          : 'Set password'
                    : ready
                    ? ''
                    : 'Configure',
                status: loading
                    ? 'Checking'
                    : ready
                    ? 'Configured'
                    : 'Needs setup',
                complete: ready,
                onPressed: loading ? null : () => onAction?.call(entry.key),
              ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> openHost(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('workspace-nav-2')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('local hardware metadata selects art independently of the name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(966, 677));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openHost(tester, hostWorkspace(deviceType: 'desktop'));
    Image localImage() => tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('local-host-art')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (localImage().image as AssetImage).assetName,
      'assets/subnetdesk-desktop.png',
    );
    await tester.pumpWidget(hostWorkspace(deviceType: 'server'));
    await tester.pumpAndSettle();
    expect(
      (localImage().image as AssetImage).assetName,
      'assets/subnetdesk-server.png',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local actions remain reachable and route to their own handlers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(966, 677));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actions = <String>[];
      await openHost(tester, hostWorkspace(onAction: actions.add));
      expect(find.byKey(const ValueKey('local-host-title')), findsOneWidget);
      expect(
        tester.getTopRight(find.byKey(const ValueKey('local-host-status'))).dx,
        closeTo(966 - 50, .1),
        reason: 'Access status follows the outer right edge of the page',
      );
      expect(tester.takeException(), isNull);
      for (final action in [
        'rename',
        'copy',
        'other-addresses',
        'identity',
        'advanced',
      ]) {
        final button = find.byKey(ValueKey('local-host-$action'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(actions, ['rename', 'copy', 'addresses', 'identity', 'advanced']);
      for (final id in ['screenRecording', 'accessibility', 'password']) {
        final button = find.byKey(
          ValueKey('local-host-requirement-$id-action'),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(actions.skip(5), ['screenRecording', 'accessibility', 'password']);
      expect(find.byKey(const ValueKey('local-host-configure')), findsNothing);
      expect(find.text('Before allowing access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading and configured states update without keeping stale pending copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(966, 677));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openHost(tester, hostWorkspace(loading: true, endpoint: ''));
      expect(find.text('Reading access status'), findsOneWidget);
      expect(find.text('No address available'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(
                const ValueKey('local-host-requirement-screenRecording-action'),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('local-host-copy')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(hostWorkspace(ready: true));
      await tester.pumpAndSettle();
      expect(find.text('Ready for access'), findsOneWidget);
      expect(find.text('Configured'), findsNWidgets(3));
      expect(find.text('Configure'), findsNothing);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Before allowing access'), findsNothing);
      expect(find.text('Access settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(640, 452),
    const Size(960, 612),
    const Size(1075, 647),
    const Size(1440, 900),
  ]) {
    for (final language in ['en', 'zh-CN']) {
      testWidgets(
        'all access requirements fit without scrolling at $size, $language',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await openHost(tester, hostWorkspace(language: language));
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('local-host-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(scrollable.position.maxScrollExtent, 0);
          final viewport = tester.getRect(
            find.byKey(const ValueKey('local-host-scroll')),
          );
          final footer = tester.getRect(
            find.byKey(const ValueKey('local-host-advanced')),
          );
          final art = tester.getRect(
            find.byKey(const ValueKey('local-host-art')),
          );
          final addressActions = tester.getRect(
            find.byKey(const ValueKey('local-host-other-addresses')),
          );
          final requirements = tester.getRect(
            find.text(
              language == 'zh-CN' ? '接入前需要完成' : 'Before allowing access',
            ),
          );
          final topGap = art.top - viewport.top;
          final middleGap = requirements.top - addressActions.bottom;
          final bottomGap = viewport.bottom - footer.bottom;
          expect((topGap - bottomGap).abs(), lessThanOrEqualTo(1));
          expect(
            middleGap,
            lessThanOrEqualTo(40),
            reason: 'The identity and access sections stay grouped',
          );
          for (final key in [
            'local-host-art',
            'local-host-name',
            'local-host-address',
          ]) {
            expect(
              tester.getCenter(find.byKey(ValueKey(key))).dx,
              closeTo(viewport.center.dx, .1),
              reason: '$key follows the same center line',
            );
          }
          expect(
            tester
                .getBottomLeft(find.byKey(const ValueKey('local-host-title')))
                .dy,
            lessThanOrEqualTo(viewport.top),
            reason: 'The page heading is separate from the centered content',
          );
          for (final id in ['screenRecording', 'accessibility', 'password']) {
            expect(
              find
                  .byKey(ValueKey('local-host-requirement-$id-action'))
                  .hitTestable(),
              findsOneWidget,
            );
          }
          expect(
            find.textContaining('Allow ', findRichText: true),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [
    const Size(640, 452),
    const Size(966, 677),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final language in ['en', 'zh-CN']) {
        testWidgets(
          'host layout at $size, text $scale, $language preserves long IPv6 and controls',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            const ipv6 = '[fd12:3456:789a:bcde:1234:5678:90ab:cdef]:31118';
            await openHost(
              tester,
              hostWorkspace(
                language: language,
                textScale: scale,
                endpoint: ipv6,
              ),
            );
            expect(find.text(ipv6), findsOneWidget);
            for (final key in [
              'local-host-copy',
              'local-host-requirement-screenRecording-action',
              'local-host-requirement-accessibility-action',
              'local-host-requirement-password-action',
              'local-host-advanced',
            ]) {
              final button = find.byKey(ValueKey(key));
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              expect(button.hitTestable(), findsOneWidget, reason: key);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
