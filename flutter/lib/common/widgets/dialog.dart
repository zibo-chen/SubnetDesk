import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

void clientClose(SessionID sessionId, FFI ffi) async {
  if (allowAskForNoteAtEndOfConnection(ffi, true)) {
    if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) {
      return;
    }
    closeConnection();
  } else {
    msgBox(
      sessionId,
      'info',
      'Close',
      'Are you sure to close the connection?',
      '',
      ffi.dialogManager,
    );
  }
}

class DialogTextField extends StatelessWidget {
  final String title;
  final String? hintText;
  final bool obscureText;
  final String? errorText;
  final String? helperText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  static const kUsernameTitle = 'Username';
  static const kUsernameIcon = Icon(Icons.account_circle_outlined);
  static const kPasswordTitle = 'Password';
  static const kPasswordIcon = Icon(Icons.lock_outline);

  DialogTextField({
    Key? key,
    this.focusNode,
    this.obscureText = false,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    required this.title,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: title,
                  hintText: hintText,
                  prefixIcon: prefixIcon,
                  suffixIcon: suffixIcon,
                  helperText: helperText,
                  helperMaxLines: 8,
                ),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                obscureText: obscureText,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                maxLength: maxLength,
              ),
              if (errorText != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.left,
                  ).paddingOnly(top: 8, left: 12),
                ),
            ],
          ).workaroundFreezeLinuxMint(),
        ),
      ],
    ).paddingSymmetric(vertical: 4.0);
  }
}

class PasswordWidget extends StatefulWidget {
  PasswordWidget({
    Key? key,
    required this.controller,
    this.autoFocus = true,
    this.reRequestFocus = false,
    this.hintText,
    this.errorText,
    this.title,
    this.maxLength,
  }) : super(key: key);

  final TextEditingController controller;
  final bool autoFocus;
  final bool reRequestFocus;
  final String? hintText;
  final String? errorText;
  final String? title;
  final int? maxLength;

  @override
  State<PasswordWidget> createState() => _PasswordWidgetState();
}

class _PasswordWidgetState extends State<PasswordWidget> {
  bool _passwordVisible = false;
  final _focusNode = FocusNode();
  Timer? _timer;
  Timer? _timerReRequestFocus;

  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) {
      _timer = Timer(
        Duration(milliseconds: 50),
        () => _focusNode.requestFocus(),
      );
    }
    // software secure keyboard will take the focus since flutter 3.13
    // request focus again when android account password obtain focus
    if (isAndroid && widget.reRequestFocus) {
      _focusNode.addListener(() {
        if (_focusNode.hasFocus) {
          _timerReRequestFocus?.cancel();
          _timerReRequestFocus = Timer(
            Duration(milliseconds: 100),
            () => _focusNode.requestFocus(),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerReRequestFocus?.cancel();
    _focusNode.unfocus();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogTextField(
      title: translate(widget.title ?? DialogTextField.kPasswordTitle),
      hintText: translate(widget.hintText ?? 'Enter your password'),
      controller: widget.controller,
      prefixIcon: DialogTextField.kPasswordIcon,
      suffixIcon: IconButton(
        icon: Icon(
          // Based on passwordVisible state choose the icon
          _passwordVisible ? Icons.visibility : Icons.visibility_off,
          color: MyTheme.lightTheme.primaryColor,
        ),
        onPressed: () {
          // Update the state i.e. toggle the state of passwordVisible variable
          setState(() {
            _passwordVisible = !_passwordVisible;
          });
        },
      ),
      obscureText: !_passwordVisible,
      errorText: widget.errorText,
      focusNode: _focusNode,
      maxLength: widget.maxLength,
    );
  }
}

void wrongPasswordDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  type,
  title,
  text,
) {
  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    cancel() {
      close();
      closeConnection();
    }

    submit() {
      enterUserLoginDialog(
        sessionId,
        dialogManager,
        'Enter the access username and password configured on the remote device.',
        false,
      );
    }

    return CustomAlertDialog(
      title: null,
      content: msgboxContent(type, title, text),
      onSubmit: submit,
      onCancel: cancel,
      actions: [
        dialogButton('Cancel', onPressed: cancel, isOutline: true),
        dialogButton('Retry', onPressed: submit),
      ],
    );
  });
}

void enterPasswordDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
) async {
  await _connectDialog(
    sessionId,
    dialogManager,
    passwordController: TextEditingController(),
  );
}

void enterUserLoginDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  String osAccountDescTip,
  bool _canRememberAccount,
) async {
  await _connectDialog(
    sessionId,
    dialogManager,
    osUsernameController: TextEditingController(),
    osPasswordController: TextEditingController(),
    osAccountDescTip: osAccountDescTip,
  );
}

void enterLanLoginDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  String description,
) async {
  await _connectDialog(
    sessionId,
    dialogManager,
    osUsernameController: TextEditingController(),
    osPasswordController: TextEditingController(),
    osAccountDescTip: description,
    lanAccess: true,
  );
}

void enterUserLoginAndPasswordDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  String osAccountDescTip,
  bool _canRememberAccount,
) async {
  await _connectDialog(
    sessionId,
    dialogManager,
    osUsernameController: TextEditingController(),
    osPasswordController: TextEditingController(),
    passwordController: TextEditingController(),
    osAccountDescTip: osAccountDescTip,
  );
}

_connectDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager, {
  TextEditingController? osUsernameController,
  TextEditingController? osPasswordController,
  TextEditingController? passwordController,
  String? osAccountDescTip,
  bool lanAccess = false,
}) async {
  final errUsername = ''.obs;
  final errPassword = ''.obs;
  if (osUsernameController != null) {
    osUsernameController.addListener(() {
      if (errUsername.value.isNotEmpty) {
        errUsername.value = '';
      }
    });
  }

  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    cancel() {
      close();
      closeConnection();
    }

    submit() {
      if (osUsernameController != null) {
        if (osUsernameController.text.trim().isEmpty) {
          errUsername.value = translate('Empty Username');
          setState(() {});
          return;
        }
      }
      final osUsername = osUsernameController?.text.trim() ?? '';
      final osPassword = osPasswordController?.text ?? '';
      final password = passwordController?.text.trim() ?? '';
      if (lanAccess) {
        if (osPassword.isEmpty) {
          errPassword.value = translate('Empty Password');
          setState(() {});
          return;
        }
        final error = bind.sessionLoginLan(
          sessionId: sessionId,
          username: osUsername,
          password: osPassword,
        );
        osPasswordController?.clear();
        if (error.isNotEmpty) {
          errPassword.value = error;
          setState(() {});
          return;
        }
      } else {
        if (passwordController != null && password.isEmpty) return;
        gFFI.login(osUsername, osPassword.trim(), sessionId, password);
      }
      close();
      dialogManager.showLoading(
        translate('Logging in...'),
        onCancel: closeConnection,
      );
    }

    descWidget(String text) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 3,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16),
            ),
          ),
          Container(height: 8),
        ],
      );
    }

    osAccountWidget() {
      if (osUsernameController == null || osPasswordController == null) {
        return Offstage();
      }
      return Column(
        children: [
          if (osAccountDescTip != null) descWidget(translate(osAccountDescTip)),
          DialogTextField(
            title: translate(DialogTextField.kUsernameTitle),
            controller: osUsernameController,
            prefixIcon: DialogTextField.kUsernameIcon,
            errorText: null,
          ),
          if (errUsername.value.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                errUsername.value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
                textAlign: TextAlign.left,
              ).paddingOnly(left: 12, bottom: 2),
            ),
          PasswordWidget(
            controller: osPasswordController,
            autoFocus: false,
            errorText: errPassword.isEmpty ? null : errPassword.value,
          ),
        ],
      );
    }

    passwdWidget() {
      if (passwordController == null) {
        return Offstage();
      }
      return Column(
        children: [
          descWidget(translate('verify_rustdesk_password_tip')),
          PasswordWidget(
            controller: passwordController,
            autoFocus: osUsernameController == null,
          ),
        ],
      );
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.password_rounded, color: MyTheme.accent),
          Text(
            translate(
              lanAccess ? 'LAN access credentials' : 'Password Required',
            ),
          ).paddingOnly(left: 10),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          osAccountWidget(),
          osUsernameController == null || passwordController == null
              ? Offstage()
              : Container(height: 12),
          passwdWidget(),
        ],
      ),
      actions: [
        dialogButton(
          'Cancel',
          icon: Icon(Icons.close_rounded),
          onPressed: cancel,
          isOutline: true,
        ),
        dialogButton('OK', icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: cancel,
    );
  });
}

void showWaitUacDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
  String type,
) {
  dialogManager.dismissAll();
  dialogManager.show(
    tag: '$sessionId-wait-uac',
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: msgboxContent(type, 'Wait', 'wait_accept_uac_tip'),
      actions: [
        dialogButton('OK', icon: Icon(Icons.done_rounded), onPressed: close),
      ],
    ),
  );
}

// Another username && password dialog?
void showRequestElevationDialog(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
) {
  RxString groupValue = ''.obs;
  RxString errUser = ''.obs;
  RxString errPwd = ''.obs;
  TextEditingController userController = TextEditingController();
  TextEditingController pwdController = TextEditingController();

  void onRadioChanged(String? value) {
    if (value != null) {
      groupValue.value = value;
    }
  }

  // TODO get from theme
  final double fontSizeNote = 13.00;

  Widget OptionRequestPermissions = Obx(
    () => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Radio(
          visualDensity: VisualDensity(horizontal: -4, vertical: -4),
          value: '',
          groupValue: groupValue.value,
          onChanged: onRadioChanged,
        ).marginOnly(right: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                hoverColor: Colors.transparent,
                onTap: () => groupValue.value = '',
                child: Text(
                  translate('Ask the remote user for authentication'),
                ),
              ).marginOnly(bottom: 10),
              Text(
                translate('Choose this if the remote account is administrator'),
                style: TextStyle(fontSize: fontSizeNote),
              ),
            ],
          ).marginOnly(top: 3),
        ),
      ],
    ),
  );

  Widget OptionCredentials = Obx(
    () => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Radio(
          visualDensity: VisualDensity(horizontal: -4, vertical: -4),
          value: 'logon',
          groupValue: groupValue.value,
          onChanged: onRadioChanged,
        ).marginOnly(right: 10),
        Expanded(
          child: InkWell(
            hoverColor: Colors.transparent,
            onTap: () => onRadioChanged('logon'),
            child: Text(
              translate('Transmit the username and password of administrator'),
            ),
          ).marginOnly(top: 4),
        ),
      ],
    ),
  );

  Widget UacNote = Container(
    padding: EdgeInsets.fromLTRB(10, 8, 8, 8),
    decoration: BoxDecoration(
      color: MyTheme.currentThemeMode() == ThemeMode.dark
          ? Color.fromARGB(135, 87, 87, 90)
          : Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 20).marginOnly(right: 10),
        Expanded(
          child: Text(
            translate('still_click_uac_tip'),
            style: TextStyle(
              fontSize: fontSizeNote,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );

  var content = Obx(
    () => Column(
      children: [
        OptionRequestPermissions.marginOnly(bottom: 15),
        OptionCredentials,
        Offstage(
          offstage: 'logon' != groupValue.value,
          child: Column(
            children: [
              UacNote.marginOnly(bottom: 10),
              DialogTextField(
                controller: userController,
                title: translate('Username'),
                hintText: translate('elevation_username_tip'),
                prefixIcon: DialogTextField.kUsernameIcon,
                errorText: errUser.isEmpty ? null : errUser.value,
              ),
              PasswordWidget(
                controller: pwdController,
                autoFocus: false,
                errorText: errPwd.isEmpty ? null : errPwd.value,
              ),
            ],
          ).marginOnly(left: stateGlobal.isPortrait.isFalse ? 35 : 0),
        ).marginOnly(top: 10),
      ],
    ),
  );

  dialogManager.dismissAll();
  dialogManager.show(tag: '$sessionId-request-elevation', (
    setState,
    close,
    context,
  ) {
    void submit() {
      if (groupValue.value == 'logon') {
        if (userController.text.isEmpty) {
          errUser.value = translate('Empty Username');
          return;
        }
        if (pwdController.text.isEmpty) {
          errPwd.value = translate('Empty Password');
          return;
        }
        bind.sessionElevateWithLogon(
          sessionId: sessionId,
          username: userController.text,
          password: pwdController.text,
        );
      } else {
        bind.sessionElevateDirect(sessionId: sessionId);
      }
      close();
      showWaitUacDialog(sessionId, dialogManager, "wait-uac");
    }

    return CustomAlertDialog(
      title: Text(translate('Request Elevation')),
      content: content,
      actions: [
        dialogButton(
          'Cancel',
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        ),
        dialogButton('OK', icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void showOnBlockDialog(
  SessionID sessionId,
  String type,
  String title,
  String text,
  OverlayDialogManager dialogManager,
) {
  if (dialogManager.existing('$sessionId-wait-uac') ||
      dialogManager.existing('$sessionId-request-elevation')) {
    return;
  }
  dialogManager.show(tag: '$sessionId-$type', (setState, close, context) {
    void submit() {
      close();
      showRequestElevationDialog(sessionId, dialogManager);
    }

    return CustomAlertDialog(
      title: null,
      content: msgboxContent(
        type,
        title,
        "${translate(text)}${type.contains('uac') ? '\n' : '\n\n'}${translate('request_elevation_tip')}",
      ),
      actions: [
        dialogButton('Wait', onPressed: close, isOutline: true),
        dialogButton('Request Elevation', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void showElevationError(
  SessionID sessionId,
  String type,
  String title,
  String text,
  OverlayDialogManager dialogManager,
) {
  dialogManager.show(tag: '$sessionId-$type', (setState, close, context) {
    void submit() {
      close();
      showRequestElevationDialog(sessionId, dialogManager);
    }

    return CustomAlertDialog(
      title: null,
      content: msgboxContent(type, title, text),
      actions: [
        dialogButton(
          'Cancel',
          onPressed: () {
            close();
          },
          isOutline: true,
        ),
        if (text != 'No permission') dialogButton('Retry', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void showRestartRemoteDevice(
  PeerInfo pi,
  String id,
  SessionID sessionId,
  OverlayDialogManager dialogManager,
) async {
  final res = await dialogManager.show<bool>(
    (setState, close, context) => CustomAlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
          Flexible(
            child: Text(
              translate("Restart remote device"),
            ).paddingOnly(left: 10),
          ),
        ],
      ),
      content: Text(
        "${translate('Are you sure you want to restart')} \n${pi.username}@${pi.hostname}($id) ?",
      ),
      actions: [
        dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        ),
        dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: () => close(true),
        ),
      ],
      onCancel: close,
      onSubmit: () => close(true),
    ),
  );
  if (res == true) bind.sessionRestartRemoteDevice(sessionId: sessionId);
}

showSetOSPassword(
  SessionID sessionId,
  bool login,
  OverlayDialogManager dialogManager,
  String? osPassword,
  Function()? closeCallback,
) async {
  final controller = TextEditingController();
  osPassword ??=
      await bind.sessionGetOption(sessionId: sessionId, arg: 'os-password') ??
          '';
  var autoLogin =
      await bind.sessionGetOption(sessionId: sessionId, arg: 'auto-login') !=
          '';
  controller.text = osPassword;
  dialogManager.show((setState, close, context) {
    closeWithCallback([dynamic]) {
      close();
      if (closeCallback != null) closeCallback();
    }

    submit() {
      var text = controller.text.trim();
      bind.sessionPeerOption(
        sessionId: sessionId,
        name: 'os-password',
        value: text,
      );
      bind.sessionPeerOption(
        sessionId: sessionId,
        name: 'auto-login',
        value: autoLogin ? 'Y' : '',
      );
      if (text != '' && login) {
        bind.sessionInputOsPassword(sessionId: sessionId, value: text);
      }
      closeWithCallback();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.password_rounded, color: MyTheme.accent),
          Text(translate('OS Password')).paddingOnly(left: 10),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PasswordWidget(controller: controller),
          CheckboxListTile(
            contentPadding: const EdgeInsets.all(0),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(translate('Auto Login')),
            value: autoLogin,
            onChanged: (v) {
              if (v == null) return;
              setState(() => autoLogin = v);
            },
          ),
        ],
      ),
      actions: [
        dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: closeWithCallback,
          isOutline: true,
        ),
        dialogButton("OK", icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: closeWithCallback,
    );
  });
}

showSetOSAccount(
  SessionID sessionId,
  OverlayDialogManager dialogManager,
) async {
  final usernameController = TextEditingController();
  final passwdController = TextEditingController();
  var username =
      await bind.sessionGetOption(sessionId: sessionId, arg: 'os-username') ??
          '';
  var password =
      await bind.sessionGetOption(sessionId: sessionId, arg: 'os-password') ??
          '';
  usernameController.text = username;
  passwdController.text = password;
  dialogManager.show((setState, close, context) {
    submit() {
      final username = usernameController.text.trim();
      final password = usernameController.text.trim();
      bind.sessionPeerOption(
        sessionId: sessionId,
        name: 'os-username',
        value: username,
      );
      bind.sessionPeerOption(
        sessionId: sessionId,
        name: 'os-password',
        value: password,
      );
      close();
    }

    descWidget(String text) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 3,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16),
            ),
          ),
          Container(height: 8),
        ],
      );
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.password_rounded, color: MyTheme.accent),
          Text(translate('OS Account')).paddingOnly(left: 10),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          descWidget(translate("os_account_desk_tip")),
          DialogTextField(
            title: translate(DialogTextField.kUsernameTitle),
            controller: usernameController,
            prefixIcon: DialogTextField.kUsernameIcon,
            errorText: null,
          ),
          PasswordWidget(controller: passwdController),
        ],
      ),
      actions: [
        dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        ),
        dialogButton("OK", icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

bool allowAskForNoteAtEndOfConnection(FFI? ffi, bool closedByControlling) {
  return false;
}

Future<bool> desktopTryShowTabAuditDialogCloseCancelled({
  required String id,
  required DesktopTabController tabController,
}) async {
  return false;
}

Future<bool> showConnEndAuditDialogCloseCanceled({
  required FFI ffi,
  String? type,
  String? title,
  String? text,
}) async {
  return false;
}

customImageQualityDialog(SessionID sessionId, String id, FFI ffi) async {
  double initQuality = kDefaultQuality;
  double initFps = kDefaultFps;
  bool qualitySet = false;
  bool fpsSet = false;

  bool? direct;
  try {
    direct =
        ConnectionTypeState.find(id).direct.value == ConnectionType.strDirect;
  } catch (_) {}
  bool hideFps = versionCmp(ffi.ffiModel.pi.version, '1.2.0') < 0;
  bool hideMoreQuality = versionCmp(ffi.ffiModel.pi.version, '1.2.2') < 0;

  setCustomValues({double? quality, double? fps}) async {
    debugPrint("setCustomValues quality:$quality, fps:$fps");
    if (quality != null) {
      qualitySet = true;
      await bind.sessionSetCustomImageQuality(
        sessionId: sessionId,
        value: quality.toInt(),
      );
    }
    if (fps != null) {
      fpsSet = true;
      await bind.sessionSetCustomFps(sessionId: sessionId, fps: fps.toInt());
    }
    if (!qualitySet) {
      qualitySet = true;
      await bind.sessionSetCustomImageQuality(
        sessionId: sessionId,
        value: initQuality.toInt(),
      );
    }
    if (!hideFps && !fpsSet) {
      fpsSet = true;
      await bind.sessionSetCustomFps(
        sessionId: sessionId,
        fps: initFps.toInt(),
      );
    }
  }

  final btnClose = dialogButton(
    'Close',
    onPressed: () async {
      await setCustomValues();
      ffi.dialogManager.dismissAll();
    },
  );

  // quality
  final quality = await bind.sessionGetCustomImageQuality(sessionId: sessionId);
  initQuality = quality != null && quality.isNotEmpty
      ? quality[0].toDouble()
      : kDefaultQuality;
  if (initQuality < kMinQuality ||
      initQuality > (!hideMoreQuality ? kMaxMoreQuality : kMaxQuality)) {
    initQuality = kDefaultQuality;
  }
  // fps
  final fpsOption = await bind.sessionGetOption(
    sessionId: sessionId,
    arg: 'custom-fps',
  );
  initFps = fpsOption == null
      ? kDefaultFps
      : double.tryParse(fpsOption) ?? kDefaultFps;
  if (initFps < kMinFps || initFps > kMaxFps) {
    initFps = kDefaultFps;
  }

  final content = customImageQualityWidget(
    initQuality: initQuality,
    initFps: initFps,
    setQuality: (v) => setCustomValues(quality: v),
    setFps: (v) => setCustomValues(fps: v),
    showFps: !hideFps,
    showMoreQuality: !hideMoreQuality,
  );
  msgBoxCommon(ffi.dialogManager, 'Custom Image Quality', content, [btnClose]);
}

trackpadSpeedDialog(SessionID sessionId, FFI ffi) async {
  int initSpeed = ffi.inputModel.trackpadSpeed;
  final curSpeed = SimpleWrapper(initSpeed);
  final btnClose = dialogButton(
    'Close',
    onPressed: () async {
      if (curSpeed.value <= kMaxTrackpadSpeed &&
          curSpeed.value >= kMinTrackpadSpeed &&
          curSpeed.value != initSpeed) {
        await bind.sessionSetTrackpadSpeed(
          sessionId: sessionId,
          value: curSpeed.value,
        );
        await ffi.inputModel.updateTrackpadSpeed();
      }
      ffi.dialogManager.dismissAll();
    },
  );
  msgBoxCommon(
    ffi.dialogManager,
    'Trackpad speed',
    TrackpadSpeedWidget(value: curSpeed),
    [btnClose],
  );
}

void deleteConfirmDialog(Function onSubmit, String title) async {
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      await onSubmit();
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_rounded, color: Colors.red),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
            ).paddingOnly(left: 10),
          ),
        ],
      ),
      content: SizedBox.shrink(),
      actions: [
        dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        ),
        dialogButton("OK", icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void renameDialog({
  required String oldName,
  FormFieldValidator<String>? validator,
  required ValueChanged<String> onSubmit,
  Function? onCancel,
}) async {
  RxBool isInProgress = false.obs;
  var controller = TextEditingController(text: oldName);
  final formKey = GlobalKey<FormState>();
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      String text = controller.text.trim();
      if (validator != null && formKey.currentState?.validate() == false) {
        return;
      }
      isInProgress.value = true;
      onSubmit(text);
      close();
      isInProgress.value = false;
    }

    cancel() {
      onCancel?.call();
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_rounded, color: MyTheme.accent),
          Text(translate('Rename')).paddingOnly(left: 10),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: translate('Name')),
                validator: validator,
              ).workaroundFreezeLinuxMint(),
            ),
          ),
          // NOT use Offstage to wrap LinearProgressIndicator
          Obx(
            () => isInProgress.value
                ? const LinearProgressIndicator()
                : Offstage(),
          ),
        ],
      ),
      actions: [
        dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: cancel,
          isOutline: true,
        ),
        dialogButton("OK", icon: Icon(Icons.done_rounded), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: cancel,
    );
  });
}

// This dialog should not be dismissed, otherwise it will be black screen, have not reproduced this.
void showWindowsSessionsDialog(
  String type,
  String title,
  String text,
  OverlayDialogManager dialogManager,
  SessionID sessionId,
  String peerId,
  String sessions,
) {
  List<dynamic> sessionsList = [];
  try {
    sessionsList = json.decode(sessions);
  } catch (e) {
    print(e);
  }
  List<String> sids = [];
  List<String> names = [];
  for (var session in sessionsList) {
    sids.add(session['sid']);
    names.add(session['name']);
  }
  String selectedUserValue = sids.first;
  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    submit() {
      bind.sessionSendSelectedSessionId(
        sessionId: sessionId,
        sid: selectedUserValue,
      );
      close();
    }

    return CustomAlertDialog(
      title: null,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          msgboxContent(type, title, text).marginOnly(bottom: 12),
          ComboBox(
            keys: sids,
            values: names,
            initialKey: selectedUserValue,
            onChanged: (value) {
              selectedUserValue = value;
            },
          ),
        ],
      ),
      actions: [dialogButton('Connect', onPressed: submit, isOutline: false)],
    );
  });
}

void CommonConfirmDialog(
  OverlayDialogManager dialogManager,
  String content,
  VoidCallback onConfirm,
) {
  dialogManager.show((setState, close, context) {
    submit() {
      close();
      onConfirm.call();
    }

    return CustomAlertDialog(
      content: Row(
        children: [
          Expanded(
            child: Text(
              content,
              style: const TextStyle(fontSize: 15),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ).marginOnly(bottom: 12),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void changeUnlockPinDialog(String oldPin, Function() callback) {
  final pinController = TextEditingController(text: oldPin);
  final confirmController = TextEditingController(text: oldPin);
  String? pinErrorText;
  String? confirmationErrorText;
  final maxLength = bind.mainMaxEncryptLen();
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      pinErrorText = null;
      confirmationErrorText = null;
      final pin = pinController.text.trim();
      final confirm = confirmController.text.trim();
      if (pin != confirm) {
        setState(() {
          confirmationErrorText = translate(
            'The confirmation is not identical.',
          );
        });
        return;
      }
      final errorMsg = bind.mainSetUnlockPin(pin: pin);
      if (errorMsg != '') {
        setState(() {
          pinErrorText = translate(errorMsg);
        });
        return;
      }
      callback.call();
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set PIN")),
      content: Column(
        children: [
          DialogTextField(
            title: 'PIN',
            controller: pinController,
            obscureText: true,
            errorText: pinErrorText,
            maxLength: maxLength,
          ),
          DialogTextField(
            title: translate('Confirmation'),
            controller: confirmController,
            obscureText: true,
            errorText: confirmationErrorText,
            maxLength: maxLength,
          ),
        ],
      ).marginOnly(bottom: 12),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

void checkUnlockPinDialog(String correctPin, Function() passCallback) {
  final controller = TextEditingController();
  String? errorText;
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      final pin = controller.text.trim();
      if (correctPin != pin) {
        setState(() {
          errorText = translate('Wrong PIN');
        });
        return;
      }
      passCallback.call();
      close();
    }

    return CustomAlertDialog(
      content: Row(
        children: [
          Expanded(
            child: PasswordWidget(
              title: 'PIN',
              controller: controller,
              errorText: errorText,
              hintText: '',
            ),
          ),
        ],
      ).marginOnly(bottom: 12),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
