String composePeerTabLabel({
  required String peerId,
  required String alias,
  required String hostname,
}) {
  final normalizedAlias = alias.trim();
  if (normalizedAlias.isNotEmpty) {
    return normalizedAlias;
  }

  final normalizedHostname = hostname.trim();
  if (normalizedHostname.isNotEmpty) {
    return normalizedHostname;
  }

  return peerId;
}
