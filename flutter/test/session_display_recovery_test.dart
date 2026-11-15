import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _Canvas extends Fake implements CanvasModel {
  @override
  Future<void> tryUpdateScrollStyle(Duration duration, String? style) async {}
}

class _Session extends Fake implements FFI {
  @override
  final SessionID sessionId = const Uuid().v4obj();
  @override
  final connType = ConnType.defaultConn;
  @override
  final canvasModel = _Canvas();
  @override
  final dialogManager = OverlayDialogManager();
}

class _RecoveryModel extends FfiModel {
  _RecoveryModel(FFI ffi) : super(WeakReference(ffi));

  int displayUpdates = 0;
  int waitingDialogs = 0;

  @override
  void showDisplayRecovery(
    OverlayDialogManager dialogManager,
    SessionID sessionId,
  ) {
    waitingDialogs++;
  }

  @override
  Future<void> updateCurDisplay(
    SessionID sessionId, {
    updateCursorPos = false,
  }) async {
    displayUpdates++;
  }
}

void main() {
  test(
    'Windows display loss waits and the same connection accepts recovery',
    () async {
      final session = _Session();
      final model = _RecoveryModel(session);
      final sessionId = const Uuid().v4obj();
      model.pi.platform = 'Windows';
      model.pi.platformAdditions['user_session_display_recovery'] = true;
      model.pi.isSet.value = true;
      model.waitForFirstImage.value = false;

      await model.handleSyncPeerInfo({'displays': '[]'}, sessionId, 'peer');
      expect(model.pi.isSet.value, isTrue);
      expect(model.pi.displays, isEmpty);
      expect(model.waitForFirstImage.value, isTrue);
      expect(model.waitingDialogs, 1);

      await model.handleSyncPeerInfo(
        {'displays': '[{"x":0,"y":0,"width":1920,"height":1080}]'},
        sessionId,
        'peer',
      );
      expect(model.pi.isSet.value, isTrue);
      expect(model.pi.displays.single.width, 1920);
      expect(model.displayUpdates, 1);
      expect(model.waitingDialogs, 1);
      model.dispose();
    },
  );
}
