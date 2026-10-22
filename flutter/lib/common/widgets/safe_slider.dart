import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uses the Material slider everywhere except Windows.
///
/// Flutter's Windows accessibility bridge can crash when a Material [Slider]
/// is placed in a pushed route. The slider's value-indicator [OverlayPortal]
/// may serialize an orphan semantics node; a concurrent UI Automation hit test
/// then dereferences its missing platform delegate. This implementation avoids
/// the overlay portal on Windows while retaining pointer, keyboard, and screen
/// reader controls.
class SafeSlider extends StatelessWidget {
  const SafeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.semanticFormatterCallback,
    this.semanticLabel,
    this.thumbText,
  }) : assert(min <= max),
       assert(value >= min && value <= max),
       assert(divisions == null || divisions > 0);

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final String? semanticLabel;

  /// Optional text painted inside a rectangular thumb on Windows.
  final String? thumbText;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return _WindowsSafeSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
        semanticFormatterCallback: semanticFormatterCallback,
        semanticLabel: semanticLabel,
        thumbText: thumbText,
      );
    }
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      semanticFormatterCallback: semanticFormatterCallback,
    );
    return semanticLabel == null
        ? slider
        : Semantics(label: semanticLabel, child: slider);
  }
}

class _WindowsSafeSlider extends StatefulWidget {
  const _WindowsSafeSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.semanticFormatterCallback,
    required this.semanticLabel,
    required this.thumbText,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final String? semanticLabel;
  final String? thumbText;

  @override
  State<_WindowsSafeSlider> createState() => _WindowsSafeSliderState();
}

class _WindowsSafeSliderState extends State<_WindowsSafeSlider> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

  bool get _enabled => widget.onChanged != null && widget.max > widget.min;
  double get _horizontalInset => widget.thumbText == null ? 14 : 32;

  double get _step => widget.divisions == null
      ? (widget.max - widget.min) / 20
      : (widget.max - widget.min) / widget.divisions!;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  double _normalized(double value) {
    if (widget.max == widget.min) return 0;
    return ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
  }

  double _valueForNormalized(double normalized) {
    var value =
        widget.min + normalized.clamp(0.0, 1.0) * (widget.max - widget.min);
    if (widget.divisions != null) {
      value = widget.min + ((value - widget.min) / _step).round() * _step;
    }
    return value.clamp(widget.min, widget.max);
  }

  double _adjustedValue(double delta) =>
      (widget.value + delta).clamp(widget.min, widget.max);

  String _format(double value) {
    final formatter = widget.semanticFormatterCallback;
    if (formatter != null) return formatter(value);
    return '${(_normalized(value) * 100).round()}%';
  }

  void _setValue(double value) {
    if (!_enabled) return;
    final adjusted = _valueForNormalized(_normalized(value));
    if (adjusted != widget.value) widget.onChanged!(adjusted);
  }

  void _nudge(double direction) {
    _setValue(_adjustedValue(direction * _step));
  }

  void _setValueFromPointer(
    BuildContext context,
    BoxConstraints constraints,
    Offset localPosition,
  ) {
    if (!_enabled) return;
    final usableWidth = (constraints.maxWidth - _horizontalInset * 2).clamp(
      1.0,
      double.infinity,
    );
    var normalized = ((localPosition.dx - _horizontalInset) / usableWidth)
        .clamp(0.0, 1.0);
    if (Directionality.of(context) == TextDirection.rtl) {
      normalized = 1 - normalized;
    }
    _focusNode.requestFocus();
    _setValue(_valueForNormalized(normalized));
  }

  KeyEventResult _handleKeyEvent(
    BuildContext context,
    FocusNode node,
    KeyEvent event,
  ) {
    if (!_enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (key == LogicalKeyboardKey.arrowUp ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight)) {
      _nudge(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
      _nudge(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _setValue(widget.min);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _setValue(widget.max);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sliderTheme = SliderTheme.of(context);
    final activeColor = _enabled
        ? sliderTheme.activeTrackColor ?? theme.colorScheme.primary
        : sliderTheme.disabledActiveTrackColor ?? theme.disabledColor;
    final inactiveColor = _enabled
        ? sliderTheme.inactiveTrackColor ?? activeColor.withValues(alpha: 0.24)
        : sliderTheme.disabledInactiveTrackColor ??
              theme.disabledColor.withValues(alpha: 0.24);
    final thumbColor = _enabled
        ? sliderTheme.thumbColor ?? activeColor
        : sliderTheme.disabledThumbColor ?? theme.disabledColor;
    final increasedValue = _format(_adjustedValue(_step));
    final decreasedValue = _format(_adjustedValue(-_step));

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: _format(widget.value),
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      enabled: _enabled,
      focusable: _enabled,
      focused: _focusNode.hasFocus,
      onIncrease: _enabled ? () => _nudge(1) : null,
      onDecrease: _enabled ? () => _nudge(-1) : null,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) => _handleKeyEvent(context, node, event),
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _enabled
                    ? (details) => _setValueFromPointer(
                        context,
                        constraints,
                        details.localPosition,
                      )
                    : null,
                onHorizontalDragStart: _enabled
                    ? (details) => _setValueFromPointer(
                        context,
                        constraints,
                        details.localPosition,
                      )
                    : null,
                onHorizontalDragUpdate: _enabled
                    ? (details) => _setValueFromPointer(
                        context,
                        constraints,
                        details.localPosition,
                      )
                    : null,
                child: SizedBox(
                  width: constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 144,
                  height: 48,
                  child: CustomPaint(
                    painter: _SafeSliderPainter(
                      normalizedValue: _normalized(widget.value),
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      thumbColor: thumbColor,
                      trackHeight: sliderTheme.trackHeight ?? 4,
                      horizontalInset: _horizontalInset,
                      textDirection: Directionality.of(context),
                      emphasized: _hovered || _focusNode.hasFocus,
                      thumbText: widget.thumbText,
                      textStyle: theme.textTheme.labelSmall?.copyWith(
                        color:
                            sliderTheme.valueIndicatorTextStyle?.color ??
                            theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafeSliderPainter extends CustomPainter {
  const _SafeSliderPainter({
    required this.normalizedValue,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.trackHeight,
    required this.horizontalInset,
    required this.textDirection,
    required this.emphasized,
    required this.thumbText,
    required this.textStyle,
  });

  final double normalizedValue;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double trackHeight;
  final double horizontalInset;
  final TextDirection textDirection;
  final bool emphasized;
  final String? thumbText;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final left = horizontalInset;
    final right = (size.width - horizontalInset).clamp(left, double.infinity);
    final logicalValue = textDirection == TextDirection.rtl
        ? 1 - normalizedValue
        : normalizedValue;
    final thumbX = left + (right - left) * logicalValue;
    final radius = Radius.circular(trackHeight / 2);
    final track = Rect.fromLTRB(
      left,
      centerY - trackHeight / 2,
      right,
      centerY + trackHeight / 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = inactiveColor,
    );
    final activeTrack = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(thumbX, track.top, right, track.bottom)
        : Rect.fromLTRB(left, track.top, thumbX, track.bottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeTrack, radius),
      Paint()..color = activeColor,
    );

    if (emphasized) {
      canvas.drawCircle(
        Offset(thumbX, centerY),
        16,
        Paint()..color = thumbColor.withValues(alpha: 0.12),
      );
    }
    if (thumbText == null) {
      canvas.drawCircle(
        Offset(thumbX, centerY),
        10,
        Paint()..color = thumbColor,
      );
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(text: thumbText, style: textStyle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final thumbWidth = (textPainter.width + 12).clamp(40.0, 64.0);
    final thumbRect = Rect.fromCenter(
      center: Offset(thumbX, centerY),
      width: thumbWidth,
      height: 24,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumbRect, const Radius.circular(4)),
      Paint()..color = thumbColor,
    );
    textPainter.paint(
      canvas,
      Offset(thumbX - textPainter.width / 2, centerY - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SafeSliderPainter oldDelegate) =>
      normalizedValue != oldDelegate.normalizedValue ||
      activeColor != oldDelegate.activeColor ||
      inactiveColor != oldDelegate.inactiveColor ||
      thumbColor != oldDelegate.thumbColor ||
      trackHeight != oldDelegate.trackHeight ||
      horizontalInset != oldDelegate.horizontalInset ||
      textDirection != oldDelegate.textDirection ||
      emphasized != oldDelegate.emphasized ||
      thumbText != oldDelegate.thumbText ||
      textStyle != oldDelegate.textStyle;
}
