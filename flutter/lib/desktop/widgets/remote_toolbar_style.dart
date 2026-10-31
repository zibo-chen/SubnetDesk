import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Tabler's outline set, kept as local assets with its upstream MIT license.
class RemoteToolbarIcon extends StatelessWidget {
  const RemoteToolbarIcon(this.name, {super.key, this.size = 26, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/remote_toolbar/$name.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
  );
}

/// Shared by the expanded toolbar and its compact edge handle.
abstract final class RemoteToolbarStyle {
  static const buttonSize = 40.0;
  static const buttonHMargin = 4.0;
  static const buttonVMargin = 8.0;
  static const iconSize = 26.0;
  static const radius = 28.0;

  static ButtonStyle buttonStyle(
    BuildContext context, {
    bool selected = false,
    bool danger = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = danger ? colors.error : colors.onSurface;
    return ButtonStyle(
      alignment: Alignment.center,
      minimumSize: const WidgetStatePropertyAll(Size(buttonSize, buttonSize)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: WidgetStatePropertyAll(foreground),
      iconColor: WidgetStatePropertyAll(foreground),
      iconSize: const WidgetStatePropertyAll(iconSize),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (danger) {
          return colors.error.withValues(
            alpha: states.contains(WidgetState.hovered) ? .16 : .08,
          );
        }
        if (selected || states.contains(WidgetState.hovered)) {
          return colors.surfaceContainerHighest;
        }
        return Colors.transparent;
      }),
      overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: .08)),
      side: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.focused)
            ? BorderSide(color: foreground.withValues(alpha: .6))
            : BorderSide.none;
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// A single scrollable surface, with no separate panel beneath the actions.
class RemoteToolbarSurface extends StatelessWidget {
  const RemoteToolbarSurface({
    super.key,
    required this.isHorizontal,
    required this.children,
    this.compact = false,
    this.borderRadius,
  });

  final bool isHorizontal;
  final List<Widget> children;
  final bool compact;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius =
        borderRadius ?? BorderRadius.circular(RemoteToolbarStyle.radius);
    final axis = isHorizontal ? Axis.horizontal : Axis.vertical;
    return Material(
      color: colors.surface,
      elevation: 3,
      shadowColor: colors.onSurface.withValues(alpha: .18),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: colors.outline.withValues(alpha: .55),
          width: .7,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: axis,
        child: Padding(
          padding: isHorizontal
              ? EdgeInsets.symmetric(horizontal: compact ? 4 : 12)
              : EdgeInsets.symmetric(vertical: compact ? 4 : 12),
          child: MenuBarTheme(
            data: MenuBarThemeData(
              style: MenuStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                side: const WidgetStatePropertyAll(BorderSide.none),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
              ),
            ),
            child: Flex(
              direction: axis,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class RemoteToolbarSeparator extends StatelessWidget {
  const RemoteToolbarSeparator({super.key, required this.isHorizontal});

  final bool isHorizontal;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline.withValues(alpha: .7);
    return SizedBox(
      width: isHorizontal ? 20 : 28,
      height: isHorizontal ? 28 : 20,
      child: isHorizontal
          ? VerticalDivider(width: 20, thickness: 1, color: color)
          : Divider(height: 20, thickness: 1, color: color),
    );
  }
}

class RemoteToolbarGrip extends StatelessWidget {
  const RemoteToolbarGrip({
    super.key,
    required this.isHorizontal,
    this.compact = false,
  });

  final bool isHorizontal;
  final bool compact;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.grab,
    child: SizedBox(
      width: isHorizontal ? (compact ? 28 : 36) : (compact ? 32 : 40),
      height: isHorizontal ? (compact ? 32 : 40) : (compact ? 28 : 36),
      child: Center(
        child: RemoteToolbarIcon(
          isHorizontal ? 'grip-vertical' : 'grip-horizontal',
          size: 20,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .4),
        ),
      ),
    ),
  );
}
