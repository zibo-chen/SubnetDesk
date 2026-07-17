import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/platform_font_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS theme uses only known-safe system font families', () {
    final theme = applySafePlatformFontFallback(
      ThemeData.light(),
      TargetPlatform.macOS,
    );

    expect(theme.textTheme.bodyMedium?.fontFamily, kSafeMacOSFontFamily);
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      kSafeMacOSFontFallback,
    );
    expect(theme.primaryTextTheme.bodyMedium?.fontFamily, kSafeMacOSFontFamily);
  });

  test('non-macOS themes are not modified', () {
    final original = ThemeData.light();

    final theme = applySafePlatformFontFallback(
      original,
      TargetPlatform.windows,
    );

    expect(identical(theme, original), isTrue);
  });

  testWidgets('macOS default text style receives the safe fallback chain', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (_) => safePlatformDefaultTextStyle(
            platform: TargetPlatform.macOS,
            child: const Text('SubnetDesk'),
          ),
        ),
      ),
    );

    final textContext = tester.element(find.text('SubnetDesk'));
    final style = DefaultTextStyle.of(textContext).style;
    expect(style.fontFamily, kSafeMacOSFontFamily);
    expect(style.fontFamilyFallback, kSafeMacOSFontFallback);
  });
}
