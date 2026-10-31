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
