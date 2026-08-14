enum LanServerDisplayStatus {
  authenticationRequired,
  ready,
  serviceFailed,
  serviceStopped,
}

LanServerDisplayStatus lanServerDisplayStatus({
  required bool configured,
  required bool running,
  String startupError = '',
}) {
  if (!configured) {
    return LanServerDisplayStatus.authenticationRequired;
  }
  if (running) {
    return LanServerDisplayStatus.ready;
  }
  if (startupError.isNotEmpty) {
    return LanServerDisplayStatus.serviceFailed;
  }
  return LanServerDisplayStatus.serviceStopped;
}

bool shouldOfferRemoteActivation({
  required bool configured,
  required bool lanServerRunning,
  required bool windowsPortable,
  required bool portableServiceRunning,
}) {
  return configured &&
      (!lanServerRunning || (windowsPortable && !portableServiceRunning));
}

bool shouldOfferPortableInstall({
  required bool windowsPortable,
  required bool installationDisabled,
}) {
  return windowsPortable && !installationDisabled;
}
