/// Incoming access and local discovery are independent of outgoing connections.
class HostAccessState {
  const HostAccessState({
    this.loading = true,
    this.discoveryEnabled = false,
    this.configured = false,
    this.permissionsReady = false,
    this.serviceStopped = true,
    this.running = false,
    this.busy = false,
    this.error = '',
  });

  factory HostAccessState.fromInfo(
    Map<String, dynamic> info, {
    bool busy = false,
  }) => HostAccessState(
    loading: false,
    discoveryEnabled: info['discovery_enabled'] == true,
    configured: info['configured'] == true,
    permissionsReady: info['host_permissions_ready'] == true,
    serviceStopped: info['service_stopped'] != false,
    running: info['running'] == true,
    busy: busy,
    error: info['runtime_error']?.toString() ?? '',
  );

  final bool loading, discoveryEnabled, configured, permissionsReady;
  final bool serviceStopped, running, busy;
  final String error;

  bool get canEnableRemote => !loading && configured && permissionsReady;
  bool get remoteEnabled => canEnableRemote && !serviceStopped && running;
}
