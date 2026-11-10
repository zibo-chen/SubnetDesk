import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/pages/saved_lan_credentials_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final fingerprint = List.filled(64, 'a').join();

  tearDown(
    () =>
        messenger.setMockMethodCallHandler(AndroidLanCredentials.channel, null),
  );

  testWidgets(
    'saved fingerprints are listed and deleting requires confirmation',
    (tester) async {
      final entries = [fingerprint];
      final deleted = <String>[];
      messenger.setMockMethodCallHandler(AndroidLanCredentials.channel, (
        call,
      ) async {
        if (call.method == 'list') return entries.toList();
        if (call.method == 'delete') {
          final value = (call.arguments as Map)['fingerprint'] as String;
          deleted.add(value);
          entries.remove(value);
          return null;
        }
        throw MissingPluginException();
      });
      await tester.pumpWidget(
        const MaterialApp(home: SavedLanCredentialsPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text(fingerprint), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(fingerprint), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, [fingerprint]);
      expect(find.text('No saved credentials'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed deletion retains the credential and displays an error',
    (tester) async {
      messenger.setMockMethodCallHandler(AndroidLanCredentials.channel, (
        call,
      ) async {
        if (call.method == 'list') return [fingerprint];
        throw PlatformException(code: 'credential_store');
      });
      await tester.pumpWidget(
        const MaterialApp(home: SavedLanCredentialsPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text(fingerprint), findsOneWidget);
      expect(
        find.text('Could not delete saved credentials. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('listing errors can be retried without exposing credentials', (
    tester,
  ) async {
    var fail = true;
    messenger.setMockMethodCallHandler(AndroidLanCredentials.channel, (
      call,
    ) async {
      if (fail) throw PlatformException(code: 'credential_store');
      return <String>[];
    });
    await tester.pumpWidget(const MaterialApp(home: SavedLanCredentialsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Could not load saved credentials.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No saved credentials'), findsOneWidget);
  });
}
