const lanDiscoveryRefreshInterval = Duration(seconds: 8);

bool shouldRefreshLanDiscovery({
  required bool windowMinimized,
}) {
  return !windowMinimized;
}
