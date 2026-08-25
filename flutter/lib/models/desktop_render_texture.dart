import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gpu_texture_renderer/flutter_gpu_texture_renderer.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:get/get.dart';

import '../../common.dart';
import './platform_model.dart';

import 'package:texture_rgba_renderer/texture_rgba_renderer.dart'
    if (dart.library.html) 'package:flutter_hbb/web/texture_rgba_renderer.dart';

class _PixelbufferTexture {
  int _textureKey = -1;
  int _display = 0;
  SessionID? _sessionId;
  bool _destroyRequested = false;
  int _ptr = 0;
  int? _id;
  Future<void>? _createFuture;
  Future<void>? _destroyFuture;

  final textureRenderer = TextureRgbaRenderer();

  int get display => _display;

  void create(int d, SessionID sessionId, FFI ffi) {
    _display = d;
    _textureKey = bind.getNextTextureKey();
    _sessionId = sessionId;
    _createFuture = _create(ffi, _textureKey);
  }

  Future<void> _create(FFI ffi, int textureKey) async {
    try {
      final id = await textureRenderer.createTexture(textureKey);
      _id = id;
      if (id == -1 || _destroyRequested) return;

      ffi.textureModel.setRgbaTextureId(display: display, id: id);
      final ptr = await textureRenderer.getTexturePtr(textureKey);
      if (_destroyRequested || ptr == 0) return;

      final sessionId = _sessionId;
      if (sessionId == null) return;
      platformFFI.registerPixelbufferTexture(sessionId, display, ptr);
      _ptr = ptr;
      debugPrint(
        "create pixelbuffer texture: peerId: ${ffi.id} display:$_display, textureId:$id, texturePtr:$ptr",
      );
    } catch (e, stack) {
      debugPrint('Failed to create pixelbuffer texture: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> destroy(FFI ffi) {
    return _destroyFuture ??= _destroy(ffi);
  }

  Future<void> _destroy(FFI ffi) async {
    _destroyRequested = true;
    await _createFuture;

    final textureKey = _textureKey;
    final sessionId = _sessionId;
    if (textureKey == -1 || sessionId == null) return;

    if (_ptr != 0) {
      platformFFI.unregisterPixelbufferTexture(sessionId, display, _ptr);
      _ptr = 0;
    }
    try {
      await textureRenderer.closeTexture(textureKey);
    } catch (e, stack) {
      debugPrint('Failed to destroy pixelbuffer texture: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      _textureKey = -1;
      _sessionId = null;
      debugPrint(
        "destroy pixelbuffer texture: peerId: ${ffi.id} display:$_display, textureId:$_id",
      );
    }
  }
}

class _GpuTexture {
  int _textureId = -1;
  SessionID? _sessionId;
  final support = bind.mainHasGpuTextureRender();
  bool _destroyRequested = false;
  int _display = 0;
  int? _id;
  int? _output;
  Future<void>? _createFuture;
  Future<void>? _destroyFuture;

  int get display => _display;

  final gpuTextureRenderer = FlutterGpuTextureRenderer();

  _GpuTexture();

  void create(int d, SessionID sessionId, FFI ffi) {
    if (support) {
      _sessionId = sessionId;
      _display = d;
      _createFuture = _create(ffi);
    }
  }

  Future<void> _create(FFI ffi) async {
    try {
      final id = await gpuTextureRenderer.registerTexture();
      _id = id;
      if (id == null) return;
      _textureId = id;
      if (_destroyRequested) return;

      ffi.textureModel.setGpuTextureId(display: display, id: id);
      final output = await gpuTextureRenderer.output(id);
      _output = output;
      if (_destroyRequested || output == null) return;

      final sessionId = _sessionId;
      if (sessionId == null) return;
      platformFFI.registerGpuTexture(sessionId, display, output);
      debugPrint(
        "create gpu texture: peerId: ${ffi.id} display:$_display, textureId:$id, output:$output",
      );
    } catch (e, stack) {
      debugPrint('Failed to create gpu texture: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> destroy(FFI ffi) {
    return _destroyFuture ??= _destroy(ffi);
  }

  Future<void> _destroy(FFI ffi) async {
    _destroyRequested = true;
    await _createFuture;

    final sessionId = _sessionId;
    if (!support || sessionId == null || _textureId == -1) return;

    final output = _output;
    if (output != null) {
      platformFFI.unregisterGpuTexture(sessionId, display, output);
      _output = null;
    }
    try {
      await gpuTextureRenderer.unregisterTexture(_textureId);
    } catch (e, stack) {
      debugPrint('Failed to destroy gpu texture: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      _textureId = -1;
      _sessionId = null;
      debugPrint(
        "destroy gpu texture: peerId: ${ffi.id} display:$_display, textureId:$_id, output:$output",
      );
    }
  }
}

class _Control {
  RxInt textureID = (-1).obs;

  int _rgbaTextureId = -1;
  int get rgbaTextureId => _rgbaTextureId;
  int _gpuTextureId = -1;
  int get gpuTextureId => _gpuTextureId;
  bool _isGpuTexture = false;
  bool get isGpuTexture => _isGpuTexture;

  setTextureType({bool gpuTexture = false}) {
    _isGpuTexture = gpuTexture;
    textureID.value = _isGpuTexture ? gpuTextureId : rgbaTextureId;
  }

  setRgbaTextureId(int id) {
    _rgbaTextureId = id;
    textureID.value = _isGpuTexture ? gpuTextureId : rgbaTextureId;
  }

  setGpuTextureId(int id) {
    _gpuTextureId = id;
    textureID.value = _isGpuTexture ? gpuTextureId : rgbaTextureId;
  }
}

class TextureModel {
  final WeakReference<FFI> parent;
  final Map<int, _Control> _control = {};
  final Map<int, _PixelbufferTexture> _pixelbufferRenderTextures = {};
  final Map<int, _GpuTexture> _gpuRenderTextures = {};
  bool _destroying = false;
  Future<void>? _destroyFuture;

  TextureModel(this.parent);

  setTextureType({required int display, required bool gpuTexture}) {
    if (_destroying) return;
    debugPrint("setTextureType: display=$display, isGpuTexture=$gpuTexture");
    ensureControl(display);
    _control[display]?.setTextureType(gpuTexture: gpuTexture);
    // For versions that do not support multiple displays, the display parameter is always 0, need set type of current display
    final ffi = parent.target;
    if (ffi == null) return;
    if (!ffi.ffiModel.pi.isSupportMultiDisplay) {
      final currentDisplay = CurrentDisplayState.find(ffi.id).value;
      if (currentDisplay != display) {
        debugPrint(
            "setTextureType: currentDisplay=$currentDisplay, isGpuTexture=$gpuTexture");
        ensureControl(currentDisplay);
        _control[currentDisplay]?.setTextureType(gpuTexture: gpuTexture);
      }
    }
  }

  setRgbaTextureId({required int display, required int id}) {
    ensureControl(display);
    _control[display]?.setRgbaTextureId(id);
  }

  setGpuTextureId({required int display, required int id}) {
    ensureControl(display);
    _control[display]?.setGpuTextureId(id);
  }

  RxInt getTextureId(int display) {
    ensureControl(display);
    return _control[display]!.textureID;
  }

  updateCurrentDisplay(int curDisplay) {
    if (isWeb || _destroying) return;
    final ffi = parent.target;
    if (ffi == null) return;
    tryCreateTexture(int idx) {
      if (!_pixelbufferRenderTextures.containsKey(idx)) {
        final renderTexture = _PixelbufferTexture();
        _pixelbufferRenderTextures[idx] = renderTexture;
        renderTexture.create(idx, ffi.sessionId, ffi);
      }
      if (!_gpuRenderTextures.containsKey(idx)) {
        final renderTexture = _GpuTexture();
        _gpuRenderTextures[idx] = renderTexture;
        renderTexture.create(idx, ffi.sessionId, ffi);
      }
    }

    tryRemoveTexture(int idx) {
      _control.remove(idx);
      if (_pixelbufferRenderTextures.containsKey(idx)) {
        unawaited(_pixelbufferRenderTextures[idx]!.destroy(ffi));
        _pixelbufferRenderTextures.remove(idx);
      }
      if (_gpuRenderTextures.containsKey(idx)) {
        unawaited(_gpuRenderTextures[idx]!.destroy(ffi));
        _gpuRenderTextures.remove(idx);
      }
    }

    if (curDisplay == kAllDisplayValue) {
      final displays = ffi.ffiModel.pi.getCurDisplays();
      for (var i = 0; i < displays.length; i++) {
        tryCreateTexture(i);
      }
    } else {
      tryCreateTexture(curDisplay);
      for (var i = 0; i < ffi.ffiModel.pi.displays.length; i++) {
        if (i != curDisplay) {
          tryRemoveTexture(i);
        }
      }
    }
  }

  Future<void> _destroyAll() async {
    _destroying = true;
    final ffi = parent.target;
    if (ffi == null) return;
    final pixelbufferTextures = _pixelbufferRenderTextures.values.toList();
    final gpuTextures = _gpuRenderTextures.values.toList();
    for (final texture in pixelbufferTextures) {
      await texture.destroy(ffi);
    }
    for (final texture in gpuTextures) {
      await texture.destroy(ffi);
    }
    _pixelbufferRenderTextures.clear();
    _gpuRenderTextures.clear();
    _control.clear();
  }

  Future<void> onRemotePageDispose() {
    return _destroyFuture ??= _destroyAll();
  }

  Future<void> onViewCameraPageDispose() {
    return _destroyFuture ??= _destroyAll();
  }

  ensureControl(int display) {
    var ctl = _control[display];
    if (ctl == null) {
      ctl = _Control();
      _control[display] = ctl;
    }
  }
}
