/// Canonical language codes shared by the native translations and Flutter UI.
String normalizeAppLanguage(String value) {
  final code = value.trim().toLowerCase().replaceAll('_', '-');
  if (code.isEmpty || code == 'default' || code == 'system') return '';
  if (code == 'cn') return 'zh-cn';
  if (code == 'tw') return 'zh-tw';
  final parts = code.split('-');
  if (parts.first == 'zh') {
    if (parts.contains('hant')) return 'zh-tw';
    if (parts.contains('hans')) return 'zh-cn';
    return parts.any((part) => ['tw', 'hk', 'mo'].contains(part))
        ? 'zh-tw'
        : 'zh-cn';
  }
  return switch (parts.first) {
    'br' => 'pt',
    'vn' => 'vi',
    'kk' => 'kz',
    'ka' => 'ge',
    final language => language,
  };
}

String resolveAppLanguage(String selected, String system) {
  final language = normalizeAppLanguage(selected);
  return language.isEmpty ? normalizeAppLanguage(system) : language;
}

/// New copy keeps its Chinese source; other languages use the existing catalog.
String appText(
  String language,
  String chinese,
  String english, {
  String? traditional,
  String Function(String)? translate,
}) {
  if (language == 'zh-cn') return chinese;
  if (language == 'zh-tw' && traditional != null) return traditional;
  final translated = translate?.call(english) ?? english;
  if (language == 'zh-tw' && translated == english) return chinese;
  return translated;
}
