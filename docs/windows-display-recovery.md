# Windows user-session display recovery

The host and its capture agent stay in the user session that launched SubnetDesk.
The old OS-service session selector is disabled in this runtime. SubnetDesk does
not transfer a disconnected RDP session to the physical console or another user.
When Windows makes the same session's desktop available again, the existing
connection retries enumeration and capture without restarting SubnetDesk.

RDP minimization can suppress desktop rendering, and a disconnected RDP session
may have no capturable outputs. A virtual monitor does not reactivate that session.
Reconnect/activate the Windows session if it remains suspended. This recovery is
not a replacement for Windows logon or a guarantee of capture while RDP is suspended.

For headless desktops, automatic virtual-monitor creation also runs during an
authenticated monitor connection, including portable/user-session launches. It
requires Windows 10 build 19041 or later, the packaged `usbmmidd_v2` driver, and
permission to install/control that driver. Failed attempts are logged as
`plug in headless failed` and retried at most once every ten seconds. After a
successful plug, enumeration waits for the output instead of adding more monitors.
The capture agent can start without displays, waits through empty enumeration,
and recreates a GDI capture context that becomes invalid during a transition.

## Validation

`python3 scripts/test_windows_capture_recovery.py` compiles and executes the actual
capture loop with display/capture test doubles, plus the virtual-monitor retry
policy tests. `flutter test test/session_display_recovery_test.dart` checks that
display loss and return preserve the client connection. These checks do not
exercise Windows display drivers or RDP itself.

Before releasing, verify on Windows 10/11 with the packaged driver:

| Scenario | Expected result |
| --- | --- |
| Fresh portable launch with no physical display or old installation | A virtual output is created on connection; the capture agent stays running. |
| RDP minimized, disconnected, then reconnected to the same user session | The SubnetDesk connection waits while outputs are unavailable and resumes when the desktop becomes capturable. |
| SubnetDesk restarted while that RDP session is disconnected | Host and capture agent start; after activating the Windows session, the connection can receive its first frame. |
| Driver missing or installation denied, then driver made available | Retry is bounded, errors appear in the host log, and creation resumes after the failure is corrected. |
| Successful monitor plug temporarily invisible | Polling does not keep adding virtual monitors. |
| Multiple Windows users/sessions | No obsolete session selector or cross-session service IPC is used. |
