import 'package:flutter_hbb/desktop/setup_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSetupReadinessIssues', () {
    test('returns every missing macOS prerequisite in display order', () {
      final issues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.macos,
          appInstalled: true,
          canScreenRecord: false,
          processTrusted: false,
          canMonitorInput: false,
          daemonInstalled: false,
        ),
      );

      expect(
        issues,
        const [
          SetupReadinessIssue.screenRecording,
          SetupReadinessIssue.accessibility,
          SetupReadinessIssue.inputMonitoring,
          SetupReadinessIssue.daemon,
        ],
      );
    });

    test('outgoing-only mode excludes incoming and daemon requirements', () {
      final issues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.macos,
          outgoingOnly: true,
          appInstalled: true,
          canScreenRecord: false,
          processTrusted: false,
          canMonitorInput: false,
          daemonInstalled: false,
        ),
      );

      expect(issues, const [SetupReadinessIssue.inputMonitoring]);
    });

    test('explicitly stopped service does not request daemon installation', () {
      final issues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.macos,
          serviceStopped: true,
          appInstalled: true,
          daemonInstalled: false,
        ),
      );

      expect(issues, isNot(contains(SetupReadinessIssue.daemon)));
    });

    test('system error precedes platform setup issues', () {
      final issues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.windows,
          systemError: 'service failed',
          appInstalled: false,
        ),
      );

      expect(
        issues,
        const [
          SetupReadinessIssue.systemError,
          SetupReadinessIssue.applicationInstall,
        ],
      );
    });

    test('disabled Windows installation suppresses install reminder', () {
      final issues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.windows,
          installationDisabled: true,
          appInstalled: false,
        ),
      );

      expect(issues, isEmpty);
    });

    test('linux warnings respect outgoing-only mode and Wayland priority', () {
      final incomingIssues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.linux,
          selinuxEnforcing: true,
          currentSessionWayland: true,
          loginSessionWayland: true,
        ),
      );
      final outgoingIssues = resolveSetupReadinessIssues(
        const SetupReadinessSnapshot(
          platform: SetupReadinessPlatform.linux,
          outgoingOnly: true,
          selinuxEnforcing: true,
          currentSessionWayland: true,
        ),
      );

      expect(
        incomingIssues,
        const [
          SetupReadinessIssue.selinux,
          SetupReadinessIssue.wayland,
        ],
      );
      expect(outgoingIssues, isEmpty);
    });
  });
}
