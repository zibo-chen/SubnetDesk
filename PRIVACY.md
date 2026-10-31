# SubnetDesk Privacy Policy

Effective date: October 23, 2026

This policy describes how the official SubnetDesk application, maintained by the contributors to [zibo-chen/SubnetDesk](https://github.com/zibo-chen/SubnetDesk), processes information. It covers version 1.3.0 and subsequent official releases; optional features are available only on supported versions and platforms. Modified builds and services operated by others may have different practices.

## Remote sessions and local discovery

SubnetDesk connects devices directly over a LAN, routed network, or VPN. The project does not operate a public rendezvous service, relay service, cloud account system, or central store for your remote sessions.

Depending on the features and permissions used, the connected devices process and exchange:

- Screen images, cursor position, keyboard and mouse input, and audio for remote viewing and control.
- Clipboard contents, transferred files, file names and directory listings, chat messages, and terminal or forwarded network traffic when those features are used.
- IP addresses, hostnames, device names, operating system information, display information, and device public keys and fingerprints to find, identify, and connect devices.
- Access usernames and passwords to authenticate to the controlled device. These credentials are sent through the encrypted session to that device for verification.

Native sessions use an encrypted transport after the initial identity and key exchange. Verify the displayed device fingerprint through a trusted channel before trusting a new device. Optional browser access is hosted by your own SubnetDesk device and uses HTTPS; it does not route the session through a project-operated server.

When local discovery is enabled, mDNS announcements expose the device display name, operating system, protocol version, public fingerprint, network addresses, and listening port to devices on the local network. Discovery announcements do not include passwords. Turn off discovery if you do not want these announcements; direct address connections remain available.

## Information saved on your devices

SubnetDesk saves settings, access usernames, trusted fingerprints, recent devices and connection times, favorites, device identity keys, and other connection preferences in local application configuration. The controlled device stores its configured access password as a salted Argon2id hash. If you choose to remember a remote password on a supported desktop platform, the controller stores that password in the operating system credential store and saves the associated username locally.

Session content is processed as needed to provide the connection. File transfers save files at the selected destination, clipboard synchronization can leave content in the receiving system clipboard or clipboard history, and session recording, when enabled, saves recordings on the recording device. The other participant can also capture or retain information they receive. Disconnecting does not delete these copies.

Local diagnostic logs can contain connection times, addresses, device or user names, file paths, operating system details, and errors. Desktop file logs normally rotate daily and retain up to 31 rotated files per logging process; settings, platform behavior, and inactive installations can affect how long files remain. Releases with diagnostic export can create a local support archive containing recent logs and system information. Export attempts to redact sensitive values, but you should review the archive before sharing it. Exporting does not automatically send it to the maintainers.

## Update requests and external services

On supported Windows and macOS builds, automatic update checks are enabled by default. Checks request release metadata and signatures from GitHub over HTTPS. Downloads also contact GitHub and its release delivery infrastructure and occur when requested or when automatic downloads are enabled. Requests disclose the network source IP address and ordinary HTTP metadata, including a user agent containing the SubnetDesk version. They do not upload remote screen content, clipboard contents, files from your sessions, or access credentials. You can turn off automatic checks and downloads in the software update settings.

Opening project, documentation, release, or community links contacts the selected website. GitHub and other services you choose to use handle those requests under their own privacy policies, including the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). VPN, DNS, operating system, and network providers may also process connection metadata under their own arrangements.

The official application does not automatically upload session content or diagnostic logs to the project maintainers and does not include advertising or analytics services. Maintainers receive information you choose to submit in issues, support conversations, or attachments. Public issue submissions are visible to others; do not post passwords, private keys, or sensitive session content there.

## Your controls and deletion

Use SubnetDesk settings and session controls to restrict incoming access, configure source network allowlists, change or clear access credentials, disable discovery or browser access, and control clipboard, audio, file transfer, and recording where available. Operating system permissions provide additional controls for screen capture, input, microphone, and other protected resources. End the session to stop its live exchange, and disable incoming access or stop SubnetDesk to stop accepting new sessions.

Saved settings and device records remain until you remove or reset them. Remove recent devices, favorites, trusted fingerprints, and remembered credentials using the available application controls; saved passwords can also be removed from your operating system credential manager. To reset all local data, stop SubnetDesk and its background components, then remove its configuration and log directories for every account that ran it, including any service account. This also removes saved device identity keys and causes other devices to see a new identity if keys are regenerated. Uninstalling alone may leave these files and credential entries behind.

Delete downloaded updates, transferred files, recordings, exported diagnostics, clipboard history, and backups separately through the relevant application or operating system. Local copies have no project-enforced expiration. We cannot remotely erase files on your devices or copies held by another participant or service. Information you submit to GitHub or another support service follows that service's retention and deletion controls.

## Contact and policy changes

Contact the project maintainer through the channels listed in the [project README](https://github.com/zibo-chen/SubnetDesk#community), or open a [GitHub issue](https://github.com/zibo-chen/SubnetDesk/issues) for a question that does not contain private information. For private support material, arrange a private channel with the maintainer before sharing it.

Changes to this policy will be published at this location with an updated effective date. The repository history records earlier versions.
