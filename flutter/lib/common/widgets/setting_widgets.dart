import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

Widget customImageQualityWidget({
  required double initQuality,
  required double initFps,
  required Function(double)? setQuality,
  required Function(double)? setFps,
  required bool showFps,
  required bool showMoreQuality,
}) {
  var quality = initQuality.clamp(
    kMinQuality,
    showMoreQuality ? kMaxMoreQuality : kMaxQuality,
  );
  var fps = initFps.clamp(kMinFps, kMaxFps);
  var moreQuality = quality > kMaxQuality;
  final qualityDebouncer = Debouncer<double>(
    const Duration(seconds: 1),
    onChanged: setQuality,
    initialValue: quality,
  );
  final fpsDebouncer = Debouncer<double>(
    const Duration(seconds: 1),
    onChanged: setFps,
    initialValue: fps,
  );

  return StatefulBuilder(
    builder: (context, setState) => Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Slider(
                value: quality,
                min: kMinQuality,
                max: moreQuality ? kMaxMoreQuality : kMaxQuality,
                divisions: moreQuality
                    ? ((kMaxMoreQuality - kMinQuality) / 10).round()
                    : ((kMaxQuality - kMinQuality) / 5).round(),
                onChanged: setQuality == null
                    ? null
                    : (value) {
                        setState(() => quality = value);
                        qualityDebouncer.value = value;
                      },
              ),
            ),
            Expanded(
              child: Text('${quality.round()}%'),
            ),
            Expanded(
              flex: isMobile ? 2 : 1,
              child: Text(translate('Bitrate')),
            ),
            if (showMoreQuality && !isMobile)
              Expanded(
                child: Row(
                  children: [
                    Checkbox(
                      value: moreQuality,
                      onChanged: setQuality == null
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                moreQuality = value;
                                if (!value && quality > kMaxQuality) {
                                  quality = kMaxQuality;
                                }
                              });
                              qualityDebouncer.value = quality;
                            },
                    ),
                    Expanded(child: Text(translate('More'))),
                  ],
                ),
              ),
          ],
        ),
        if (showMoreQuality && isMobile)
          Row(
            children: [
              const Spacer(),
              Checkbox(
                value: moreQuality,
                onChanged: setQuality == null
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          moreQuality = value;
                          if (!value && quality > kMaxQuality) {
                            quality = kMaxQuality;
                          }
                        });
                        qualityDebouncer.value = quality;
                      },
              ),
              Expanded(child: Text(translate('More'))),
            ],
          ),
        if (showFps)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Slider(
                  value: fps,
                  min: kMinFps,
                  max: kMaxFps,
                  divisions: ((kMaxFps - kMinFps) / 5).round(),
                  onChanged: setFps == null
                      ? null
                      : (value) {
                          setState(() => fps = value);
                          fpsDebouncer.value = value;
                        },
                ),
              ),
              Expanded(child: Text('${fps.round()}')),
              Expanded(flex: 2, child: Text(translate('FPS'))),
            ],
          ),
      ],
    ),
  );
}

Widget customImageQualitySetting() {
  const qualityKey = 'custom_image_quality';
  const fpsKey = 'custom-fps';
  final initialQuality =
      double.tryParse(bind.mainGetUserDefaultOption(key: qualityKey)) ??
          kDefaultQuality;
  final initialFps =
      double.tryParse(bind.mainGetUserDefaultOption(key: fpsKey)) ??
          kDefaultFps;
  return customImageQualityWidget(
    initQuality: initialQuality,
    initFps: initialFps,
    setQuality: isOptionFixed(qualityKey)
        ? null
        : (value) => bind.mainSetUserDefaultOption(
              key: qualityKey,
              value: value.toString(),
            ),
    setFps: isOptionFixed(fpsKey)
        ? null
        : (value) => bind.mainSetUserDefaultOption(
              key: fpsKey,
              value: value.toString(),
            ),
    showFps: true,
    showMoreQuality: true,
  );
}

List<(String, String)> otherDefaultSettings() => [
      ('View Mode', kOptionViewOnly),
      if (isDesktop || isWebDesktop)
        ('show_monitors_tip', kKeyShowMonitorsToolbar),
      if (isDesktop || isWebDesktop)
        ('Collapse toolbar', kOptionCollapseToolbar),
      ('Show remote cursor', kOptionShowRemoteCursor),
      ('Follow remote cursor', kOptionFollowRemoteCursor),
      ('Follow remote window focus', kOptionFollowRemoteWindow),
      if (isDesktop || isWebDesktop) ('Zoom cursor', kOptionZoomCursor),
      ('Show quality monitor', kOptionShowQualityMonitor),
      ('Mute', kOptionDisableAudio),
      if (isDesktop) ('Enable file copy and paste', kOptionEnableFileCopyPaste),
      ('Disable clipboard', kOptionDisableClipboard),
      ('Lock after session end', kOptionLockAfterSessionEnd),
      ('Privacy mode', kOptionPrivacyMode),
      ('True color (4:4:4)', kOptionI444),
      ('Reverse mouse wheel', kKeyReverseMouseWheel),
      ('swap-left-right-mouse', kOptionSwapLeftRightMouse),
      if (isDesktop)
        (
          'Show displays as individual windows',
          kKeyShowDisplaysAsIndividualWindows,
        ),
      if (isDesktop)
        (
          'Use all my displays for the remote session',
          kKeyUseAllMyDisplaysForTheRemoteSession,
        ),
      ('Keep terminal sessions on disconnect', kOptionTerminalPersistent),
    ];

class TrackpadSpeedWidget extends StatefulWidget {
  final SimpleWrapper<int> value;
  final Function(int)? onDebouncer;

  const TrackpadSpeedWidget({
    super.key,
    required this.value,
    this.onDebouncer,
  });

  @override
  State<TrackpadSpeedWidget> createState() => _TrackpadSpeedWidgetState();
}

class _TrackpadSpeedWidgetState extends State<TrackpadSpeedWidget> {
  final _controller = TextEditingController();
  late final Debouncer<int> _debouncer;

  int get value => widget.value.value;

  @override
  void initState() {
    super.initState();
    _controller.text = value.toString();
    _debouncer = Debouncer<int>(
      const Duration(seconds: 1),
      onChanged: widget.onDebouncer,
      initialValue: value,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void updateValue(int newValue) {
    setState(() {
      widget.value.value = newValue.clamp(
        kMinTrackpadSpeed,
        kMaxTrackpadSpeed,
      );
      _controller.text = value.toString();
    });
    if (widget.onDebouncer != null) {
      _debouncer.value = value;
    }
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 3,
            child: Slider(
              value: value.toDouble(),
              min: kMinTrackpadSpeed.toDouble(),
              max: kMaxTrackpadSpeed.toDouble(),
              divisions: ((kMaxTrackpadSpeed - kMinTrackpadSpeed) / 10).round(),
              onChanged: (value) => updateValue(value.round()),
            ),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onSubmitted: (text) {
                final value = int.tryParse(text);
                if (value != null) updateValue(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('%'),
        ],
      );
}
