import 'package:flutter/material.dart';

/// Always-visible text and an icon; color is only a secondary status cue.
class PeerStatusBadge extends StatelessWidget {
  const PeerStatusBadge({
    super.key,
    required this.online,
    required this.label,
    required this.tooltip,
  });

  final bool? online;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (online) {
      true => dark ? const Color(0xFF81C995) : const Color(0xFF176B3A),
      false => dark ? const Color(0xFFB7BEC9) : const Color(0xFF586174),
      null => dark ? const Color(0xFFE8BE78) : const Color(0xFF8A5900),
    };
    final icon = switch (online) {
      true => Icons.check_circle_outline,
      false => Icons.cloud_off_outlined,
      null => Icons.help_outline,
    };
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        label: '$label. $tooltip',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
