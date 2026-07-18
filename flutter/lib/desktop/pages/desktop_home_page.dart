import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/lan_server_status.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class LanServerInfoPanel extends StatefulWidget {
  const LanServerInfoPanel({Key? key, this.compact = false}) : super(key: key);

  final bool compact;

  @override
  State<LanServerInfoPanel> createState() => _LanServerInfoPanelState();
}

class _LanServerInfoPanelState extends State<LanServerInfoPanel> {
  Timer? _timer;
  bool _showAllAddresses = false;

  int _addressPriority(String address) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null) return 5;
    if (parsed.isLoopback) return 4;
    final bytes = parsed.rawAddress;
    if (parsed.type == InternetAddressType.IPv4) {
      if (bytes[0] == 169 && bytes[1] == 254) return 3;
      final isPrivate = bytes[0] == 10 ||
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

  Map<String, dynamic> get _info {
    try {
      return jsonDecode(bind.mainGetLanServerInfoSync())
          as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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
    final displayStatus = lanServerDisplayStatus(
      configured: configured,
      running: running,
    );
    final statusLabel = switch (displayStatus) {
      LanServerDisplayStatus.authenticationRequired =>
        translate('Authentication Required'),
      LanServerDisplayStatus.ready => translate('Ready'),
      LanServerDisplayStatus.serviceStopped =>
        translate('Service is not running'),
    };
    final addresses = (info['addresses'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toSet()
        .toList()
      ..sort((a, b) {
        final priority = _addressPriority(a).compareTo(_addressPriority(b));
        return priority == 0 ? a.compareTo(b) : priority;
      });
    final port = info['port']?.toString() ?? '21118';
    final preferredAddresses =
        addresses.where((address) => _addressPriority(address) < 3).toList();
    final primaryAddress = preferredAddresses.isNotEmpty
        ? preferredAddresses.first
        : addresses.isEmpty
            ? null
            : addresses.first;
    final hiddenAddressCount =
        primaryAddress == null ? 0 : addresses.length - 1;
    final visibleAddresses = _showAllAddresses
        ? addresses
        : primaryAddress == null
            ? const <String>[]
            : <String>[primaryAddress];
    final endpoints = visibleAddresses
        .map((address) => _formatEndpoint(address, port))
        .join('\n');
    final fingerprint = info['fingerprint']?.toString() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white54 : const Color(0xFF7A8290);
    final statusColor = displayStatus == LanServerDisplayStatus.ready
        ? const Color(0xFF27B980)
        : const Color(0xFFF59E0B);
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
                    child: const Icon(
                      Icons.laptop_mac_rounded,
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
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'LAN · ${translate('Settings')}',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
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
                        onPressed: () => _showAddressList(
                          context,
                          addresses,
                          port,
                        ),
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
                    color: displayStatus == LanServerDisplayStatus.ready
                        ? const Color(0xFF27B980)
                        : Colors.orange,
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
            const SizedBox(height: 14),
            Text(translate('Name'),
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 3),
            SelectableText(info['device_name']?.toString() ?? '-'),
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
            if (hiddenAddressCount > 0)
              TextButton.icon(
                onPressed: () => setState(
                  () => _showAllAddresses = !_showAllAddresses,
                ),
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
          width: 420,
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
    info = jsonDecode(bind.mainGetLanServerInfoSync()) as Map<String, dynamic>;
  } catch (_) {
    info = <String, dynamic>{};
  }
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
  var discoveryEnabled = info['discovery_enabled'] == true;
  var error = '';
  var saving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = Theme.of(context).colorScheme.primary;
        final muted = isDark ? Colors.white60 : const Color(0xFF737B8C);
        final fieldFill =
            isDark ? const Color(0xFF292C33) : const Color(0xFFF7F9FC);
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
                    child: Icon(Icons.info_outline_rounded,
                        size: 17, color: muted),
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

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF202228) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: 590,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: username,
                            autocorrect: false,
                            decoration: fieldDecoration(
                              label: translate('Username'),
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: password,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: fieldDecoration(
                              label: translate('Password'),
                              icon: Icons.lock_outline_rounded,
                              help: info['configured'] == true
                                  ? translate(
                                      'Leave blank to keep current password')
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: listenPort,
                            keyboardType: TextInputType.number,
                            decoration: fieldDecoration(
                              label: translate('Port'),
                              icon: Icons.tag_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                            onChanged: (value) => setDialogState(
                              () => discoveryEnabled = value,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.08),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(translate('Cancel')),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  setDialogState(() {
                                    saving = true;
                                    error = '';
                                  });
                                  final result =
                                      await bind.mainApplyLanSettings(
                                    username: username.text,
                                    password: password.text,
                                    listenAddresses: listenAddresses.text,
                                    listenPort: listenPort.text,
                                    allowedNetworks: allowedNetworks.text,
                                    discoveryEnabled: discoveryEnabled,
                                  );
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  password.clear();
  username.dispose();
  password.dispose();
  listenAddresses.dispose();
  listenPort.dispose();
  allowedNetworks.dispose();
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
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  PeerTabIndex _selectedPeerTab = PeerTabIndex.lan;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    if (!isIncomingOnly) {
      return _buildBlock(
        child: Row(
          children: [
            _buildNavigationSidebar(context),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: ConnectionPage(selectedPeerTab: _selectedPeerTab),
            ),
          ],
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

  Widget _buildNavigationSidebar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white60 : const Color(0xFF6F7786);
    final panelColor =
        isDark ? const Color(0xFF1E2026) : const Color(0xFFFBFCFE);
    return Container(
      width: 280,
      color: panelColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2684FF), Color(0xFF1266E3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1677FF).withOpacity(0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.desktop_windows_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SubnetDesk',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'LAN · ${translate('Discovered')}',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 18,
            endIndent: 18,
            color: isDark ? Colors.white10 : const Color(0xFFF0F2F6),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildSidebarItem(
                    context,
                    icon: Icons.devices_outlined,
                    label: translate('Discovered'),
                    tab: PeerTabIndex.lan,
                  ),
                  _buildSidebarItem(
                    context,
                    icon: Icons.history_rounded,
                    label: translate('Recent sessions'),
                    tab: PeerTabIndex.recent,
                  ),
                  _buildSidebarItem(
                    context,
                    icon: Icons.star_border_rounded,
                    label: translate('Favorites'),
                    tab: PeerTabIndex.fav,
                  ),
                  _buildSidebarItem(
                    context,
                    icon: Icons.settings_outlined,
                    label: translate('Settings'),
                    onTap: () => DesktopSettingPage.switch2page(
                      DesktopSettingPage.tabKeys.first,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!bind.isOutgoingOnly())
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: LanServerInfoPanel(compact: true),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 20, 18),
            child: Row(
              children: [
                Icon(Icons.help_outline_rounded, size: 19, color: muted),
                const SizedBox(width: 9),
                Text(
                  translate('Help'),
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const Spacer(),
                Text(
                  version.isEmpty ? '' : 'v$version',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    PeerTabIndex? tab,
    VoidCallback? onTap,
  }) {
    final selected = tab != null && _selectedPeerTab == tab;
    final primary = Theme.of(context).colorScheme.primary;
    final foreground = selected
        ? primary
        : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.68);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
      child: Material(
        color: selected
            ? primary.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.08,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap ??
              () {
                if (tab != null) {
                  setState(() => _selectedPeerTab = tab);
                  gFFI.peerTabModel.setCurrentTab(tab.index);
                }
              },
          child: Container(
            height: 46,
            decoration: selected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(color: primary, width: 3),
                    ),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 21, color: foreground),
                const SizedBox(width: 13),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      child: ConnectionPage(selectedPeerTab: _selectedPeerTab),
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
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
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
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(
            buildInstallCard(
              "Warning",
              "selinux_tip",
              "",
              () async {},
              marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
              closeButton: true,
              closeOption: keyShowSelinuxHelpTip,
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
              children: (title.isNotEmpty
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
                  <Widget>[],
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
        debugPrint(
          "[Main] call ${call.method} from window $fromWindowId",
        );
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
      shouldBeBlocked(_block, canBeBlocked);
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
