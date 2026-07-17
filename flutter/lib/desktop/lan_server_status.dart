enum LanServerDisplayStatus {
  authenticationRequired,
  ready,
  serviceStopped,
}

LanServerDisplayStatus lanServerDisplayStatus({
  required bool configured,
  required bool running,
}) {
  if (!configured) {
    return LanServerDisplayStatus.authenticationRequired;
  }
  if (running) {
    return LanServerDisplayStatus.ready;
  }
  return LanServerDisplayStatus.serviceStopped;
}
