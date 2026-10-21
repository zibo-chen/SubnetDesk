import 'dart:async';
import 'package:flutter_hbb/common/widgets/lan_workspace.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/common/widgets/device_art.dart';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/lan_device_name.dart';
import 'package:flutter_hbb/desktop/lan_server_status.dart';
import 'package:flutter_hbb/desktop/setup_readiness.dart';
import 'package:flutter_hbb/models/favorite_group_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import '../widgets/local_host_view.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);
const _showSelinuxHelpTipOption = 'show-selinux-help-tip';
const _selinuxHelpUrl =
    'https://github.com/zibo-chen/SubnetDesk/blob/master/docs/linux-host-readiness.md#selinux';
const _waylandHelpUrl =
    'https://github.com/zibo-chen/SubnetDesk/blob/master/docs/linux-host-readiness.md#wayland-session';
const _loginWaylandHelpUrl =
    'https://github.com/zibo-chen/SubnetDesk/blob/master/docs/linux-host-readiness.md#wayland-login-screen';
const _lanDeviceNameOption = 'lan-device-name';

class LanServerInfoPanel extends StatefulWidget {
  const LanServerInfoPanel({
    Key? key,
    this.compact = false,
    this.workspace = false,
    this.setupIssues = const [],
    this.setupRequirements = const [],
    this.onAdvanced,
  }) : super(key: key);

  final bool compact;
  final bool workspace;
  final List<SetupReadinessIssue> setupIssues;
  final List<LocalAccessRequirement> setupRequirements;
  final VoidCallback? onAdvanced;

  @override
  State<LanServerInfoPanel> createState() => _LanServerInfoPanelState();
}

class _LanServerInfoPanelState extends State<LanServerInfoPanel> {
  Timer? _timer;
  bool _showAllAddresses = false;
  bool _refreshing = false;
  bool _activatingRemote = false;
  bool _authorizingHost = false;
  Map<String, dynamic> _info = <String, dynamic>{};

  int _addressPriority(String address) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null) return 5;
    if (parsed.isLoopback) return 4;
    final bytes = parsed.rawAddress;
    if (parsed.type == InternetAddressType.IPv4) {
      if (bytes[0] == 169 && bytes[1] == 254) return 3;
      final isPrivate =
          bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
      return isPrivate ? 0 : 2;
    }
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return 3;
    if ((bytes[0] & 0xfe) == 0xfc) return 1;
    return 2;
  }

  String _formatEndpoint(String address, String port) =>
      address.contains(':') ? '[$address]:$port' : '$address:$port';

  Future<void> _refreshInfo() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final info =
          jsonDecode(await bind.mainGetLanServerInfo()) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _info = info);
      }
    } catch (_) {
      // Keep the last successful snapshot while the host state is unavailable.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshInfo();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshInfo());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final configured = info['configured'] == true;
    final running = info['running'] == true;
    final windowsPortable = isWindows && !bind.mainIsInstalled();
    final portableServiceRunning = info['portable_service_running'] == true;
    final offerRemoteActivation = shouldOfferRemoteActivation(
      configured: configured,
      lanServerRunning: running,
      windowsPortable: windowsPortable,
      portableServiceRunning: portableServiceRunning,
    );
    final offerPortableInstall = shouldOfferPortableInstall(
      windowsPortable: windowsPortable,
      installationDisabled: bind.isDisableInstallation(),
    );
    final runtimeError = info['runtime_error']?.toString() ?? '';
    final displayStatus = lanServerDisplayStatus(
      configured: configured,
      running: running,
      startupError: runtimeError,
    );
    final statusLabel = switch (displayStatus) {
      LanServerDisplayStatus.authenticationRequired => translate(
        'Password Required',
      ),
      LanServerDisplayStatus.ready => translate('Ready'),
      LanServerDisplayStatus.serviceFailed => translate(
        'Service is not running',
      ),
      LanServerDisplayStatus.serviceStopped => translate(
        'Service is not running',
      ),
    };
    final addresses =
        (info['addresses'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toSet()
            .toList()
          ..sort((a, b) {
            final priority = _addressPriority(a).compareTo(_addressPriority(b));
            return priority == 0 ? a.compareTo(b) : priority;
          });
    final port = info['port']?.toString() ?? '21118';
    final preferredAddresses = addresses
        .where((address) => _addressPriority(address) < 3)
        .toList();
    final primaryAddress = preferredAddresses.isNotEmpty
        ? preferredAddresses.first
        : addresses.isEmpty
        ? null
        : addresses.first;
    final hiddenAddressCount = primaryAddress == null
        ? 0
        : addresses.length - 1;
    final visibleAddresses = _showAllAddresses
        ? addresses
        : primaryAddress == null
        ? const <String>[]
        : <String>[primaryAddress];
    final endpoints = visibleAddresses
        .map((address) => _formatEndpoint(address, port))
        .join('\n');
    final webAccessEnabled = info['web_access_enabled'] == true;
    final webPort = info['web_listen_port']?.toString() ?? '18123';
    final webRuntime =
        info['web_runtime'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final webRuntimeState =
        webRuntime['state']?.toString() ??
        (webAccessEnabled ? 'starting' : 'disabled');
    final webRuntimeError = webRuntime['last_error']?.toString() ?? '';
    final webCaCertificatePath =
        info['web_ca_certificate_path']?.toString() ?? '';
    final runtimeEndpoints =
        (webRuntime['endpoints'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList();
    final configuredWebEndpoints = visibleAddresses
        .map((address) => 'https://${_formatEndpoint(address, webPort)}')
        .toList();
    final webEndpointValues = runtimeEndpoints.isNotEmpty
        ? runtimeEndpoints
        : configuredWebEndpoints;
    final webEndpoints = webEndpointValues.join('\n');
    final fingerprint = info['fingerprint']?.toString() ?? '';
    final localDeviceKind = resolveDeviceKind(
      deviceType: info['device_type']?.toString() ?? '',
      platform: isAndroid ? 'Android' : isIOS ? 'iOS' : '',
      hostname: info['system_device_name']?.toString() ?? '',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white54 : const Color(0xFF7A8290);
    final statusColor = switch (displayStatus) {
      LanServerDisplayStatus.ready => const Color(0xFF27B980),
      LanServerDisplayStatus.authenticationRequired => Theme.of(
        context,
      ).colorScheme.error,
      LanServerDisplayStatus.serviceFailed => Theme.of(
        context,
      ).colorScheme.error,
      _ => const Color(0xFFF59E0B),
    };
    if (widget.workspace) {
      String t(String zh, String en) => subnetText(context, zh, en);
      final loading = info.isEmpty;
      final permissionsReady = info['host_permissions_ready'] == true;
      final ready = !loading && permissionsReady &&
          !widget.setupIssues.contains(SetupReadinessIssue.systemError) &&
          !widget.setupIssues.contains(SetupReadinessIssue.localNetwork) &&
          displayStatus == LanServerDisplayStatus.ready;
      String requirementStatus(bool complete) => loading
          ? t('检查中', 'Checking')
          : complete ? t('已就绪', 'Ready') : t('待配置', 'Needs setup');
      final platform = isMacOS ? 'macOS' : isWindows ? 'Windows' : isLinux ? 'Linux' : Platform.operatingSystem;
      return LocalHostView(
        deviceName: info['device_name']?.toString() ?? t('正在读取设备信息', 'Reading device information'),
        platform: platform,
        deviceType: info['device_type']?.toString() ?? '',
        systemDeviceName: info['system_device_name']?.toString() ?? '',
        endpoint: primaryAddress == null ? '' : _formatEndpoint(primaryAddress, port),
        status: loading
            ? t('正在读取接入信息', 'Reading access status')
            : ready
            ? t('接入已就绪', 'Ready for access')
            : runtimeError.isNotEmpty
            ? t('接入服务异常', 'Access service error')
            : t('接入尚未就绪', 'Access is not ready'),
        ready: ready,
        loading: loading,
        onRename: loading ? null : () => _showDeviceNameDialog(context,
            systemName: info['system_device_name']?.toString() ?? ''),
        onCopyAddress: primaryAddress == null ? null : () {
          Clipboard.setData(ClipboardData(text: _formatEndpoint(primaryAddress, port)));
          showToast(translate('Copied'));
        },
        onOtherAddresses: hiddenAddressCount > 0
            ? () => _showAddressList(context, addresses, port) : null,
        onIdentity: loading ? null : () => _showWorkspaceIdentity(info, fingerprint),
        onAdvanced: widget.onAdvanced,
        notice: runtimeError,
        requirements: [
          ...widget.setupRequirements,
          LocalAccessRequirement(
            id: 'password',
            icon: Icons.lock_outline_rounded,
            label: t('访问密码', 'Access password'),
            description: t('连接本机时用于验证身份', 'Used to authenticate connections to this device'),
            actionLabel: configured ? t('修改密码', 'Change password') : t('设置密码', 'Set password'),
            status: loading ? t('检查中', 'Checking') : configured
                ? t('已设置', 'Configured') : t('未设置', 'Not set'),
            complete: !loading && configured,
            onPressed: loading ? null : _openLanSettings,
          ),
          if (isWindows || (isLinux && bind.mainCurrentIsWayland()))
            LocalAccessRequirement(
              id: 'host-permissions',
              icon: isWindows ? Icons.admin_panel_settings_outlined : Icons.screen_share_outlined,
              actionLabel: permissionsReady ? '' : t('授权', 'Allow'),
              label: isWindows ? t('管理员权限', 'Administrator access')
                  : t('录屏与输入控制', 'Screen sharing and input control'),
              status: _authorizingHost ? t('等待授权', 'Waiting for permission')
                  : requirementStatus(permissionsReady),
              complete: !loading && permissionsReady,
              onPressed: loading || _authorizingHost ? null : _requestHostPermissions,
            ),
          if (!isMacOS)
            LocalAccessRequirement(
              id: 'service',
              icon: Icons.settings_ethernet_rounded,
              actionLabel: t('设置', 'Settings'),
              label: t('接入服务', 'Access service'),
              status: loading ? t('检查中', 'Checking') : statusLabel,
              complete: ready,
              onPressed: loading ? null : _openLanSettings,
            ),
        ],
        additionalActions: offerRemoteActivation || offerPortableInstall || webAccessEnabled
            ? Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  if (offerRemoteActivation || offerPortableInstall)
                    _buildRemoteActions(
                      windowsPortable: windowsPortable,
                      offerRemoteActivation: offerRemoteActivation,
                      offerPortableInstall: offerPortableInstall,
                    ),
                  if (webAccessEnabled)
                    TextButton.icon(
                      onPressed: () => _showWorkspaceWebAccess(
                        webEndpoints, webRuntimeState, webRuntimeError,
                        runtimeEndpoints, webCaCertificatePath,
                      ),
                      icon: const Icon(Icons.language_rounded, size: 16),
                      label: Text(t('浏览器接入', 'Browser access')),
                    ),
                ],
              )
            : null,
      );
    }
    if (widget.compact) {
      return Card(
        color: isDark ? const Color(0xFF24262D) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE3E8F0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      localDeviceKind.icon,
                      size: 18,
                      color: Color(0xFF1677FF),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      translate('Your Desktop'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 78),
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (configured) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'LAN · ${translate('Settings')}',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      onPressed: _openLanSettings,
                      icon: Icon(Icons.tune_rounded, size: 16, color: muted),
                    ),
                  ],
                ],
              ),
              if (runtimeError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    runtimeError,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
              if (!configured) ...[
                const SizedBox(height: 14),
                _buildCredentialSetupPrompt(
                  username: info['username']?.toString() ?? '',
                  isDark: isDark,
                  muted: muted,
                ),
              ] else ...[
                if (offerRemoteActivation || offerPortableInstall) ...[
                  const SizedBox(height: 9),
                  _buildRemoteActions(
                  windowsPortable: windowsPortable,
                  offerRemoteActivation: offerRemoteActivation,
                  offerPortableInstall: offerPortableInstall,
                ),
              ],
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: isDark ? Colors.white10 : const Color(0xFFF0F2F6),
              ),
              const SizedBox(height: 4),
              _buildCompactInfoRow(
                icon: Icons.badge_outlined,
                label: translate('Name'),
                value: info['device_name']?.toString() ?? '-',
                muted: muted,
                trailing: IconButton(
                  tooltip: translate('Change'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: () => _showDeviceNameDialog(
                    context,
                    systemName: info['system_device_name']?.toString() ?? '',
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                ),
              ),
              _buildCompactInfoRow(
                icon: Icons.person_outline_rounded,
                label: translate('Username'),
                value: info['username']?.toString() ?? '-',
                muted: muted,
              ),
              _buildCompactInfoRow(
                icon: Icons.lan_outlined,
                label: translate('Local Address'),
                value: primaryAddress == null
                    ? '-'
                    : _formatEndpoint(primaryAddress, port),
                muted: muted,
                trailing: hiddenAddressCount > 0
                    ? TextButton(
                        onPressed: () =>
                            _showAddressList(context, addresses, port),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          minimumSize: const Size(0, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '+$hiddenAddressCount',
                          style: const TextStyle(fontSize: 11),
                        ),
                      )
                    : null,
              ),
              if (webAccessEnabled)
                _buildCompactInfoRow(
                  icon: Icons.language_rounded,
                  label: 'Web remote access',
                  value: webEndpointValues.isEmpty
                      ? webRuntimeState.toUpperCase()
                      : '${webRuntimeState.toUpperCase()} · ${webEndpointValues.first}',
                    muted: muted,
                  ),
              ],
            ],
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white12 : const Color(0xFFDDE2EA),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    translate('Your Desktop'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (widget.compact)
                  IconButton(
                    tooltip: 'LAN · ${translate('Settings')}',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.only(left: 6),
                    constraints: const BoxConstraints(),
                    onPressed: () => showLanSettingsDialog(
                      context,
                      onSaved: () {
                        if (mounted) setState(() {});
                      },
                    ),
                    icon: Icon(Icons.tune_rounded, size: 16, color: muted),
                  ),
              ],
            ),
            if (runtimeError.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                runtimeError,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 11,
                ),
              ),
            ],
            if (offerRemoteActivation || offerPortableInstall) ...[
              const SizedBox(height: 10),
              _buildRemoteActions(
                windowsPortable: windowsPortable,
                offerRemoteActivation: offerRemoteActivation,
                offerPortableInstall: offerPortableInstall,
              ),
            ],
            const SizedBox(height: 14),
            if (isAndroid || isIOS) ...[
              Center(
                child: DeviceArt(
                  kind: localDeviceKind,
                  key: const ValueKey('mobile-local-device-art'),
                  width: 220,
                  height: 156,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              translate('Name'),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            Row(
              children: [
                Expanded(
                  child: SelectableText(info['device_name']?.toString() ?? '-'),
                ),
                IconButton(
                  tooltip: translate('Change'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showDeviceNameDialog(
                    context,
                    systemName: info['system_device_name']?.toString() ?? '',
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              translate('Username'),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 3),
            SelectableText(info['username']?.toString() ?? '-'),
            const SizedBox(height: 11),
            Text(
              translate('Local Address'),
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 3),
            SelectableText(endpoints.isEmpty ? '-' : endpoints),
            if (webAccessEnabled) ...[
              const SizedBox(height: 11),
              Text(
                'Web remote access',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 3),
              SelectableText(webEndpoints.isEmpty ? '-' : webEndpoints),
              const SizedBox(height: 5),
              Text(
                webRuntimeError.isNotEmpty
                    ? webRuntimeError
                    : webRuntimeState.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: webRuntimeState == 'listening'
                      ? const Color(0xFF27B980)
                      : webRuntimeState == 'failed' ||
                            webRuntimeState == 'stale'
                      ? Theme.of(context).colorScheme.error
                      : muted,
                ),
              ),
              if (webRuntimeState == 'listening' && runtimeEndpoints.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri.parse(runtimeEndpoints.first),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: Text(translate('Open')),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: runtimeEndpoints.first),
                        );
                        showToast(translate('Copied'));
                      },
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: Text(translate('Copy')),
                    ),
                  ],
                ),
              if (webCaCertificatePath.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.file(webCaCertificatePath),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.verified_user_outlined, size: 16),
                  label: const Text('Install local CA'),
                ),
            ],
            if (hiddenAddressCount > 0)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showAllAddresses = !_showAllAddresses),
                icon: Icon(
                  _showAllAddresses
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                label: Text('$hiddenAddressCount ${translate('More')}'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            if (!widget.compact) ...[
              const SizedBox(height: 8),
              Text(
                translate('Fingerprint'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              SelectableText(fingerprint),
            ],
            if (!widget.compact) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => showLanSettingsDialog(
                      context,
                      onSaved: () {
                        if (mounted) setState(() {});
                      },
                    ),
                    icon: const Icon(Icons.settings_ethernet),
                    label: Text('LAN · ${translate('Settings')}'),
                  ),
                  if (fingerprint.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: translate('Copy fingerprint'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fingerprint));
                        showToast(translate('Copied'));
                      },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteActions({
    required bool windowsPortable,
    required bool offerRemoteActivation,
    required bool offerPortableInstall,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (offerRemoteActivation)
          OutlinedButton.icon(
            onPressed: _activatingRemote ? null : _enableRemote,
            icon: _activatingRemote
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.power_settings_new_rounded, size: 16),
            label: Text(
              windowsPortable
                  ? '${translate('Enable')} ${translate('Remote')}'
                  : translate('Start service'),
            ),
          ),
        if (offerPortableInstall)
          TextButton.icon(
            onPressed: _openInstaller,
            icon: const Icon(Icons.download_for_offline_outlined, size: 16),
            label: Text(translate('Install')),
          ),
      ],
    );
  }

  Future<void> _openLanSettings() async {
    await showLanSettingsDialog(
      context,
      onSaved: () => unawaited(_refreshInfo()),
    );
  }

  Future<void> _showWorkspaceIdentity(Map<String, dynamic> info, String fingerprint) {
    String t(String zh, String en) => subnetText(context, zh, en);
    final username = info['username']?.toString() ?? '';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('设备身份', 'Device identity')),
        content: SizedBox(
          width: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('用户名', 'Username'), style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              SelectableText(username.isEmpty ? t('未设置', 'Not set') : username),
              const SizedBox(height: 20),
              Text(t('设备指纹', 'Device fingerprint'), style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              SelectableText(fingerprint.isEmpty ? t('暂不可用', 'Unavailable') : fingerprint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              if (fingerprint.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fingerprint));
                    showToast(translate('Copied'));
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: Text(t('复制完整指纹', 'Copy full fingerprint')),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(translate('Close')))],
      ),
    );
  }

  Future<void> _showWorkspaceWebAccess(String endpoints, String state, String error,
      List<String> runtimeEndpoints, String caPath) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(subnetText(context, '浏览器接入', 'Browser access')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(endpoints.isEmpty ? '-' : endpoints),
              const SizedBox(height: 12),
              SelectableText(error.isEmpty ? state.toUpperCase() : error),
              if (state == 'listening' && runtimeEndpoints.isNotEmpty)
                Wrap(children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(runtimeEndpoints.first), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: Text(translate('Open')),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: runtimeEndpoints.first));
                      showToast(translate('Copied'));
                    },
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: Text(translate('Copy')),
                  ),
                ]),
              if (caPath.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.file(caPath), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.verified_user_outlined, size: 16),
                  label: const Text('Install local CA'),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(translate('Close')))],
      ),
    );
  }

  Widget _buildCredentialSetupPrompt({
    required String username,
    required bool isDark,
    required Color muted,
  }) {
    final warning = Theme.of(context).colorScheme.error;
    final fieldColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF7F9FC);
    final usernameValue = username.trim().isEmpty
        ? translate('Not available')
        : username;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          translate('Set your own password'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '${translate('Remote')} · ${translate('Authentication Required')}',
          style: TextStyle(fontSize: 12, height: 1.35, color: muted),
        ),
        const SizedBox(height: 12),
        _buildCredentialStatusRow(
          icon: Icons.person_outline_rounded,
          label: translate('Username'),
          value: usernameValue,
          fieldColor: fieldColor,
          muted: muted,
          warning: warning,
        ),
        const SizedBox(height: 8),
        _buildCredentialStatusRow(
          icon: Icons.lock_outline_rounded,
          label: translate('Password'),
          value: translate('Password Required'),
          fieldColor: fieldColor,
          muted: muted,
          warning: warning,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openLanSettings,
            icon: const Icon(Icons.lock_outline_rounded, size: 17),
            label: Text(translate('Set Password')),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color fieldColor,
    required Color muted,
    required Color warning,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: muted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: warning,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enableRemote() async {
    if (_activatingRemote) return;
    setState(() => _activatingRemote = true);
    try {
      await start_service(true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refreshInfo();
    } finally {
      if (mounted) setState(() => _activatingRemote = false);
    }
  }

  Future<void> _requestHostPermissions() async {
    if (_authorizingHost) return;
    setState(() => _authorizingHost = true);
    try {
      final error = await bind.mainRequestHostPermissions();
      if (error.isNotEmpty && mounted) showToast(error);
      await _refreshInfo();
    } catch (error) {
      debugPrint('Requesting host permissions failed: $error');
      if (mounted) {
        showToast(subnetText(context, '授权未完成，请重试',
            'Permission setup did not complete. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _authorizingHost = false);
    }
  }

  Future<void> _openInstaller() async {
    await rustDeskWinManager.closeAllSubWindows();
    bind.mainGotoInstall();
  }

  Widget _buildCompactInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color muted,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: muted),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: muted)),
                const SizedBox(height: 2),
                Tooltip(
                  message: value,
                  child: Text(
                    value,
                    maxLines: _showAllAddresses ? null : 1,
                    overflow: _showAllAddresses ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _showDeviceNameDialog(
    BuildContext context, {
    required String systemName,
  }) async {
    final storedName = bind.mainGetOptionSync(key: _lanDeviceNameOption);
    final controller = TextEditingController(text: storedName);
    var errorText = validateLanDeviceName(storedName);

    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF1677FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                translate('Name'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: maxLanDeviceNameLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(maxLanDeviceNameLength),
              ],
              onChanged: (value) => setDialogState(
                () => errorText = validateLanDeviceName(value),
              ),
              decoration: InputDecoration(
                labelText: translate('Name'),
                hintText: systemName,
                errorText: errorText == null ? null : translate(errorText!),
                helperText: systemName.isEmpty
                    ? translate('Default')
                    : '${translate('Default')}: $systemName',
                prefixIcon: const Icon(Icons.desktop_windows_outlined),
                suffixIcon: TextButton(
                  onPressed: () {
                    controller.clear();
                    setDialogState(() => errorText = null);
                  },
                  child: Text(translate('Default')),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(translate('Cancel')),
            ),
            ElevatedButton(
              onPressed: errorText != null
                  ? null
                  : () async {
                      await bind.mainSetOption(
                        key: _lanDeviceNameOption,
                        value: normalizeLanDeviceName(controller.text),
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      if (mounted) setState(() {});
                    },
              child: Text(translate('OK')),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    // The pop future finishes before the dialog's closing animation.
    await route.completed;
    controller.dispose();
  }

  Future<void> _showAddressList(
    BuildContext context,
    List<String> addresses,
    String port,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate('Local Address')),
        content: SizedBox(
          width: isDesktop || isWebDesktop ? 420 : double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: addresses.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final endpoint = _formatEndpoint(addresses[index], port);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lan_outlined, size: 18),
                title: SelectableText(
                  endpoint,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: IconButton(
                  tooltip: translate('Copy'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: endpoint));
                    showToast(translate('Copied'));
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translate('Close')),
          ),
        ],
      ),
    );
  }
}

Future<void> showLanSettingsDialog(
  BuildContext context, {
  VoidCallback? onSaved,
}) async {
  Map<String, dynamic> info;
  try {
    info =
        jsonDecode(await bind.mainGetLanServerInfo()) as Map<String, dynamic>;
  } catch (_) {
    info = <String, dynamic>{};
  }
  final credentialsConfigured = info['configured'] == true;
  final username = TextEditingController(
    text: info['username']?.toString() ?? '',
  );
  final password = TextEditingController();
  final listenAddresses = TextEditingController(
    text: info['listen_addresses']?.toString() ?? '',
  );
  final listenPort = TextEditingController(
    text: info['port']?.toString() ?? '21118',
  );
  final allowedNetworks = TextEditingController(
    text: info['allowed_networks']?.toString() ?? '',
  );
  final webListenPort = TextEditingController(
    text: info['web_listen_port']?.toString() ?? '18123',
  );
  final webCertificatePath = TextEditingController(
    text: info['web_certificate_path']?.toString() ?? '',
  );
  final webPrivateKeyPath = TextEditingController(
    text: info['web_private_key_path']?.toString() ?? '',
  );
  final webListenAddresses = TextEditingController(
    text: info['web_listen_addresses']?.toString() ?? '',
  );
  final webAllowedNetworks = TextEditingController(
    text: info['web_allowed_networks']?.toString() ?? '',
  );
  final webAllowedHosts = TextEditingController(
    text: info['web_allowed_hosts']?.toString() ?? '',
  );
  var webPermissionProfile =
      info['web_permission_profile']?.toString() ?? 'control';
  if (!const {
    'view-only',
    'control',
    'collaboration',
  }.contains(webPermissionProfile)) {
    webPermissionProfile = 'control';
  }
  var discoveryEnabled = info['discovery_enabled'] == true;
  var webAccessEnabled = info['web_access_enabled'] == true;
  var error = '';
  var saving = false;

  final route = DialogRoute<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final useDesktopLayout = isDesktop || isWebDesktop;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = Theme.of(context).colorScheme.primary;
        final muted = isDark ? Colors.white60 : const Color(0xFF737B8C);
        final fieldFill = isDark
            ? const Color(0xFF292C33)
            : const Color(0xFFF7F9FC);
        final border = isDark ? Colors.white12 : const Color(0xFFE1E6EE);

        InputDecoration fieldDecoration({
          required String label,
          required IconData icon,
          String? help,
        }) {
          return InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: muted, fontSize: 13),
            prefixIcon: Icon(icon, size: 19, color: muted),
            suffixIcon: help == null
                ? null
                : Tooltip(
                    message: help,
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: muted,
                    ),
                  ),
            filled: true,
            fillColor: fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: primary, width: 1.4),
            ),
          );
        }

        Widget responsiveFields(List<Widget> children) {
          if (useDesktopLayout) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index] is Expanded
                    ? (children[index] as Expanded).child
                    : children[index],
                if (index != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        Widget responsiveActions(List<Widget> children) {
          if (useDesktopLayout) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: children,
            );
          }
          return Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: children,
          );
        }

        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: useDesktopLayout ? 40 : 16,
            vertical: 24,
          ),
          backgroundColor: isDark ? const Color(0xFF202228) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: useDesktopLayout ? 590 : double.maxFinite,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                useDesktopLayout ? 24 : 16,
                useDesktopLayout ? 22 : 16,
                useDesktopLayout ? 24 : 16,
                useDesktopLayout ? 20 : 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: primary.withOpacity(isDark ? 0.18 : 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.settings_ethernet_rounded,
                            color: primary,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'LAN · ${translate('Settings')}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${translate('Your Desktop')} · ${translate('Local Address')}',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: translate('Close'),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: Icon(Icons.close_rounded, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    responsiveFields([
                      Expanded(
                        child: TextField(
                          controller: username,
                          autofocus:
                              !credentialsConfigured && username.text.isEmpty,
                          autocorrect: false,
                          decoration: fieldDecoration(
                            label: translate('Username'),
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                      ),
                      if (useDesktopLayout) const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: password,
                          autofocus:
                              !credentialsConfigured &&
                              username.text.isNotEmpty,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: fieldDecoration(
                            label: translate('Password'),
                            icon: Icons.lock_outline_rounded,
                            help: info['configured'] == true
                                ? translate(
                                    'Leave blank to keep current password',
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    responsiveFields([
                      Expanded(
                        child: TextField(
                          controller: listenAddresses,
                          decoration: fieldDecoration(
                            label: translate('Local Address'),
                            icon: Icons.lan_outlined,
                            help: translate(
                              'Comma-separated IP addresses; blank listens on all interfaces',
                            ),
                          ),
                        ),
                      ),
                      if (useDesktopLayout) const SizedBox(width: 12),
                      SizedBox(
                        width: useDesktopLayout ? 140 : double.maxFinite,
                        child: TextField(
                          controller: listenPort,
                          keyboardType: TextInputType.number,
                          decoration: fieldDecoration(
                            label: translate('Port'),
                            icon: Icons.tag_rounded,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                      controller: allowedNetworks,
                      decoration: fieldDecoration(
                        label: translate('Network'),
                        icon: Icons.route_outlined,
                        help: translate(
                          'Comma-separated CIDR ranges; blank uses safe LAN/VPN defaults',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(isDark ? 0.12 : 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primary.withOpacity(isDark ? 0.24 : 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.radar_rounded, size: 20, color: primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              translate('Enable LAN discovery'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Switch(
                            value: discoveryEnabled,
                            onChanged: (value) =>
                                setDialogState(() => discoveryEnabled = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: fieldFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.language_rounded,
                                size: 20,
                                color: primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Web remote access',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Open this computer directly from a browser on the local network',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: webAccessEnabled,
                                onChanged: (value) => setDialogState(
                                  () => webAccessEnabled = value,
                                ),
                              ),
                            ],
                          ),
                          if (webAccessEnabled) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: webListenPort,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setDialogState(() {}),
                              decoration: fieldDecoration(
                                label: 'Web port',
                                icon: Icons.tag_rounded,
                                help:
                                    'HTTPS is always enabled. HTTP requests on this port redirect to HTTPS.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: webListenAddresses,
                              decoration: fieldDecoration(
                                label: 'Web listen addresses',
                                icon: Icons.dns_outlined,
                                help:
                                    'Comma-separated IP addresses. Blank falls back to the native LAN listener. VPN addresses outside the default private ranges also require a matching Web allowed network.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: webAllowedNetworks,
                              decoration: fieldDecoration(
                                label: 'Web allowed networks',
                                icon: Icons.security_rounded,
                                help:
                                    'Comma-separated CIDR ranges. Blank falls back to the native LAN policy. Add the VPN CIDR here when an overlay network uses public-looking addresses.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: webAllowedHosts,
                              decoration: fieldDecoration(
                                label: 'Web allowed host names',
                                icon: Icons.language_outlined,
                                help:
                                    'Comma-separated DNS names or IP addresses. When set, every other Host header is rejected.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: webPermissionProfile,
                              decoration: fieldDecoration(
                                label: 'Browser permission profile',
                                icon: Icons.policy_outlined,
                                help:
                                    'Browser sessions never receive file, restart, privacy-mode, or terminal privileges.',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'view-only',
                                  child: Text('View only'),
                                ),
                                DropdownMenuItem(
                                  value: 'control',
                                  child: Text('Keyboard and pointer control'),
                                ),
                                DropdownMenuItem(
                                  value: 'collaboration',
                                  child: Text('Control and text clipboard'),
                                ),
                              ],
                              onChanged: (value) => setDialogState(
                                () => webPermissionProfile = value ?? 'control',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: webCertificatePath,
                              decoration: fieldDecoration(
                                label: 'Custom certificate chain (PEM)',
                                icon: Icons.verified_user_outlined,
                                help:
                                    'Optional absolute path. Leave both certificate fields empty to use the generated local CA and rotating server certificate.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: webPrivateKeyPath,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: fieldDecoration(
                                label: 'Custom private key (PEM)',
                                icon: Icons.key_rounded,
                                help:
                                    'Optional absolute path. On macOS and Linux the key file must only be accessible by its owner.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'https://<LAN-IP>:${webListenPort.text.isEmpty ? '18123' : webListenPort.text}',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Divider(height: 1, color: border),
                    const SizedBox(height: 16),
                    responsiveActions([
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(translate('Cancel')),
                      ),
                      if (useDesktopLayout) const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                setDialogState(() {
                                  saving = true;
                                  error = '';
                                });
                                if (webCertificatePath.text.trim().isNotEmpty &&
                                    webAllowedHosts.text.trim().isEmpty) {
                                  setDialogState(() {
                                    saving = false;
                                    error =
                                        'Web allowed host names are required with a custom certificate';
                                  });
                                  return;
                                }
                                await bind.mainSetOptions(
                                  json: jsonEncode(<String, String>{
                                    'web-listen-addresses': webListenAddresses
                                        .text
                                        .trim(),
                                    'web-allowed-networks': webAllowedNetworks
                                        .text
                                        .trim(),
                                    'web-allowed-hosts': webAllowedHosts.text
                                        .trim(),
                                    'web-permission-profile':
                                        webPermissionProfile,
                                  }),
                                );
                                var result = await bind.mainApplyLanSettings(
                                  username: username.text,
                                  password: password.text,
                                  listenAddresses: listenAddresses.text,
                                  listenPort: listenPort.text,
                                  allowedNetworks: allowedNetworks.text,
                                  discoveryEnabled: discoveryEnabled,
                                  webAccessEnabled: webAccessEnabled,
                                  webListenPort: webListenPort.text,
                                  webCertificatePath: webCertificatePath.text,
                                  webPrivateKeyPath: webPrivateKeyPath.text,
                                );
                                if (result.isEmpty && webAccessEnabled) {
                                  var runtimeState = '';
                                  for (
                                    var attempt = 0;
                                    attempt < 25;
                                    attempt++
                                  ) {
                                    await Future<void>.delayed(
                                      const Duration(milliseconds: 200),
                                    );
                                    try {
                                      final currentInfo =
                                          jsonDecode(
                                                await bind
                                                    .mainGetLanServerInfo(),
                                              )
                                              as Map<String, dynamic>;
                                      final runtime =
                                          currentInfo['web_runtime']
                                              as Map<String, dynamic>?;
                                      runtimeState =
                                          runtime?['state']?.toString() ?? '';
                                      if (runtimeState == 'listening') break;
                                      if (runtimeState == 'failed' ||
                                          runtimeState == 'stale') {
                                        result =
                                            runtime?['last_error']
                                                ?.toString() ??
                                            'Web gateway failed to start';
                                        break;
                                      }
                                    } catch (_) {
                                      // The host may still be replacing its
                                      // runtime status file atomically.
                                    }
                                  }
                                  if (result.isEmpty &&
                                      runtimeState != 'listening') {
                                    result =
                                        'Web gateway did not reach the listening state within 5 seconds';
                                  }
                                }
                                password.clear();
                                if (!dialogContext.mounted) return;
                                if (result.isEmpty) {
                                  Navigator.of(dialogContext).pop();
                                  onSaved?.call();
                                } else {
                                  setDialogState(() {
                                    saving = false;
                                    error = result;
                                  });
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(translate('Save')),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  // Keep controllers alive until the route and its input decorators unmount.
  await route.completed;
  password.clear();
  username.dispose();
  password.dispose();
  listenAddresses.dispose();
  listenPort.dispose();
  allowedNetworks.dispose();
  webListenPort.dispose();
  webCertificatePath.dispose();
  webPrivateKeyPath.dispose();
  webListenAddresses.dispose();
  webAllowedNetworks.dispose();
  webAllowedHosts.dispose();
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsInstalledDaemon = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  LocalNetworkPermissionStatus _localNetworkPermission =
      LocalNetworkPermissionStatus.unknown;
  bool _checkingLocalNetworkPermission = false;
  PeerTabIndex _selectedPeerTab = PeerTabIndex.lan;
  String? _selectedFavoriteGroupId;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    if (!isIncomingOnly) {
      return _buildBlock(
        child: LanWorkspacePage(
          onSettings: () => DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys.first),
          localPane: bind.isOutgoingOnly() ? null : LanServerInfoPanel(
            workspace: true,
            setupIssues: _setupReadinessIssues,
            setupRequirements: _localSetupRequirements,
            onAdvanced: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LocalHostPreferencesPage(),
            )),
          ),
        ),
      );
    }
    return _buildBlock(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildLeftPane(context),
          if (!isIncomingOnly) const VerticalDivider(width: 1),
          if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
        ],
      ),
    );
  }

  SetupReadinessPlatform get _setupReadinessPlatform {
    if (isWindows) return SetupReadinessPlatform.windows;
    if (isMacOS) return SetupReadinessPlatform.macos;
    if (isLinux) return SetupReadinessPlatform.linux;
    return SetupReadinessPlatform.other;
  }

  List<SetupReadinessIssue> get _setupReadinessIssues {
    final platform = _setupReadinessPlatform;
    final isMac = platform == SetupReadinessPlatform.macos;
    final isWin = platform == SetupReadinessPlatform.windows;
    final isLinuxPlatform = platform == SetupReadinessPlatform.linux;
    final appInstalled = isMac || isWin ? bind.mainIsInstalled() : true;

    return resolveSetupReadinessIssues(
      SetupReadinessSnapshot(
        platform: platform,
        systemError: systemError,
        outgoingOnly: bind.isOutgoingOnly(),
        serviceStopped: svcStopped.value,
        installationDisabled: true,
        appInstalled: appInstalled,
        canScreenRecord: !isMac || bind.mainIsCanScreenRecording(prompt: false),
        processTrusted: !isMac || bind.mainIsProcessTrusted(prompt: false),
        canMonitorInput: !isMac || bind.mainIsCanInputMonitoring(prompt: false),
        localNetworkDenied:
            isMac &&
            _localNetworkPermission == LocalNetworkPermissionStatus.denied,
        daemonInstalled: true,
        selinuxEnforcing: isLinuxPlatform && bind.isSelinuxEnforcing(),
        showSelinuxWarning:
            !isLinuxPlatform ||
            bind.mainGetLocalOption(key: _showSelinuxHelpTipOption) != 'N',
        currentSessionWayland: isLinuxPlatform && bind.mainCurrentIsWayland(),
        loginSessionWayland: isLinuxPlatform && bind.mainIsLoginWayland(),
      ),
    );
  }

  List<LocalAccessRequirement> get _localSetupRequirements {
    String t(String zh, String en) => subnetText(context, zh, en);
    final issues = _setupReadinessIssues;
    final displayed = <SetupReadinessIssue>[
      if (isMacOS) ...[
        SetupReadinessIssue.screenRecording,
        SetupReadinessIssue.accessibility,
      ],
      // Input monitoring is for outgoing keyboard capture, not incoming access.
      ...issues.where((issue) =>
          issue != SetupReadinessIssue.inputMonitoring &&
          (!isMacOS ||
              (issue != SetupReadinessIssue.screenRecording &&
                  issue != SetupReadinessIssue.accessibility))),
    ];
    return [
      for (final issue in displayed)
        LocalAccessRequirement(
          id: issue.name,
          icon: _setupIssueIcon(issue),
          label: _setupIssueTitle(issue),
          description: _setupIssueDescription(issue),
          status: issues.contains(issue) ? t('待配置', 'Needs setup') : t('已就绪', 'Ready'),
          complete: !issues.contains(issue),
          actionLabel: issues.contains(issue) && _setupIssueHasAction(issue)
              ? _setupIssueActionLabel(issue) : '',
          onPressed: issues.contains(issue) && _setupIssueHasAction(issue)
              ? () => _performSetupIssueAction(issue) : null,
          onDismiss: issue == SetupReadinessIssue.selinux
              ? () => _dismissSetupIssue(issue) : null,
        ),
    ];
  }

  String _setupIssueTitle(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.systemError:
        return translate('Error');
      case SetupReadinessIssue.applicationInstall:
        return translate('Installation');
      case SetupReadinessIssue.screenRecording:
        return subnetText(context, '屏幕录制', 'Screen recording');
      case SetupReadinessIssue.accessibility:
        return subnetText(context, '辅助功能', 'Accessibility');
      case SetupReadinessIssue.inputMonitoring:
        return subnetText(context, '输入监控', 'Input monitoring');
      case SetupReadinessIssue.localNetwork:
        return subnetText(context, '本地网络', 'Local network');
      case SetupReadinessIssue.daemon:
        return translate('Service');
      case SetupReadinessIssue.selinux:
      case SetupReadinessIssue.wayland:
      case SetupReadinessIssue.loginWayland:
        return translate('Warning');
    }
  }

  String _setupIssueDescription(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.systemError:
        return systemError;
      case SetupReadinessIssue.applicationInstall:
        return bind.isOutgoingOnly() ? '' : translate('install_tip');
      case SetupReadinessIssue.screenRecording:
        return translate('config_screen');
      case SetupReadinessIssue.accessibility:
        return translate('config_acc');
      case SetupReadinessIssue.inputMonitoring:
        return translate('config_input');
      case SetupReadinessIssue.localNetwork:
        return '${translate('Open System Setting')}: '
            '${translate('Network')} · ${translate('Enable LAN discovery')}';
      case SetupReadinessIssue.daemon:
        return translate('install_daemon_tip');
      case SetupReadinessIssue.selinux:
        return translate('selinux_tip');
      case SetupReadinessIssue.wayland:
        return translate('wayland_experiment_tip');
      case SetupReadinessIssue.loginWayland:
        return translate('Login screen using Wayland is not supported');
    }
  }

  IconData _setupIssueIcon(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.systemError:
        return Icons.error_outline_rounded;
      case SetupReadinessIssue.applicationInstall:
        return Icons.download_for_offline_outlined;
      case SetupReadinessIssue.screenRecording:
        return Icons.screen_share_outlined;
      case SetupReadinessIssue.accessibility:
        return Icons.accessibility_new_rounded;
      case SetupReadinessIssue.inputMonitoring:
        return Icons.keyboard_alt_outlined;
      case SetupReadinessIssue.localNetwork:
        return Icons.lan_outlined;
      case SetupReadinessIssue.daemon:
        return Icons.settings_suggest_outlined;
      case SetupReadinessIssue.selinux:
      case SetupReadinessIssue.wayland:
      case SetupReadinessIssue.loginWayland:
        return Icons.warning_amber_rounded;
    }
  }

  bool _setupIssueHasAction(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.applicationInstall:
      case SetupReadinessIssue.screenRecording:
      case SetupReadinessIssue.accessibility:
      case SetupReadinessIssue.inputMonitoring:
      case SetupReadinessIssue.localNetwork:
      case SetupReadinessIssue.daemon:
      case SetupReadinessIssue.selinux:
      case SetupReadinessIssue.wayland:
      case SetupReadinessIssue.loginWayland:
        return true;
      case SetupReadinessIssue.systemError:
        return false;
    }
  }

  String _setupIssueActionLabel(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.applicationInstall:
      case SetupReadinessIssue.daemon:
        return translate('Install');
      case SetupReadinessIssue.screenRecording:
      case SetupReadinessIssue.accessibility:
      case SetupReadinessIssue.inputMonitoring:
      case SetupReadinessIssue.localNetwork:
        return translate('Configure');
      case SetupReadinessIssue.selinux:
      case SetupReadinessIssue.wayland:
      case SetupReadinessIssue.loginWayland:
        return translate('Help');
      case SetupReadinessIssue.systemError:
        return '';
    }
  }

  String? _setupIssueHelpUrl(SetupReadinessIssue issue) {
    switch (issue) {
      case SetupReadinessIssue.selinux:
        return _selinuxHelpUrl;
      case SetupReadinessIssue.wayland:
        return _waylandHelpUrl;
      case SetupReadinessIssue.loginWayland:
        return _loginWaylandHelpUrl;
      case SetupReadinessIssue.systemError:
      case SetupReadinessIssue.applicationInstall:
      case SetupReadinessIssue.screenRecording:
      case SetupReadinessIssue.accessibility:
      case SetupReadinessIssue.inputMonitoring:
      case SetupReadinessIssue.localNetwork:
      case SetupReadinessIssue.daemon:
        return null;
    }
  }

  Future<void> _dismissSetupIssue(SetupReadinessIssue issue) async {
    if (issue != SetupReadinessIssue.selinux) return;
    await bind.mainSetLocalOption(key: _showSelinuxHelpTipOption, value: 'N');
    if (mounted) setState(() {});
  }

  Future<void> _performSetupIssueAction(SetupReadinessIssue issue) async {
    switch (issue) {
      case SetupReadinessIssue.applicationInstall:
        await rustDeskWinManager.closeAllSubWindows();
        bind.mainGotoInstall();
        break;
      case SetupReadinessIssue.screenRecording:
        bind.mainIsCanScreenRecording(prompt: true);
        watchIsCanScreenRecording = true;
        break;
      case SetupReadinessIssue.accessibility:
        bind.mainIsProcessTrusted(prompt: true);
        watchIsProcessTrust = true;
        break;
      case SetupReadinessIssue.inputMonitoring:
        bind.mainIsCanInputMonitoring(prompt: true);
        watchIsInputMonitoring = true;
        break;
      case SetupReadinessIssue.localNetwork:
        await RdPlatformChannel.instance.openLocalNetworkSettings();
        break;
      case SetupReadinessIssue.daemon:
        bind.mainIsInstalledDaemon(prompt: true);
        watchIsInstalledDaemon = true;
        break;
      case SetupReadinessIssue.selinux:
      case SetupReadinessIssue.wayland:
      case SetupReadinessIssue.loginWayland:
        final helpUrl = _setupIssueHelpUrl(issue);
        if (helpUrl != null) {
          await launchUrl(Uri.parse(helpUrl));
        }
        break;
      case SetupReadinessIssue.systemError:
        break;
    }
    if (mounted) setState(() {});
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
      block: _block,
      mask: true,
      use: canBeBlocked,
      child: child,
    );
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (bind.isCustomClient())
        Align(alignment: Alignment.center, child: loadPowered(context)),
      Align(alignment: Alignment.center, child: loadLogo()),
      buildTip(context),
      if (!isOutgoingOnly) const LanServerInfoPanel(compact: true),
      FutureBuilder<Widget>(
        future: Future.value(buildHelpCards()),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6),
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 340.0 : 300.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(key: _childKey, children: children),
                ),
                Expanded(child: Container()),
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                            DesktopSettingPage.tabKeys[0],
                          ),
                        },
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(
        selectedPeerTab: _selectedPeerTab,
        favoriteGroupId: _selectedPeerTab == PeerTabIndex.fav
            ? _selectedFavoriteGroupId
            : null,
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding: const EdgeInsets.only(
        left: 20.0,
        right: 16,
        top: 16.0,
        bottom: 5,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(height: 10.0),
          if (!isOutgoingOnly)
            Text(
              '${translate("Local Address")} · ${translate("Username")} · ${translate("Password")}',
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards() {
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
          "",
          bind.isOutgoingOnly() ? "" : "install_tip",
          "Install",
          () async {
            await rustDeskWinManager.closeAllSubWindows();
            bind.mainGotoInstall();
          },
        );
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard(
          "Permissions",
          "config_screen",
          "Configure",
          () async {
            bind.mainIsCanScreenRecording(prompt: true);
            watchIsCanScreenRecording = true;
          },
        );
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_acc",
          "Configure",
          () async {
            bind.mainIsProcessTrusted(prompt: true);
            watchIsProcessTrust = true;
          },
        );
      } else if (!bind.isIncomingOnly() &&
          !bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard(
          "Permissions",
          "config_input",
          "Configure",
          () async {
            bind.mainIsCanInputMonitoring(prompt: true);
            watchIsInputMonitoring = true;
          },
        );
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        if (bind.mainGetLocalOption(key: _showSelinuxHelpTipOption) != 'N') {
          LinuxCards.add(
            buildInstallCard(
              "Warning",
              "selinux_tip",
              "",
              () async {},
              marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
              help: 'Help',
              link: _selinuxHelpUrl,
              closeButton: true,
              closeOption: _showSelinuxHelpTipOption,
            ),
          );
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(
          buildInstallCard(
            "Warning",
            "wayland_experiment_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: _waylandHelpUrl,
          ),
        );
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(
          buildInstallCard(
            "Warning",
            "Login screen using Wayland is not supported",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: _loginWaylandHelpUrl,
          ),
        );
      }
      if (LinuxCards.isNotEmpty) {
        return Column(children: LinuxCards);
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(
    String title,
    String content,
    String btnText,
    GestureTapCallback onPressed, {
    double marginTop = 20.0,
    String? help,
    String? link,
    bool? closeButton,
    String? closeOption,
  }) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
            0,
            marginTop,
            0,
            bind.isIncomingOnly() ? marginTop : 0,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              ),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  (title.isNotEmpty
                      ? <Widget>[
                          Center(
                            child: Text(
                              translate(title),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ).marginOnly(bottom: 6),
                          ),
                        ]
                      : <Widget>[]) +
                  <Widget>[
                    if (content.isNotEmpty)
                      Text(
                        translate(content),
                        style: TextStyle(
                          height: 1.5,
                          color: Colors.white,
                          fontWeight: FontWeight.normal,
                          fontSize: 13,
                        ),
                      ).marginOnly(bottom: 20),
                  ] +
                  (btnText.isNotEmpty
                      ? <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FixedWidthButton(
                                width: 150,
                                padding: 8,
                                isOutline: true,
                                text: translate(btnText),
                                textColor: Colors.white,
                                borderColor: Colors.white,
                                textSize: 20,
                                radius: 10,
                                onTap: onPressed,
                              ),
                            ],
                          ),
                        ]
                      : <Widget>[]) +
                  (help != null && link != null
                      ? <Widget>[
                          Center(
                            child: InkWell(
                              onTap: () async =>
                                  await launchUrl(Uri.parse(link)),
                              child: Text(
                                translate(help),
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ).marginOnly(top: 6),
                          ),
                        ]
                      : <Widget>[]),
            ),
          ),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    favoriteGroupModel.load();
    if (isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkLocalNetworkPermission();
      });
    }
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsInstalledDaemon) {
        if (bind.mainIsInstalledDaemon(prompt: false)) {
          watchIsInstalledDaemon = false;
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
      'frame': {
        'l': screen.frame.left,
        't': screen.frame.top,
        'r': screen.frame.right,
        'b': screen.frame.bottom,
      },
      'visibleFrame': {
        'l': screen.visibleFrame.left,
        't': screen.visibleFrame.top,
        'r': screen.visibleFrame.right,
        'b': screen.visibleFrame.bottom,
      },
      'scaleFactor': screen.scaleFactor,
    };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse:
          return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint("[Main] call ${call.method} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
          (await window_size.getScreenList()).map(screenToMap).toList(),
        );
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy'],
        );
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id: $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type: $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
            windowId,
            args[1],
            args[2],
            windowType,
          );
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
          windowId,
          peerId,
          display,
          displayCount,
          screenRect,
          windowType,
        );
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
            await rustDeskWinManager.getOtherRemoteWindowCoords(windowId),
          );
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      shouldBeBlocked(_block, canBeBlocked);
      if (isMacOS) {
        _checkLocalNetworkPermission();
      }
    }
  }

  Future<void> _checkLocalNetworkPermission() async {
    if (_checkingLocalNetworkPermission) return;
    _checkingLocalNetworkPermission = true;
    try {
      final status = await RdPlatformChannel.instance
          .checkLocalNetworkPermission();
      if (mounted && status != LocalNetworkPermissionStatus.checking) {
        setState(() => _localNetworkPermission = status);
      }
    } on PlatformException catch (error) {
      debugPrint('Failed to check local-network permission: $error');
    } finally {
      _checkingLocalNetworkPermission = false;
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          }),
        ],
      ),
    );
  }
}
