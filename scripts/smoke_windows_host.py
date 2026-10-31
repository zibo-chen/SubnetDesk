"""Check a packaged host survives window startup and keeps TCP 21118 listening.

Run on an elevated Windows CI runner. The temporary profile binds only loopback,
disables discovery and contains a deliberately invalid password hash, so no login
can succeed. This does not validate screen capture, input or a Win7 desktop.
"""
import argparse
import ctypes
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def has_window(process_id):
    user32 = ctypes.windll.user32
    found = False
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_ssize_t)

    @callback_type
    def inspect(window, _):
        nonlocal found
        owner = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(ctypes.c_void_p(window), ctypes.byref(owner))
        if owner.value == process_id:
            found = True
        return True

    if not user32.EnumWindows(inspect, 0):
        raise ctypes.WinError()
    return found


def smoke(executable):
    if sys.platform != 'win32':
        raise RuntimeError('Run the packaged-host smoke check on Windows')
    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise RuntimeError('The host runtime check requires an elevated CI runner')
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 21118))
    with tempfile.TemporaryDirectory(prefix='subnetdesk-host-smoke-') as temporary:
        data_dir = Path(temporary)
        config = data_dir / 'config'
        config.mkdir()
        (config / 'SubnetDesk.toml').write_text(
            'access_username = "ci-lifecycle-check"\n'
            'access_password_hash = "invalid-ci-only-deny-auth"\n'
            'credential_revision = 1\nlan_schema_version = 1\n', encoding='utf-8')
        (config / 'SubnetDesk2.toml').write_text(
            '[options]\nlan-listen-addresses = "127.0.0.1"\n'
            'lan-listen-port = "21118"\nlan-allowed-networks = "127.0.0.0/8"\n'
            'lan-discovery-enabled = "N"\nweb-access-enabled = "N"\n', encoding='utf-8')
        process = subprocess.Popen(
            [str(executable), '--background', f'--data-dir={data_dir}'],
            cwd=executable.parent)
        started = time.monotonic()
        first_ready = None
        try:
            while time.monotonic() - started < 40:
                if process.poll() is not None:
                    raise RuntimeError(f'Packaged host exited during startup: {process.returncode}')
                ready = False
                if has_window(process.pid):
                    try:
                        with socket.create_connection(('127.0.0.1', 21118), timeout=1):
                            ready = True
                    except OSError:
                        pass
                if ready:
                    first_ready = first_ready or time.monotonic()
                    if time.monotonic() - first_ready >= 5:
                        return {
                            'host_executable': str(executable),
                            'native_window_created': True,
                            'tcp_21118_reachable': True,
                            'sustained_seconds': 5,
                            'elapsed_seconds': round(time.monotonic() - started, 2),
                            'bind_address': '127.0.0.1',
                            'win7_desktop_tested': False,
                            'remote_control_tested': False,
                        }
                else:
                    first_ready = None
                time.sleep(0.5)
            logs = '\n'.join(path.read_text(errors='replace')[-8000:]
                             for path in (data_dir / 'logs').rglob('*.log'))
            raise RuntimeError('Window and TCP 21118 did not stay ready for five seconds.\n' + logs)
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    evidence = smoke(arguments.executable.resolve(strict=True))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print(json.dumps(evidence, indent=2))
