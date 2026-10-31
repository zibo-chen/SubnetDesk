import 'package:flutter/material.dart';

import '../app_language.dart';

/// Shared desktop/mobile foundations for the approved porcelain/lilac design.
abstract final class SubnetPalette {
  static const canvas = Color(0xFFF8F5F0);
  static const ink = Color(0xFF332B3B);
  static const lilac = Color(0xFFDDD7EE);
  static const muted = Color(0xFF716B78);
  static const line = Color(0xFFE5DFE7);
  static const darkCanvas = Color(0xFF211E27);

  static ThemeData apply(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final canvas = dark ? darkCanvas : SubnetPalette.canvas;
    final surface = dark ? const Color(0xFF2C2633) : const Color(0xFFFFFCF8);
    final ink = dark ? const Color(0xFFF0EAF5) : SubnetPalette.ink;
    final primary = dark ? const Color(0xFFC7BAE8) : SubnetPalette.ink;
    final border = dark ? const Color(0xFF49414F) : line;
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      dividerColor: border,
      hintColor: dark ? const Color(0xFFB4AABB) : muted,
      textTheme: text,
      iconTheme: IconThemeData(color: ink, size: 24),
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        onPrimary: dark ? darkCanvas : Colors.white,
        secondary: primary,
        surface: surface,
        onSurface: ink,
        surfaceContainerHighest: dark ? const Color(0xFF39313F) : lilac,
        outline: border,
        // Older app surfaces still read this field.
        background: canvas,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: surface,
        elevation: 8,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF39313F) : const Color(0xFFF0EAF2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: base.colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: base.colorScheme.error, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark ? darkCanvas : Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const StadiumBorder(),
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(44, 44),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: dark
            ? const Color(0xFF39313F)
            : const Color(0xFFF0EBE7),
        selectedColor: dark ? const Color(0xFF514560) : lilac,
        secondarySelectedColor: dark ? const Color(0xFF514560) : lilac,
        labelStyle: TextStyle(color: ink, fontSize: 14),
        secondaryLabelStyle: TextStyle(color: ink, fontSize: 14),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: surface,
        shape: shape,
        elevation: 6,
      ),
      menuBarTheme: MenuBarThemeData(
        style: MenuStyle(backgroundColor: WidgetStatePropertyAll(surface)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: canvas,
        selectedItemColor: primary,
        unselectedItemColor: dark ? const Color(0xFFB4AABB) : muted,
        elevation: 0,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: primary,
        unselectedLabelColor: dark ? const Color(0xFFB4AABB) : muted,
        indicatorColor: primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: .3)
              : null,
        ),
      ),
    );
  }
}

/// Follows the app language setting while retaining system locale by default.
class SubnetLanguage extends InheritedWidget {
  const SubnetLanguage({
    super.key,
    required this.languageCode,
    this.translate,
    required super.child,
  });
  final String languageCode;
  final String Function(String)? translate;

  @override
  bool updateShouldNotify(SubnetLanguage oldWidget) =>
      languageCode != oldWidget.languageCode ||
      translate != oldWidget.translate;
}

String subnetText(BuildContext context, String chinese, String english) {
  final settings = context.dependOnInheritedWidgetOfExactType<SubnetLanguage>();
  final language = resolveAppLanguage(
    settings?.languageCode ?? '',
    Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en',
  );
  return appText(language, chinese, english, translate: settings?.translate);
}

double subnetTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

/// Settings labels stay beside controls on wide windows and stack at large type.
class SubnetSettingRow extends StatelessWidget {
  const SubnetSettingRow({
    super.key,
    required this.title,
    required this.description,
    required this.control,
  });
  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final label = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 14),
          ),
        ],
      );
      final wide =
          box.maxWidth > 720 * MediaQuery.textScalerOf(context).scale(1);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: wide
            ? Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 32),
                  SizedBox(width: 330, child: control),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [label, const SizedBox(height: 16), control],
              ),
      );
    },
  );
}

class SubnetBrand extends StatelessWidget {
  const SubnetBrand({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SubnetDesk',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/subnetdesk-mark.png',
          width: compact ? 28 : 36,
          height: compact ? 28 : 36,
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFDDD7EE)
              : null,
          colorBlendMode: BlendMode.srcIn,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'SubnetDesk',
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 21 : 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -.9,
            ),
          ),
        ),
      ],
    ),
  );
}

class SubnetEmpty extends StatelessWidget {
  const SubnetEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: Theme.of(context).hintColor),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).hintColor, height: 1.6),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
