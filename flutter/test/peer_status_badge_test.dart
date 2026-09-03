import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/peer_status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final status in <bool?>[true, false, null]) {
      testWidgets('visible and accessible status $status in $brightness', (
        tester,
      ) async {
        final label = status == null ? '状态未知' : (status ? '在线' : '离线');
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 180,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.5),
                    ),
                    child: PeerStatusBadge(
                      online: status,
                      label: label,
                      tooltip: '最后发现 2026-09-03 12:00:00',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text(label), findsOneWidget);
        expect(
          find.bySemanticsLabel('$label. 最后发现 2026-09-03 12:00:00'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
