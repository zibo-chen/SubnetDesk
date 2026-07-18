const int maxLanDeviceNameLength = 64;

String normalizeLanDeviceName(String value) => value.trim();

String? validateLanDeviceName(String value) {
  final normalized = normalizeLanDeviceName(value);
  if (normalized.runes.length > maxLanDeviceNameLength) {
    return 'Invalid format';
  }
  if (normalized.runes.any((value) => value < 0x20 || value == 0x7F)) {
    return 'Invalid format';
  }
  return null;
}
