enum SetupReadinessPlatform { windows, macos, linux, other }

enum SetupReadinessIssue {
  systemError,
  applicationInstall,
  screenRecording,
  accessibility,
  inputMonitoring,
  daemon,
  selinux,
  wayland,
  loginWayland,
}

class SetupReadinessSnapshot {
  const SetupReadinessSnapshot({
    required this.platform,
    this.systemError = '',
    this.outgoingOnly = false,
    this.serviceStopped = false,
    this.installationDisabled = false,
    this.appInstalled = true,
    this.canScreenRecord = true,
    this.processTrusted = true,
    this.canMonitorInput = true,
    this.daemonInstalled = true,
    this.selinuxEnforcing = false,
    this.currentSessionWayland = false,
    this.loginSessionWayland = false,
  });

  final SetupReadinessPlatform platform;
  final String systemError;
  final bool outgoingOnly;
  final bool serviceStopped;
  final bool installationDisabled;
  final bool appInstalled;
  final bool canScreenRecord;
  final bool processTrusted;
  final bool canMonitorInput;
  final bool daemonInstalled;
  final bool selinuxEnforcing;
  final bool currentSessionWayland;
  final bool loginSessionWayland;
}

List<SetupReadinessIssue> resolveSetupReadinessIssues(
  SetupReadinessSnapshot snapshot,
) {
  final issues = <SetupReadinessIssue>[];

  if (snapshot.systemError.isNotEmpty) {
    issues.add(SetupReadinessIssue.systemError);
  }

  switch (snapshot.platform) {
    case SetupReadinessPlatform.windows:
      if (!snapshot.installationDisabled && !snapshot.appInstalled) {
        issues.add(SetupReadinessIssue.applicationInstall);
      }
      break;
    case SetupReadinessPlatform.macos:
      if (!snapshot.outgoingOnly && !snapshot.canScreenRecord) {
        issues.add(SetupReadinessIssue.screenRecording);
      }
      if (!snapshot.outgoingOnly && !snapshot.processTrusted) {
        issues.add(SetupReadinessIssue.accessibility);
      }
      if (!snapshot.canMonitorInput) {
        issues.add(SetupReadinessIssue.inputMonitoring);
      }
      if (!snapshot.outgoingOnly &&
          !snapshot.serviceStopped &&
          snapshot.appInstalled &&
          !snapshot.daemonInstalled) {
        issues.add(SetupReadinessIssue.daemon);
      }
      break;
    case SetupReadinessPlatform.linux:
      if (snapshot.outgoingOnly) break;
      if (snapshot.selinuxEnforcing) {
        issues.add(SetupReadinessIssue.selinux);
      }
      if (snapshot.currentSessionWayland) {
        issues.add(SetupReadinessIssue.wayland);
      } else if (snapshot.loginSessionWayland) {
        issues.add(SetupReadinessIssue.loginWayland);
      }
      break;
    case SetupReadinessPlatform.other:
      break;
  }

  return issues;
}
