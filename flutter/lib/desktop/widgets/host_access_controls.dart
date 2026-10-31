import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/widgets/subnet_ui.dart';
import '../host_access_state.dart';

/// Homepage controls for this computer, with an anchored prerequisite guide.
class HostAccessControls extends StatefulWidget {
  const HostAccessControls({
    super.key,
    required this.state,
    required this.permissionLabel,
    required this.onDiscoveryChanged,
    required this.onRemoteChanged,
    required this.onConfigure,
  });

  final HostAccessState state;
  final String permissionLabel;
  final Future<void> Function(bool) onDiscoveryChanged;
  final Future<bool> Function(bool) onRemoteChanged;
  final VoidCallback onConfigure;

  @override
  State<HostAccessControls> createState() => _HostAccessControlsState();
}

class _HostAccessControlsState extends State<HostAccessControls> {
  final _guide = OverlayPortalController();

  String t(String zh, String en) => subnetText(context, zh, en);

  Future<void> _remoteChanged(bool enabled) async {
    if (await widget.onRemoteChanged(enabled) || !mounted) return;
    if (_guide.isShowing) {
      _guide.hide();
      return;
    }
    if (MediaQuery.sizeOf(context).width < 800 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 320,
            child: _guidance(() {
              Navigator.of(dialogContext).pop();
              widget.onConfigure();
            }),
          ),
        ),
      );
    } else {
      _guide.show();
    }
  }

  Widget _guidance(VoidCallback configure) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('host-access-guide'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('开启远程前，先完成配置', 'Set up this computer first'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                '在「本机」中完成以下设置，才能允许远程访问。',
                'Complete these steps in This device to allow remote access.',
              ),
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            _requirement(
              '1',
              t('设置访问密码', 'Set an access password'),
              widget.state.configured,
            ),
            const Divider(height: 24),
            _requirement(
              '2',
              widget.permissionLabel,
              widget.state.permissionsReady,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('host-access-configure'),
                onPressed: configure,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.all(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        t('前往本机配置', 'Set up in This device'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.north_east_rounded, size: 17),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                t('配置完成后才能开启', 'Setup is required before enabling'),
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requirement(String number, String label, bool complete) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: complete
            ? const Icon(
                Icons.check_rounded,
                size: 16,
                color: Color(0xFF527D61),
              )
            : Text(number, style: const TextStyle(fontSize: 12)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 13, height: 1.5)),
      ),
    ],
  );

  Widget _toggle({
    required String id,
    required IconData icon,
    required String label,
    required String description,
    required String status,
    required bool value,
    required Future<void> Function(bool) changed,
    bool pending = false,
  }) {
    final theme = Theme.of(context);
    final enabled = !widget.state.loading && !widget.state.busy;
    const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    final statusStyle = TextStyle(
      fontSize: 11,
      color: pending ? const Color(0xFFBA7D22) : theme.hintColor,
    );
    final textWidth = math.max(
      subnetTextWidth(context, label, labelStyle),
      subnetTextWidth(context, status, statusStyle),
    );
    return Tooltip(
      message: description,
      child: Semantics(
        label: '$label，$status',
        toggled: value,
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('host-access-$id'),
            onTap: enabled ? () => changed(!value) : null,
            child: SizedBox(
              width: math.max(172, textWidth + 20 + 19 + 8 + 12 + 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(icon, size: 19),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label, style: labelStyle),
                            const SizedBox(height: 3),
                            Text(status, style: statusStyle),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 44,
                        height: 28,
                        child: FittedBox(
                          child: IgnorePointer(
                            child: Theme(
                              data: ThemeData.from(
                                colorScheme: theme.colorScheme,
                                useMaterial3: true,
                              ),
                              child: Switch(
                                value: value,
                                onChanged: enabled ? (_) {} : null,
                                activeTrackColor: const Color(0xFFA590DD),
                                activeThumbColor: Colors.white,
                                inactiveTrackColor:
                                    theme.brightness == Brightness.dark
                                    ? const Color(0xFF625969)
                                    : const Color(0xFFCAC6CC),
                                inactiveThumbColor: Colors.white,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    String status(bool enabled) => state.loading
        ? t('检查中', 'Checking')
        : state.busy
        ? t('更新中', 'Updating')
        : enabled
        ? t('已开启', 'On')
        : t('已关闭', 'Off');
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _guide,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final top = anchor.bottom + 12;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _guide.hide,
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _guide.hide,
                  ),
                ),
                Positioned(
                  top: top,
                  right: math.max(16, info.overlaySize.width - anchor.right),
                  width: math.min(300, info.overlaySize.width - 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        80,
                        info.overlaySize.height - top - 16,
                      ),
                    ),
                    child: _guidance(() {
                      _guide.hide();
                      widget.onConfigure();
                    }),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            t('本机', 'This device'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          _toggle(
            id: 'discovery',
            icon: Icons.wifi_tethering_rounded,
            label: t('可被发现', 'Discoverable'),
            description: t(
              '允许同一局域网内的设备发现本机',
              'Allow devices on this LAN to discover this computer',
            ),
            status: status(state.discoveryEnabled),
            value: state.discoveryEnabled,
            changed: widget.onDiscoveryChanged,
          ),
          _toggle(
            id: 'remote',
            icon: Icons.desktop_windows_outlined,
            label: t('可被远程', 'Remote access'),
            description: state.error.isNotEmpty
                ? state.error
                : t(
                    '允许其他设备远程控制本机',
                    'Allow other devices to control this computer',
                  ),
            status: !state.loading && !state.busy && !state.canEnableRemote
                ? t('待配置', 'Needs setup')
                : !state.loading && !state.busy && state.error.isNotEmpty
                ? t('服务异常', 'Service error')
                : !state.loading &&
                      !state.busy &&
                      !state.serviceStopped &&
                      !state.running
                ? t('启动中', 'Starting')
                : status(state.remoteEnabled),
            value: state.remoteEnabled,
            pending: !state.loading && !state.canEnableRemote,
            changed: _remoteChanged,
          ),
        ],
      ),
    );
  }
}
