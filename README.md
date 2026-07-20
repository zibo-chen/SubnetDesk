<p align="center">
  <img src="res/subnetdesk-icon.svg" alt="SubnetDesk" width="112">
</p>

# SubnetDesk

<p align="center">
  A simple, LAN-first remote desktop application based on <a href="https://github.com/rustdesk/rustdesk">RustDesk</a>.
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

SubnetDesk is an independently maintained fork of RustDesk for direct remote access inside a LAN or VPN. It removes the public device-ID, rendezvous, relay, cloud account, proxy, and automatic public-update paths, replacing them with direct endpoint connections and local device discovery.

![Discovered devices](assets/screenshots/device-discovery.png)

## Highlights

- Discover nearby devices automatically over mDNS.
- Connect directly by IP address or hostname, with a configurable TCP port.
- Protect access with a username and password; passwords are stored as Argon2id hashes.
- Verify device fingerprints before trusting a new endpoint.
- Restrict incoming connections to selected CIDR networks.
- Keep recent devices and favorites for quick reconnection.
- Use the familiar RustDesk remote-control experience without a public coordination server.

> SubnetDesk does not provide Internet rendezvous or relay services. Devices must be reachable through the same LAN, a routed private network, or a VPN such as WireGuard, Tailscale, or OpenVPN.

## Quick start

1. Install and open SubnetDesk on both devices.
2. On the controlled device, open **LAN settings**, set a username and password, and enable LAN discovery. The default port is `21118`.
3. On the controller, select a discovered device or enter its address manually, then verify the fingerprint and connect.

![LAN settings](assets/screenshots/lan-settings.png)

## Download and build

Prebuilt desktop packages for Windows, macOS, and Linux are published on the [Releases](https://github.com/zibo-chen/SubnetDesk/releases) page. Continuous builds are also available from [GitHub Actions](https://github.com/zibo-chen/SubnetDesk/actions).

To build from source, clone the submodules and use the platform-specific commands in the release workflow:

```bash
git clone --recurse-submodules https://github.com/zibo-chen/SubnetDesk.git
cd SubnetDesk
./build.py --flutter --hwcodec
```

The build requires Rust, Flutter, and native platform dependencies. The GitHub Actions workflow is the source of truth for pinned tool versions and packaging steps.

## Credits and license

SubnetDesk is based on [RustDesk](https://github.com/rustdesk/rustdesk) and retains its open-source foundations. SubnetDesk is an independent project and is not an official RustDesk release.

Licensed under the [GNU Affero General Public License v3.0](LICENCE). Use remote-control software only on systems you own or are authorized to administer.
