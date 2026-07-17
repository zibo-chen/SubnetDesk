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
}
