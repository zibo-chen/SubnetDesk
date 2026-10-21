import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/subnet_ui.dart';
import 'package:flutter_hbb/desktop/lan_identity_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LAN identity profiles', () {
    test('parses metadata without a password field', () {
      final identity = LanIdentityProfile.fromJson({
        'id': 'identity-id',
        'name': 'Operations',
        'username': 'operator',
        'is_default': true,
        'password': 'must-not-be-used',
      });

      expect(identity.id, 'identity-id');
      expect(identity.name, 'Operations');
      expect(identity.username, 'operator');
      expect(identity.isDefault, isTrue);
    });

    test('finds the default identity', () {
      const identities = [
        LanIdentityProfile(
          id: 'first',
          name: 'First',
          username: 'first-user',
          isDefault: false,
        ),
        LanIdentityProfile(
          id: 'default',
          name: 'Default',
          username: 'operator',
          isDefault: true,
        ),
      ];

      expect(defaultLanIdentityId(identities), 'default');
      expect(defaultLanIdentityId(const []), isNull);
    });

    test('connection payload contains only identity selection metadata', () {
      final payload =
          jsonDecode(buildLanIdentityPayload('identity-id', bindIdentity: true))
              as Map<String, dynamic>;

      expect(payload, {
        'lan_version': 1,
        'identity_id': 'identity-id',
        'bind_identity': true,
      });
      expect(payload.containsKey('username'), isFalse);
      expect(payload.containsKey('password'), isFalse);
    });

    test(
      'selection keeps a valid choice, then uses default or first account',
      () {
        const identities = [
          LanIdentityProfile(
            id: 'first',
            name: 'First',
            username: 'one',
            isDefault: false,
          ),
          LanIdentityProfile(
            id: 'default',
            name: 'Default',
            username: 'two',
            isDefault: true,
          ),
        ];
        expect(preferredLanIdentityId(identities), 'default');
        expect(
          preferredLanIdentityId(identities, selectedId: 'first'),
          'first',
        );
        expect(
          preferredLanIdentityId(identities, selectedId: 'deleted'),
          'default',
        );
        expect(
          preferredLanIdentityId([identities.first], selectedId: 'deleted'),
          'first',
        );
        expect(preferredLanIdentityId(const [], selectedId: 'deleted'), isNull);
      },
    );
  });

  Widget selector({
    List<LanIdentityProfile> identities = const [],
    String? selectedId,
    ValueChanged<String?>? onChanged,
    VoidCallback? onAdd,
    VoidCallback? onManage,
    String? errorText,
    String language = 'zh-cn',
  }) => MaterialApp(
    home: SubnetLanguage(
      languageCode: language,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: LanIdentitySelector(
              identities: identities,
              selectedId: selectedId,
              onChanged: onChanged ?? (_) {},
              onAdd: onAdd ?? () {},
              onManage: onManage ?? () {},
              errorText: errorText,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('empty account list offers account creation and management', (
    tester,
  ) async {
    var added = false;
    var managed = false;
    await tester.pumpWidget(
      selector(onAdd: () => added = true, onManage: () => managed = true),
    );
    expect(find.text('还没有保存账号，请先添加用于连接远程设备的账号。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('添加账号'));
    await tester.tap(find.text('管理账号'));
    expect(added, isTrue);
    expect(managed, isTrue);
  });

  testWidgets('saved accounts can be selected without entering credentials', (
    tester,
  ) async {
    String? selected = 'default';
    const identities = [
      LanIdentityProfile(
        id: 'default',
        name: 'Operations',
        username: 'operator',
        isDefault: true,
      ),
      LanIdentityProfile(
        id: 'other',
        name: 'Support',
        username: 'support',
        isDefault: false,
      ),
    ];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => selector(
          identities: identities,
          selectedId: selected,
          onChanged: (value) => setState(() => selected = value),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.initialValue, 'default');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support · support').last);
    await tester.pumpAndSettle();
    expect(selected, 'other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('account errors remain visible alongside recovery actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      selector(errorText: 'LAN identity does not exist', language: 'en'),
    );
    expect(find.text('LAN identity does not exist'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('account selector lays out inside the connection dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomAlertDialog(
            title: const Text('Select connection account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Use a saved account to connect to the remote device.',
                ),
                LanIdentitySelector(
                  identities: const [
                    LanIdentityProfile(
                      id: 'account',
                      name: 'Account',
                      username: 'operator',
                      isDefault: false,
                    ),
                  ],
                  selectedId: 'account',
                  onChanged: (_) {},
                  onAdd: () {},
                  onManage: () {},
                ),
                CheckboxListTile(
                  value: true,
                  onChanged: (_) {},
                  title: const Text('Remember this account for this device'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select connection account'), findsOneWidget);
  });
}
