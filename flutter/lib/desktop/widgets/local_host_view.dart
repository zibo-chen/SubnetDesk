import 'package:flutter/material.dart';

import '../../common/widgets/subnet_ui.dart';
import '../../common/widgets/device_art.dart';

class LocalAccessRequirement {
  const LocalAccessRequirement({
    required this.id,
    required this.icon,
    required this.label,
    required this.status,
    required this.complete,
    required this.onPressed,
    this.description = '',
    this.actionLabel = '',
    this.onDismiss,
  });

  final String id;
  final IconData icon;
  final String label, status, description, actionLabel;
  final bool complete;
  final VoidCallback? onPressed;
  final VoidCallback? onDismiss;
}

/// The desktop local-device surface; host state and actions stay in its adapter.
class LocalHostView extends StatelessWidget {
  const LocalHostView({
    super.key,
    required this.deviceName,
    required this.platform,
    this.deviceType = '',
    this.systemDeviceName = '',
    required this.endpoint,
    required this.status,
    required this.ready,
    required this.requirements,
    required this.onRename,
    required this.onCopyAddress,
    required this.onOtherAddresses,
    required this.onIdentity,
    required this.onAdvanced,
    this.loading = false,
    this.notice = '',
    this.additionalActions,
  });

  final String deviceName, platform, endpoint, status, notice;
  final String deviceType, systemDeviceName;
  final bool ready, loading;
  final List<LocalAccessRequirement> requirements;
  final VoidCallback? onRename, onCopyAddress, onOtherAddresses;
  final VoidCallback? onIdentity, onAdvanced;
  final Widget? additionalActions;

  @override
  Widget build(BuildContext context) {
    String t(String zh, String en) => subnetText(context, zh, en);
    final theme = Theme.of(context);
    final muted = theme.hintColor;
    final kind = resolveDeviceKind(
      deviceType: deviceType,
      platform: platform,
      hostname: systemDeviceName,
    );
    final statusColor = loading
        ? muted
        : ready
        ? const Color(0xFF527D61)
        : const Color(0xFFBA7D22);
    final hasPending = requirements.any((item) => !item.complete);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(50, 12, 50, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('本机', 'This device'),
                      key: const ValueKey('local-host-title'),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Semantics(
                      key: const ValueKey('local-host-status'),
                      liveRegion: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ready ? Icons.check_circle_outline : Icons.circle,
                            size: ready ? 15 : 8,
                            color: statusColor,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              status,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final artHeight = (constraints.maxHeight - 440).clamp(
                60.0,
                144.0,
              );
              return SingleChildScrollView(
                key: const ValueKey('local-host-scroll'),
                padding: const EdgeInsets.fromLTRB(50, 8, 50, 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 800,
                      minHeight: (constraints.maxHeight - 16).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DeviceArt(
                              kind: kind,
                              key: const ValueKey('local-host-art'),
                              width: 240,
                              height: artHeight,
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 40),
                                  Flexible(
                                    child: Text(
                                      deviceName,
                                      key: const ValueKey('local-host-name'),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey('local-host-rename'),
                                    tooltip: t('修改设备名称', 'Rename device'),
                                    onPressed: onRename,
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$platform · ${t('此设备', 'This device')}',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                            const SizedBox(height: 10),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    t('连接地址', 'Connection address'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    key: const ValueKey('local-host-address'),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      2,
                                      8,
                                      2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: .38),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final address = SelectableText(
                                          endpoint.isEmpty
                                              ? t(
                                                  '暂无可用地址',
                                                  'No address available',
                                                )
                                              : endpoint,
                                          key: const ValueKey(
                                            'local-host-endpoint',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontFamily: 'Menlo',
                                            fontFamilyFallback: [
                                              'Consolas',
                                              'DejaVu Sans Mono',
                                              'monospace',
                                            ],
                                          ),
                                        );
                                        final copy = TextButton.icon(
                                          key: const ValueKey(
                                            'local-host-copy',
                                          ),
                                          onPressed: onCopyAddress,
                                          icon: const Icon(
                                            Icons.copy_outlined,
                                            size: 17,
                                          ),
                                          label: Text(
                                            t('复制地址', 'Copy address'),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                        if (box.maxWidth < 370 ||
                                            MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(1) >
                                                1.3) {
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 10),
                                              address,
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: copy,
                                              ),
                                            ],
                                          );
                                        }
                                        return Row(
                                          children: [
                                            Expanded(child: address),
                                            copy,
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  if (onOtherAddresses != null)
                                    Center(
                                      child: TextButton.icon(
                                        key: const ValueKey(
                                          'local-host-other-addresses',
                                        ),
                                        onPressed: onOtherAddresses,
                                        label: Text(
                                          t('其他地址', 'Other addresses'),
                                        ),
                                        icon: const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 17,
                                        ),
                                        iconAlignment: IconAlignment.end,
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(44, 32),
                                          textStyle: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 32),
                                ],
                              ),
                            ),
                            if (notice.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                notice,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                ),
                              ),
                            ],
                            if (additionalActions != null) ...[
                              const SizedBox(height: 8),
                              additionalActions!,
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 800),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    hasPending
                                        ? t('接入前需要完成', 'Before allowing access')
                                        : t('接入设置', 'Access settings'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LayoutBuilder(
                                    builder: (context, box) {
                                      final columns =
                                          box.maxWidth >= 720 &&
                                              MediaQuery.textScalerOf(
                                                    context,
                                                  ).scale(1) <=
                                                  1.3
                                          ? requirements.length == 3
                                                ? 3
                                                : 2
                                          : 1;
                                      return Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 24,
                                        children: [
                                          for (final item in requirements)
                                            SizedBox(
                                              width:
                                                  (box.maxWidth -
                                                      24 * (columns - 1)) /
                                                  columns,
                                              child: _requirement(
                                                context,
                                                item,
                                                centered: columns > 1,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  key: const ValueKey('local-host-identity'),
                                  onPressed: onIdentity,
                                  label: Text(t('设备身份', 'Device identity')),
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 17,
                                  ),
                                  iconAlignment: IconAlignment.end,
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  key: const ValueKey('local-host-advanced'),
                                  onPressed: onAdvanced,
                                  label: Text(t('高级设置', 'Advanced settings')),
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 17,
                                  ),
                                  iconAlignment: IconAlignment.end,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _requirement(
    BuildContext context,
    LocalAccessRequirement item, {
    required bool centered,
  }) {
    final theme = Theme.of(context);
    String t(String zh, String en) => subnetText(context, zh, en);
    final color = loading
        ? theme.hintColor
        : item.complete
        ? const Color(0xFF527D61)
        : const Color(0xFFBA7D22);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              item.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.complete && !loading
                      ? Icons.check_circle_outline
                      : Icons.circle,
                  size: item.complete && !loading ? 13 : 7,
                  color: color,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    loading ? t('检查中', 'Checking') : item.status,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.actionLabel.isNotEmpty)
          OutlinedButton(
            key: ValueKey('local-host-requirement-${item.id}-action'),
            onPressed: loading ? null : item.onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(item.actionLabel),
          ),
        if (item.onDismiss != null)
          IconButton(
            key: ValueKey('local-host-requirement-${item.id}-dismiss'),
            tooltip: t('关闭', 'Dismiss'),
            onPressed: loading ? null : item.onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
      ],
    );
    return Padding(
      key: ValueKey('local-host-requirement-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final stacked =
              box.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return Align(
            alignment: centered ? Alignment.center : Alignment.centerLeft,
            child: Row(
              mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .5,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, size: 19),
                ),
                const SizedBox(width: 12),
                Flexible(
                  fit: centered ? FlexFit.loose : FlexFit.tight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      details,
                      if (stacked &&
                          (item.actionLabel.isNotEmpty ||
                              item.onDismiss != null)) ...[
                        const SizedBox(height: 8),
                        actions,
                      ],
                    ],
                  ),
                ),
                if (!stacked &&
                    (item.actionLabel.isNotEmpty ||
                        item.onDismiss != null)) ...[
                  const SizedBox(width: 12),
                  actions,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
