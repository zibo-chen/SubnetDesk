import 'package:flutter/material.dart';

/// Flutter's macOS embedder uses this internal family for San Francisco.
/// Pinning it prevents CoreText from selecting an arbitrary user font that
/// only claims to cover the requested glyph.
const String kSafeMacOSFontFamily = '.AppleSystemUIFont';

/// System-owned macOS families covering CJK, legacy Latin, and emoji text.
const List<String> kSafeMacOSFontFallback = <String>[
  'PingFang SC',
  'Hiragino Sans',
  'Apple SD Gothic Neo',
  'Helvetica Neue',
  'Geeza Pro',
  'Kohinoor Devanagari',
  'Thonburi',
  'Apple Symbols',
  'Apple Color Emoji',
  'LastResort',
];

ThemeData applySafePlatformFontFallback(
  ThemeData theme,
  TargetPlatform platform,
) {
  if (platform != TargetPlatform.macOS) {
    return theme;
  }

  return theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamily: kSafeMacOSFontFamily,
      fontFamilyFallback: kSafeMacOSFontFallback,
    ),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: kSafeMacOSFontFamily,
      fontFamilyFallback: kSafeMacOSFontFallback,
    ),
  );
}

Widget safePlatformDefaultTextStyle({
  required TargetPlatform platform,
  required Widget child,
}) {
  if (platform != TargetPlatform.macOS) {
    return child;
  }

  return DefaultTextStyle.merge(
    style: const TextStyle(
      fontFamily: kSafeMacOSFontFamily,
      fontFamilyFallback: kSafeMacOSFontFallback,
    ),
    child: child,
  );
}
