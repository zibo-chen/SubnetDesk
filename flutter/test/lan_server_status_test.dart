import 'package:flutter_hbb/desktop/lan_server_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing credentials require authentication', () {
    expect(
      lanServerDisplayStatus(configured: false, running: false),
      LanServerDisplayStatus.authenticationRequired,
    );
  });

  test('configured enabled service is ready', () {
    expect(
      lanServerDisplayStatus(configured: true, running: true),
      LanServerDisplayStatus.ready,
    );
  });

  test('configured stopped service does not ask for credentials again', () {
    expect(
      lanServerDisplayStatus(configured: true, running: false),
      LanServerDisplayStatus.serviceStopped,
    );
  });

  test('listener startup errors are reported as service failures', () {
    expect(
      lanServerDisplayStatus(
        configured: true,
        running: false,
        startupError: 'Address already in use',
      ),
      LanServerDisplayStatus.serviceFailed,
    );
  });

  test('Windows portable mode offers elevation when LAN is stopped', () {
    expect(
      shouldOfferRemoteActivation(
        configured: true,
        lanServerRunning: false,
        windowsPortable: true,
        portableServiceRunning: false,
      ),
      isTrue,
    );
  });

  test('Windows portable mode can elevate even when user LAN is ready', () {
    expect(
      shouldOfferRemoteActivation(
        configured: true,
        lanServerRunning: true,
        windowsPortable: true,
        portableServiceRunning: false,
      ),
      isTrue,
    );
  });

  test('remote activation is hidden after portable service starts', () {
    expect(
      shouldOfferRemoteActivation(
        configured: true,
        lanServerRunning: true,
        windowsPortable: true,
        portableServiceRunning: true,
      ),
      isFalse,
    );
  });

  test('portable installation remains a separate supported action', () {
    expect(
      shouldOfferPortableInstall(
        windowsPortable: true,
        installationDisabled: false,
      ),
      isTrue,
    );
    expect(
      shouldOfferPortableInstall(
        windowsPortable: true,
        installationDisabled: true,
      ),
      isFalse,
    );
  });
}
