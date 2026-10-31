import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/app_language.dart';

void main() {
  test('saved and system languages match the native translation catalog', () {
    final cases =
        jsonDecode(File('test/fixtures/app_languages.json').readAsStringSync())
            as List;
    for (final entry in cases) {
      expect(
        resolveAppLanguage(entry['selected'], entry['system']),
        entry['expected'],
        reason: entry.toString(),
      );
    }
  });

  test('Chinese menu text does not depend on an English catalog fallback', () {
    for (final selected in ['cn', 'zh-CN', 'zh_Hans_CN']) {
      expect(
        appText(
          resolveAppLanguage(selected, 'en_US'),
          '设置',
          'Settings',
          translate: (source) => source,
        ),
        '设置',
      );
    }
    expect(appText('zh-tw', '设置', 'Settings', traditional: '設定'), '設定');
    expect(appText('en', '设置', 'Settings'), 'Settings');
    expect(
      appText('de', '设置', 'Settings', translate: (_) => 'Einstellungen'),
      'Einstellungen',
    );
  });
}
