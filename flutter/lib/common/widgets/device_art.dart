import 'package:flutter/material.dart';

enum DeviceKind { phone, tablet, laptop, desktop, allInOne, server }

/// Explicit hardware metadata wins. Legacy peers only provide OS and hostname;
/// do not infer a server just because its OS is Linux, or use a mutable alias.
DeviceKind resolveDeviceKind({
  String deviceType = '',
  String platform = '',
  String hostname = '',
}) {
  final explicit = switch (deviceType.toLowerCase()) {
    'phone' => DeviceKind.phone,
    'tablet' => DeviceKind.tablet,
    'laptop' => DeviceKind.laptop,
    'desktop' => DeviceKind.desktop,
    'all-in-one' => DeviceKind.allInOne,
    'server' => DeviceKind.server,
    _ => null,
  };
  if (explicit != null) return explicit;
  final os = platform.toLowerCase();
  final name = hostname.toLowerCase();
  if (os.contains('ipad') ||
      name.contains('ipad') ||
      name.contains('tablet') ||
      name.contains('galaxy-tab')) {
    return DeviceKind.tablet;
  }
  if (os == 'android' || os == 'ios' || os.contains('iphone')) {
    return DeviceKind.phone;
  }
  if (name.contains('macbook') ||
      name.contains('laptop') ||
      name.contains('notebook') ||
      name.contains('thinkpad')) {
    return DeviceKind.laptop;
  }
  if (os.contains('server') ||
      RegExp(r'(^|[\s_.-])(server|srv)([\s_.-]|$)').hasMatch(name)) {
    return DeviceKind.server;
  }
  if (name.contains('imac')) return DeviceKind.allInOne;
  return DeviceKind.desktop;
}

extension DeviceKindAppearance on DeviceKind {
  String get asset => switch (this) {
    DeviceKind.phone => 'assets/subnetdesk-phone.png',
    DeviceKind.tablet => 'assets/subnetdesk-tablet.png',
    DeviceKind.laptop => 'assets/subnetdesk-local-laptop.png',
    DeviceKind.desktop => 'assets/subnetdesk-desktop.png',
    DeviceKind.allInOne => 'assets/subnetdesk-device.png',
    DeviceKind.server => 'assets/subnetdesk-server.png',
  };

  IconData get icon => switch (this) {
    DeviceKind.phone => Icons.smartphone_outlined,
    DeviceKind.tablet => Icons.tablet_outlined,
    DeviceKind.laptop => Icons.laptop_outlined,
    DeviceKind.desktop || DeviceKind.allInOne => Icons.desktop_windows_outlined,
    DeviceKind.server => Icons.dns_outlined,
  };
}

class DeviceArt extends StatelessWidget {
  const DeviceArt({
    super.key,
    required this.kind,
    required this.width,
    required this.height,
  });

  final DeviceKind kind;
  final double width, height;

  @override
  Widget build(BuildContext context) => Image.asset(
    kind.asset,
    width: width,
    height: height,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) => SizedBox(
      width: width,
      height: height,
      child: Icon(kind.icon, size: height * .65),
    ),
  );
}
