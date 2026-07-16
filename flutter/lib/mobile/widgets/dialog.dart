import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:get/get.dart';

import '../../common.dart';

void setPrivacyModeDialog(
  OverlayDialogManager dialogManager,
  List<TToggleMenu> privacyModeList,
  RxString privacyModeState,
) async {
  dialogManager.dismissAll();
  dialogManager.show(
    (setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('Privacy mode')),
        content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: privacyModeList
              .map(
                (value) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: value.child,
                  value: value.value,
                  onChanged: value.onChanged,
                ),
              )
              .toList(),
        ),
      );
    },
    backDismiss: true,
    clickMaskDismiss: true,
  );
}
