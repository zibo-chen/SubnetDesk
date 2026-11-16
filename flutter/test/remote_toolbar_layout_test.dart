import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final horizontal in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets('toolbar scrolls to the last action: horizontal=$horizontal '
          'dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var disconnected = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: SubnetPalette.apply(
              dark ? ThemeData.dark() : ThemeData.light(),
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (context) {
                    Widget action(int index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RemoteToolbarStyle.buttonHMargin,
                        vertical: RemoteToolbarStyle.buttonVMargin,
                      ),
                      child: SizedBox.square(
                        dimension: RemoteToolbarStyle.buttonSize,
                        child: MenuItemButton(
                          key: ValueKey('action-$index'),
                          style: RemoteToolbarStyle.buttonStyle(
                            context,
                            danger: index == 9,
                          ),
                          onPressed: () => disconnected = index == 9,
                          child: const Center(child: Icon(Icons.close)),
                        ),
                      ),
                    );
                    return RemoteToolbarSurface(
                      isHorizontal: horizontal,
                      children: [
                        RemoteToolbarGrip(isHorizontal: horizontal),
                        RemoteToolbarSeparator(isHorizontal: horizontal),
                        for (var i = 0; i < 10; i++) action(i),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.getSize(find.byType(RemoteToolbarSurface));
        expect(surface.height, horizontal ? 56 : lessThanOrEqualTo(240));
        expect(surface.width, horizontal ? lessThanOrEqualTo(320) : 48);
        expect(surface.width, lessThanOrEqualTo(320));
        expect(surface.height, lessThanOrEqualTo(240));
        expect(tester.takeException(), isNull);
        final lastAction = find.byKey(const ValueKey('action-9'));
        await tester.ensureVisible(lastAction);
        await tester.pumpAndSettle();
        await tester.tap(lastAction);
        await tester.pumpAndSettle();
        expect(disconnected, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final horizontal in [true, false]) {
    testWidgets(
      'toolbar stays inside a smaller remote viewport while resizing: '
      'horizontal=$horizontal',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewportSize = ValueNotifier(const Size(475, 310));
        addTearDown(viewportSize.dispose);
        var activated = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ValueListenableBuilder<Size>(
                  valueListenable: viewportSize,
                  builder: (context, size, _) => SizedBox(
                    key: const ValueKey('remote-viewport'),
                    width: size.width,
                    height: size.height,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: RemoteToolbarSurface(
                        isHorizontal: horizontal,
                        children: [
                          for (var i = 0; i < 12; i++)
                            SizedBox.square(
                              dimension: 40,
                              child: IconButton(
                                key: ValueKey('resize-action-$i'),
                                onPressed: () => activated++,
                                icon: const Icon(Icons.settings),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final size in [
          const Size(475, 310),
          const Size(320, 240),
          const Size(224, 144),
        ]) {
          viewportSize.value = size;
          await tester.pumpAndSettle();
          final viewport = tester.getRect(
            find.byKey(const ValueKey('remote-viewport')),
          );
          final material = tester.getRect(
            find
                .descendant(
                  of: find.byType(RemoteToolbarSurface),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(material.left, greaterThanOrEqualTo(viewport.left));
          expect(material.right, lessThanOrEqualTo(viewport.right));
          expect(material.top, greaterThanOrEqualTo(viewport.top));
          expect(material.bottom, lessThanOrEqualTo(viewport.bottom));
          if (horizontal) {
            expect(material.left, greaterThanOrEqualTo(viewport.left + 8));
            expect(material.right, lessThanOrEqualTo(viewport.right - 8));
          } else {
            expect(material.top, greaterThanOrEqualTo(viewport.top + 8));
            expect(material.bottom, lessThanOrEqualTo(viewport.bottom - 8));
          }
          final action = find.byKey(const ValueKey('resize-action-11'));
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
          expect(tester.takeException(), isNull);
        }
        expect(activated, 3);
      },
    );
  }

  testWidgets('menus open outside the clipped toolbar and remain usable', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: SubnetPalette.apply(ThemeData.light()),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Builder(
              builder: (context) {
                return RemoteToolbarSurface(
                  isHorizontal: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: MenuBar(
                        children: [
                          SubmenuButton(
                            style: RemoteToolbarStyle.buttonStyle(context),
                            menuChildren: [
                              MenuItemButton(
                                onPressed: () => selected = true,
                                child: const Text('Fit to window'),
                              ),
                            ],
                            child: const Icon(Icons.desktop_windows_outlined),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Fit to window').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Fit to window'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(find.text('Fit to window'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
