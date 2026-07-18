const lanDiscoveryRefreshInterval = Duration(seconds: 8);

bool shouldRefreshLanDiscovery({
  required bool lanTabSelected,
  required bool windowMinimized,
}) {
  return lanTabSelected && !windowMinimized;
}
