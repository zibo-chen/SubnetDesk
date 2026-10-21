import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:uuid/uuid.dart';

class _Session extends Fake implements FFI {
  @override
  final SessionID sessionId = const Uuid().v4obj();
}

class _DialogModel extends FfiModel {
  _DialogModel(FFI ffi) : super(WeakReference(ffi));

  String? dialogType;

  @override
  void handleMsgBox(
    Map<String, dynamic> evt,
    SessionID sessionId,
    String peerId,
  ) {
    dialogType = evt['type'];
  }
}

void main() {
  for (final type in ['lan-login-required', 'error']) {
    test('$type prevents a late Connecting overlay', () async {
      final session = _Session();
      final model = _DialogModel(session);
      final onEvent = model.startEventListener(session.sessionId, 'test-peer');
      expect(model.hasConnectionResponse, isFalse);

      await onEvent({'name': 'msgbox', 'type': type});
      expect(model.hasConnectionResponse, isTrue);
      expect(model.dialogType, type);

      model.clear();
      expect(model.hasConnectionResponse, isFalse);
      model.dispose();
    });
  }
}
