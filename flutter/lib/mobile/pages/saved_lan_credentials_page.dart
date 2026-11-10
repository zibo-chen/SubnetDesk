import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/widgets/subnet_ui.dart';

class AndroidLanCredentials {
  static const channel = MethodChannel(
    'com.zibochen.subnetdesk/lan_credentials',
  );

  Future<List<String>> list() async =>
      await channel.invokeListMethod<String>('list') ?? const [];

  Future<void> delete(String fingerprint) =>
      channel.invokeMethod<void>('delete', {'fingerprint': fingerprint});
}

class SavedLanCredentialsPage extends StatefulWidget {
  const SavedLanCredentialsPage({super.key, this.deviceNames = const {}});

  final Map<String, String> deviceNames;

  @override
  State<SavedLanCredentialsPage> createState() =>
      _SavedLanCredentialsPageState();
}

class _SavedLanCredentialsPageState extends State<SavedLanCredentialsPage> {
  final _store = AndroidLanCredentials();
  late Future<List<String>> _entries = _store.list();
  bool _deleting = false;

  void _reload() {
    final entries = _store.list();
    setState(() {
      _entries = entries;
    });
  }

  Future<void> _delete(String fingerprint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          subnetText(context, '删除已保存的凭据？', 'Forget saved credentials?'),
        ),
        content: Text(
          subnetText(
            context,
            '下次连接此设备时需要重新输入用户名和密码。',
            'You will need to enter the username and password the next time you connect to this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(subnetText(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(subnetText(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _store.delete(fingerprint);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              subnetText(
                context,
                '无法删除已保存的凭据，请重试。',
                'Could not delete saved credentials. Please try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(subnetText(context, '已保存的 LAN 凭据', 'Saved LAN credentials')),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            subnetText(
              context,
              '凭据仅在此设备加密保存，并绑定到被控设备指纹。修改密码时，请先删除凭据，再重新连接并保存。',
              'Credentials are encrypted on this device and bound to the remote device fingerprint. To change a password, forget the credential, then reconnect and save it again.',
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<String>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subnetText(
                          context,
                          '无法读取已保存的凭据。',
                          'Could not load saved credentials.',
                        ),
                      ),
                      TextButton(
                        onPressed: _reload,
                        child: Text(subnetText(context, '重试', 'Retry')),
                      ),
                    ],
                  ),
                );
              }
              final entries = snapshot.data ?? const [];
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    subnetText(context, '没有已保存的凭据', 'No saved credentials'),
                  ),
                );
              }
              return ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: Text(
                    widget.deviceNames[entries[index]] ?? entries[index],
                  ),
                  subtitle: widget.deviceNames.containsKey(entries[index])
                      ? Text(entries[index])
                      : null,
                  trailing: IconButton(
                    tooltip: subnetText(context, '删除', 'Delete'),
                    onPressed: _deleting ? null : () => _delete(entries[index]),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
